// Firebase ID token verification for Cloudflare Workers.
//
// A JWT is never trusted because it decodes: the RS256 signature is checked
// against Google's published keys, and the issuer, audience, expiry and subject
// are all validated. Only then is the uid read from the token.

const JWK_URL =
  'https://www.googleapis.com/service_accounts/v1/jwk/securetoken@system.gserviceaccount.com';

/** One hour, the cache lifetime Google asks clients to respect. */
const KEY_TTL_MS = 60 * 60 * 1000;

let cache = { keys: null, fetchedAt: 0 };

export class AuthError extends Error {
  constructor(message) {
    super(message);
    this.name = 'AuthError';
  }
}

function base64UrlToBytes(value) {
  const normalized = value.replace(/-/g, '+').replace(/_/g, '/');
  const padded = normalized + '='.repeat((4 - (normalized.length % 4)) % 4);
  const binary = atob(padded);
  const bytes = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i++) bytes[i] = binary.charCodeAt(i);
  return bytes;
}

function decodeSegment(segment) {
  const text = new TextDecoder().decode(base64UrlToBytes(segment));
  const value = JSON.parse(text);
  if (!value || typeof value !== 'object') throw new AuthError('bad-token');
  return value;
}

async function fetchKeys(fetchImpl) {
  const response = await fetchImpl(JWK_URL);
  if (!response.ok) throw new AuthError('key-fetch-failed');
  const body = await response.json();
  const keys = Array.isArray(body?.keys) ? body.keys : [];
  if (keys.length === 0) throw new AuthError('no-keys');
  cache = { keys, fetchedAt: Date.now() };
  return keys;
}

async function keysFor(fetchImpl, kid) {
  const fresh = cache.keys && Date.now() - cache.fetchedAt < KEY_TTL_MS;
  if (fresh && cache.keys.some((key) => key.kid === kid)) return cache.keys;
  return fetchKeys(fetchImpl);
}

async function importKey(jwk) {
  return crypto.subtle.importKey(
    'jwk',
    { kty: jwk.kty, n: jwk.n, e: jwk.e, alg: 'RS256', ext: true },
    { name: 'RSASSA-PKCS1-v1_5', hash: 'SHA-256' },
    false,
    ['verify'],
  );
}

/**
 * Verifies a Firebase ID token and returns `{ uid, claims }`.
 *
 * @param {string} token raw JWT (without the `Bearer ` prefix)
 * @param {string} projectId Firebase project id (`aud` and issuer suffix)
 * @param {{ fetchImpl?: typeof fetch, now?: number, keys?: object[] }} options
 *        `keys` lets the tests inject a JWKS instead of reaching the network.
 */
export async function verifyFirebaseToken(token, projectId, options = {}) {
  const fetchImpl = options.fetchImpl ?? fetch;
  const now = options.now ?? Date.now();
  if (typeof token !== 'string' || token.length === 0) {
    throw new AuthError('missing-token');
  }
  if (typeof projectId !== 'string' || projectId.length === 0) {
    throw new AuthError('missing-project');
  }
  const parts = token.split('.');
  if (parts.length !== 3) throw new AuthError('malformed-token');

  const header = decodeSegment(parts[0]);
  if (header.alg !== 'RS256') throw new AuthError('bad-algorithm');
  const kid = header.kid;
  if (typeof kid !== 'string' || kid.length === 0) throw new AuthError('missing-kid');

  const keys = options.keys ?? (await keysFor(fetchImpl, kid));
  const jwk = keys.find((candidate) => candidate.kid === kid);
  if (!jwk) throw new AuthError('unknown-kid');

  const key = await importKey(jwk);
  const signed = new TextEncoder().encode(`${parts[0]}.${parts[1]}`);
  const signature = base64UrlToBytes(parts[2]);
  const valid = await crypto.subtle.verify(
    { name: 'RSASSA-PKCS1-v1_5' },
    key,
    signature,
    signed,
  );
  if (!valid) throw new AuthError('bad-signature');

  const claims = decodeSegment(parts[1]);
  const issuer = `https://securetoken.google.com/${projectId}`;
  if (claims.iss !== issuer) throw new AuthError('bad-issuer');
  if (claims.aud !== projectId) throw new AuthError('bad-audience');
  if (typeof claims.exp !== 'number' || claims.exp * 1000 <= now) {
    throw new AuthError('expired');
  }
  if (typeof claims.iat !== 'number' || claims.iat * 1000 > now + 5 * 60 * 1000) {
    throw new AuthError('bad-issued-at');
  }
  const uid = claims.sub;
  if (typeof uid !== 'string' || uid.length === 0 || uid.length > 128) {
    throw new AuthError('bad-subject');
  }
  // A sign-in that already happened is a valid `auth_time`, but Firebase adds
  // it only for fresh credentials; nothing else is required here.
  if (claims.auth_time != null && typeof claims.auth_time !== 'number') {
    throw new AuthError('bad-auth-time');
  }
  return { uid, claims };
}

/** Reads the bearer token of a request. */
export function bearerToken(request) {
  const header = request.headers.get('Authorization') ?? '';
  const match = /^Bearer\s+(.+)$/i.exec(header.trim());
  if (!match) throw new AuthError('missing-token');
  return match[1];
}

/** Test-only hook so a unit test can start from a clean key cache. */
export function resetKeyCache() {
  cache = { keys: null, fetchedAt: 0 };
}
