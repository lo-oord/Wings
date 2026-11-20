// wings-media-api — the only holder of the Tigris credentials.
//
// Flow for an upload:
//   1. Flutter sends its Firebase ID token.
//   2. This Worker verifies the RS256 signature and the issuer/audience/expiry.
//   3. The uid is taken from the verified token (never from the request body).
//   4. The Worker returns short-lived signed PUT URLs for Tigris.
//   5. Flutter uploads the bytes straight to Tigris.
//   6. Flutter stores only the object keys in Firestore.
//
// Downloads are the same in reverse. The bucket stays private.
//
// Endpoints
//   GET  /health      service identity, version and a real Tigris probe
//   POST /v1/uploads  signed PUT URLs for pictures, video, avatar, cover
//   POST /v1/download signed GET URLs (HTTP Range is answered by Tigris)
//   POST /v1/delete   deletes objects under the caller's own prefix
//
// Because the signed GET only signs `host`, the player's `Range` header is not
// part of the signature: libmpv/media_kit can seek with 206 responses directly
// from Tigris, and the Worker never proxies video bytes.

import {
  AuthError,
  bearerToken,
  verifyFirebaseToken,
} from './firebase.js';
import { presignUrl } from './sigv4.js';
import {
  MAX_DELETE_KEYS,
  MAX_DOWNLOAD_KEYS,
  MAX_FILES,
  MAX_IMAGE_BYTES,
  MAX_VIDEO_BYTES,
  MediaError,
  buildObjectKey,
  isOwnKey,
  isReadableKey,
  limitFor,
  normalizeUploadRequest,
} from './media.js';

const UPLOAD_TTL = 300; // 5 minutes to start the upload
const DOWNLOAD_TTL = 600;
const HEALTH_PROBE_TTL_MS = 60_000;

/** A key that is never written: a HEAD on it proves Tigris is reachable. */
const HEALTH_PROBE_KEY = '_health/ping';

function json(body, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      'content-type': 'application/json; charset=utf-8',
      'cache-control': 'no-store',
      'x-content-type-options': 'nosniff',
    },
  });
}

function failure(status, code) {
  return json({ error: code }, status);
}

async function readJson(request) {
  const type = request.headers.get('content-type') ?? '';
  if (!type.includes('application/json')) throw new Error('unsupported-media-type');
  const length = Number(request.headers.get('content-length') ?? '0');
  if (length > 64 * 1024) throw new Error('body-too-large');
  const body = await request.json();
  if (!body || typeof body !== 'object') throw new Error('bad-body');
  return body;
}

function config(env) {
  const missing = [
    'FIREBASE_PROJECT_ID',
    'TIGRIS_ACCESS_KEY_ID',
    'TIGRIS_SECRET_ACCESS_KEY',
    'TIGRIS_BUCKET',
  ].filter((name) => !env[name]);
  if (missing.length > 0) {
    // Names only: no values ever appear in a response or a log line.
    return { error: `missing-config:${missing.join(',')}` };
  }
  return {
    projectId: env.FIREBASE_PROJECT_ID,
    accessKeyId: env.TIGRIS_ACCESS_KEY_ID,
    secretAccessKey: env.TIGRIS_SECRET_ACCESS_KEY,
    bucket: env.TIGRIS_BUCKET,
    endpoint: env.TIGRIS_ENDPOINT ?? 'https://t3.storage.dev',
    region: env.TIGRIS_REGION ?? 'auto',
  };
}

function sign(options) {
  return presignUrl({
    endpoint: options.endpoint,
    region: options.region,
    accessKeyId: options.accessKeyId,
    secretAccessKey: options.secretAccessKey,
    ...options.sign,
  });
}

// The probe answer is cached for a minute so a monitoring loop cannot turn a
// health check into load on the bucket.
let probeCache = { at: 0, result: null };

/**
 * Signs a HEAD for a key that does not exist. A 2xx/404 means Tigris accepted
 * the signature and answered; 403 means the credentials were refused; anything
 * else (or a network failure) is reported as unreachable. Only the status code
 * is returned — never a credential or a signed URL.
 */
async function storageHealth(settings) {
  if (probeCache.result && Date.now() - probeCache.at < HEALTH_PROBE_TTL_MS) {
    return probeCache.result;
  }
  const started = Date.now();
  let result;
  try {
    const url = await sign({
      ...settings,
      sign: {
        method: 'HEAD',
        bucket: settings.bucket,
        key: HEALTH_PROBE_KEY,
        expires: 60,
      },
    });
    const response = await fetch(url, { method: 'HEAD' });
    result = {
      reachable: true,
      http: response.status,
      authorization:
        response.status === 403 ? 'refused' : response.status < 500 ? 'accepted' : 'unknown',
    };
  } catch {
    result = { reachable: false, authorization: 'unknown' };
  }
  result = { ...result, latencyMs: Date.now() - started };
  probeCache = { at: Date.now(), result };
  return result;
}

function versionOf(env) {
  const metadata = env.CF_VERSION_METADATA;
  if (metadata && typeof metadata === 'object') {
    return {
      id: typeof metadata.id === 'string' ? metadata.id : null,
      tag: typeof metadata.tag === 'string' ? metadata.tag : null,
      deployedAt: typeof metadata.timestamp === 'string' ? metadata.timestamp : null,
    };
  }
  return { id: env.WORKER_VERSION ?? 'dev', tag: null, deployedAt: null };
}

async function handleHealth(env) {
  const settings = config(env);
  const version = versionOf(env);
  if (settings.error) {
    return json({
      service: 'wings-media-api',
      status: 'degraded',
      configured: false,
      version,
      storage: { reachable: false, authorization: 'unknown' },
      reason: settings.error,
    });
  }
  const storage = await storageHealth(settings);
  return json({
    service: 'wings-media-api',
    status: storage.reachable && storage.authorization === 'accepted' ? 'ok' : 'degraded',
    configured: true,
    version,
    endpoint: settings.endpoint,
    bucket: settings.bucket,
    storage,
    endpoints: {
      uploads: '/v1/uploads',
      download: '/v1/download',
      delete: '/v1/delete',
    },
    limits: {
      maxImageBytes: MAX_IMAGE_BYTES,
      maxVideoBytes: MAX_VIDEO_BYTES,
      maxFiles: MAX_FILES,
      maxDownloadKeys: MAX_DOWNLOAD_KEYS,
      maxDeleteKeys: MAX_DELETE_KEYS,
    },
  });
}

async function handleUploads(request, env, user) {
  const settings = config(env);
  if (settings.error) return failure(500, settings.error);
  const body = await readJson(request);
  const { purpose, postId, files } = normalizeUploadRequest(body);
  const objects = [];
  for (const file of files) {
    const key = buildObjectKey({
      uid: user.uid,
      purpose,
      postId,
      contentType: file.contentType,
    });
    const uploadUrl = await sign({
      ...settings,
      sign: {
        method: 'PUT',
        bucket: settings.bucket,
        key,
        expires: UPLOAD_TTL,
      },
    });
    objects.push({
      key,
      uploadUrl,
      headers: { 'Content-Type': file.contentType },
      expiresIn: UPLOAD_TTL,
      maxBytes: limitFor(file.contentType),
    });
  }
  return json({ objects, purpose, expiresIn: UPLOAD_TTL });
}

async function handleDownload(request, env) {
  const settings = config(env);
  if (settings.error) return failure(500, settings.error);
  const body = await readJson(request);
  const keys = body.keys;
  if (!Array.isArray(keys) || keys.length === 0 || keys.length > MAX_DOWNLOAD_KEYS) {
    return failure(400, 'bad-key-count');
  }
  const urls = {};
  for (const key of keys) {
    // Any signed-in member may view community and profile media, but a key can
    // never point outside the namespaces this service owns.
    if (!isReadableKey(key)) return failure(400, 'bad-key');
    urls[key] = await sign({
      ...settings,
      sign: {
        method: 'GET',
        bucket: settings.bucket,
        key,
        expires: DOWNLOAD_TTL,
      },
    });
  }
  return json({ urls, expiresIn: DOWNLOAD_TTL, acceptsRange: true });
}

async function handleDelete(request, env, user) {
  const settings = config(env);
  if (settings.error) return failure(500, settings.error);
  const body = await readJson(request);
  const keys = body.keys;
  if (!Array.isArray(keys) || keys.length === 0 || keys.length > MAX_DELETE_KEYS) {
    return failure(400, 'bad-key-count');
  }
  for (const key of keys) {
    // Ownership is structural: a member can only ever delete under their own
    // prefix, whatever the client sends.
    if (!isOwnKey(user.uid, key)) return failure(403, 'not-owner');
  }
  const deleted = [];
  for (const key of keys) {
    const url = await sign({
      ...settings,
      sign: {
        method: 'DELETE',
        bucket: settings.bucket,
        key,
        expires: 60,
      },
    });
    try {
      const response = await fetch(url, { method: 'DELETE' });
      if (response.ok || response.status === 404) deleted.push(key);
    } catch {
      // A failed cleanup leaves the object; the post was never saved, so the
      // only cost is storage and it can be swept later.
    }
  }
  return json({ deleted });
}

export default {
  async fetch(request, env) {
    const url = new URL(request.url);
    if (request.method === 'GET' && (url.pathname === '/' || url.pathname === '/health')) {
      return handleHealth(env);
    }
    if (request.method === 'OPTIONS') {
      return new Response(null, {
        status: 204,
        headers: {
          'access-control-allow-origin': 'https://wings.app',
          'access-control-allow-headers': 'authorization, content-type',
          'access-control-allow-methods': 'POST, OPTIONS',
          'access-control-max-age': '600',
        },
      });
    }
    if (request.method !== 'POST') return failure(405, 'method-not-allowed');

    const settings = config(env);
    if (settings.error) return failure(500, settings.error);

    let user;
    try {
      const token = bearerToken(request);
      user = await verifyFirebaseToken(token, settings.projectId);
    } catch (error) {
      const code = error instanceof AuthError ? error.message : 'unauthorized';
      return failure(401, code);
    }

    try {
      switch (url.pathname) {
        case '/v1/uploads':
          return await handleUploads(request, env, user);
        case '/v1/download':
          return await handleDownload(request, env, user);
        case '/v1/delete':
          return await handleDelete(request, env, user);
        default:
          return failure(404, 'not-found');
      }
    } catch (error) {
      if (error instanceof MediaError) return failure(error.status, error.code);
      const message = error instanceof Error ? error.message : 'bad-request';
      if (message === 'body-too-large') return failure(413, message);
      if (message === 'unsupported-media-type' || message === 'bad-body') {
        return failure(415, message);
      }
      return failure(500, 'request-failed');
    }
  },
};
