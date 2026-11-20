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

import {
  AuthError,
  bearerToken,
  verifyFirebaseToken,
} from './firebase.js';
import { presignUrl } from './sigv4.js';

const MAX_UPLOAD_BYTES = 5 * 1024 * 1024;
const MAX_FILES = 4;
const MAX_DOWNLOAD_KEYS = 20;
const UPLOAD_TTL = 300; // 5 minutes to start the upload
const DOWNLOAD_TTL = 600;
const ALLOWED_TYPES = new Map([
  ['image/jpeg', 'jpg'],
  ['image/png', 'png'],
  ['image/webp', 'webp'],
]);

const KEY_PATTERN =
  /^users\/([A-Za-z0-9_-]{1,128})\/posts\/([A-Za-z0-9]{1,64})\/([A-Za-z0-9-]{8,64})\.(jpg|png|webp)$/;

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

async function handleUploads(request, env, user) {
  const settings = config(env);
  if (settings.error) return failure(500, settings.error);
  const body = await readJson(request);
  const postId = body.postId;
  if (typeof postId !== 'string' || !/^[A-Za-z0-9]{1,64}$/.test(postId)) {
    return failure(400, 'bad-post-id');
  }
  const files = body.files;
  if (!Array.isArray(files) || files.length === 0 || files.length > MAX_FILES) {
    return failure(400, 'bad-file-count');
  }
  for (const file of files) {
    if (!file || typeof file !== 'object') return failure(400, 'bad-file');
    if (!ALLOWED_TYPES.has(file.contentType)) {
      return failure(415, 'unsupported-type');
    }
    if (
      typeof file.size !== 'number' ||
      !Number.isFinite(file.size) ||
      file.size <= 0 ||
      file.size > MAX_UPLOAD_BYTES
    ) {
      return failure(413, 'file-too-large');
    }
  }
  const objects = [];
  for (const file of files) {
    const extension = ALLOWED_TYPES.get(file.contentType);
    const key = `users/${user.uid}/posts/${postId}/${crypto.randomUUID()}.${extension}`;
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
    });
  }
  return json({ objects, expiresIn: UPLOAD_TTL });
}

async function handleDownload(request, env, user) {
  const settings = config(env);
  if (settings.error) return failure(500, settings.error);
  const body = await readJson(request);
  const keys = body.keys;
  if (!Array.isArray(keys) || keys.length === 0 || keys.length > MAX_DOWNLOAD_KEYS) {
    return failure(400, 'bad-key-count');
  }
  const urls = {};
  for (const key of keys) {
    if (typeof key !== 'string' || !KEY_PATTERN.test(key)) {
      return failure(400, 'bad-key');
    }
    // Any signed-in member may view community pictures, but a key can never
    // point outside the posts namespace.
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
  return json({ urls, expiresIn: DOWNLOAD_TTL });
}

async function handleDelete(request, env, user) {
  const settings = config(env);
  if (settings.error) return failure(500, settings.error);
  const body = await readJson(request);
  const keys = body.keys;
  if (!Array.isArray(keys) || keys.length === 0 || keys.length > MAX_FILES * 2) {
    return failure(400, 'bad-key-count');
  }
  const ownPrefix = `users/${user.uid}/`;
  for (const key of keys) {
    // Ownership is structural: a member can only ever delete under their own
    // prefix, whatever the client sends.
    if (typeof key !== 'string' || !KEY_PATTERN.test(key) || !key.startsWith(ownPrefix)) {
      return failure(403, 'not-owner');
    }
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
      return json({
        service: 'wings-media-api',
        status: 'ok',
        uploads: '/v1/uploads',
        download: '/v1/download',
        delete: '/v1/delete',
      });
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
      const message = error instanceof Error ? error.message : 'bad-request';
      if (message === 'body-too-large') return failure(413, message);
      if (message === 'unsupported-media-type' || message === 'bad-body') {
        return failure(415, message);
      }
      return failure(500, 'request-failed');
    }
  },
};
