// AWS Signature V4 presigning for the S3-compatible Tigris endpoint.
//
// Only query-string presigning is implemented, which is what the app needs:
// the Worker hands out a short-lived URL and the bytes travel directly between
// the device and Tigris. The secret never leaves the Worker.

const ALGORITHM = 'AWS4-HMAC-SHA256';
const SERVICE = 's3';

function hex(buffer) {
  const bytes = new Uint8Array(buffer);
  let out = '';
  for (const byte of bytes) {
    out += byte.toString(16).padStart(2, '0');
  }
  return out;
}

async function sha256Hex(value) {
  const bytes = typeof value === 'string' ? new TextEncoder().encode(value) : value;
  return hex(await crypto.subtle.digest('SHA-256', bytes));
}

async function hmac(key, value) {
  const cryptoKey = await crypto.subtle.importKey(
    'raw',
    key,
    { name: 'HMAC', hash: 'SHA-256' },
    false,
    ['sign'],
  );
  return crypto.subtle.sign('HMAC', cryptoKey, new TextEncoder().encode(value));
}

/** RFC 3986 encoding, as SigV4 requires (encodeURIComponent differs on `!'()*`). */
export function encodeRfc3986(value) {
  return encodeURIComponent(value).replace(
    /[!'()*]/g,
    (char) => '%' + char.charCodeAt(0).toString(16).toUpperCase(),
  );
}

/** Encodes an object key while keeping its `/` separators. */
export function encodeKeyPath(key) {
  return key.split('/').map(encodeRfc3986).join('/');
}

function stamp(date) {
  const iso = date.toISOString().replace(/[:-]|\.\d{3}/g, '');
  return { amzDate: iso, dateStamp: iso.slice(0, 8) };
}

/**
 * Builds a presigned URL for a private object.
 *
 * @param {object} options
 * @param {'GET'|'PUT'|'DELETE'} options.method
 * @param {string} options.endpoint   e.g. https://t3.storage.dev
 * @param {string} options.bucket
 * @param {string} options.key
 * @param {string} options.region
 * @param {string} options.accessKeyId
 * @param {string} options.secretAccessKey
 * @param {number} options.expires    seconds, 1..604800
 * @param {Date}   [options.now]
 * @returns {Promise<string>}
 */
export async function presignUrl({
  method,
  endpoint,
  bucket,
  key,
  region,
  accessKeyId,
  secretAccessKey,
  expires,
  now = new Date(),
}) {
  const url = new URL(endpoint);
  const host = url.host;
  const { amzDate, dateStamp } = stamp(now);
  const credentialScope = `${dateStamp}/${region}/${SERVICE}/aws4_request`;
  // Path-style (`/bucket/key`) is what the app uses; an empty bucket builds a
  // virtual-hosted path, which is also how the AWS reference vector is signed.
  const canonicalUri = bucket
    ? `/${encodeRfc3986(bucket)}/${encodeKeyPath(key)}`
    : `/${encodeKeyPath(key)}`;

  const query = new Map([
    ['X-Amz-Algorithm', ALGORITHM],
    ['X-Amz-Credential', `${accessKeyId}/${credentialScope}`],
    ['X-Amz-Date', amzDate],
    ['X-Amz-Expires', String(expires)],
    ['X-Amz-SignedHeaders', 'host'],
  ]);
  const canonicalQuery = [...query.entries()]
    .map(([name, value]) => `${encodeRfc3986(name)}=${encodeRfc3986(value)}`)
    .sort()
    .join('&');

  const canonicalRequest = [
    method,
    canonicalUri,
    canonicalQuery,
    `host:${host}\n`,
    'host',
    'UNSIGNED-PAYLOAD',
  ].join('\n');

  const stringToSign = [
    ALGORITHM,
    amzDate,
    credentialScope,
    await sha256Hex(canonicalRequest),
  ].join('\n');

  const dateKey = await hmac(new TextEncoder().encode(`AWS4${secretAccessKey}`), dateStamp);
  const regionKey = await hmac(dateKey, region);
  const serviceKey = await hmac(regionKey, SERVICE);
  const signingKey = await hmac(serviceKey, 'aws4_request');
  const signature = hex(await hmac(signingKey, stringToSign));

  return `${url.origin}${canonicalUri}?${canonicalQuery}&X-Amz-Signature=${signature}`;
}
