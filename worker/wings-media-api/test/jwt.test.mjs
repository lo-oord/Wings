import assert from 'node:assert/strict';
import { generateKeyPairSync, sign } from 'node:crypto';
import test from 'node:test';

import { AuthError, verifyFirebaseToken } from '../src/firebase.js';

const PROJECT = 'wings-test-project';
const KID = 'test-key-1';
const { privateKey, publicKey } = generateKeyPairSync('rsa', {
  modulusLength: 2048,
});
const jwk = { ...publicKey.export({ format: 'jwk' }), kid: KID, alg: 'RS256' };

function base64url(value) {
  return Buffer.from(value)
    .toString('base64')
    .replace(/\+/g, '-')
    .replace(/\//g, '_')
    .replace(/=+$/, '');
}

function token({
  claims = {},
  header = { alg: 'RS256', kid: KID, typ: 'JWT' },
  key = privateKey,
} = {}) {
  const now = Math.floor(Date.now() / 1000);
  const payload = {
    iss: `https://securetoken.google.com/${PROJECT}`,
    aud: PROJECT,
    sub: 'uid-123',
    iat: now - 10,
    exp: now + 3600,
    ...claims,
  };
  const head = base64url(JSON.stringify(header));
  const body = base64url(JSON.stringify(payload));
  const signature = sign('RSA-SHA256', Buffer.from(`${head}.${body}`), key);
  return `${head}.${body}.${base64url(signature)}`;
}

const options = { keys: [jwk] };

test('accepts a correctly signed token and returns its subject', async () => {
  const result = await verifyFirebaseToken(token(), PROJECT, options);
  assert.equal(result.uid, 'uid-123');
});

test('rejects a token signed with another key', async () => {
  const { privateKey: other } = generateKeyPairSync('rsa', {
    modulusLength: 2048,
  });
  await assert.rejects(
    verifyFirebaseToken(token({ key: other }), PROJECT, options),
    (error) => error instanceof AuthError && error.message === 'bad-signature',
  );
});

test('rejects a tampered payload', async () => {
  const [head, , signature] = token().split('.');
  const tampered = base64url(
    JSON.stringify({
      iss: `https://securetoken.google.com/${PROJECT}`,
      aud: PROJECT,
      sub: 'someone-else',
      iat: Math.floor(Date.now() / 1000) - 10,
      exp: Math.floor(Date.now() / 1000) + 3600,
    }),
  );
  await assert.rejects(
    verifyFirebaseToken(`${head}.${tampered}.${signature}`, PROJECT, options),
    (error) => error instanceof AuthError && error.message === 'bad-signature',
  );
});

test('rejects a wrong issuer, a wrong audience and an expired token', async () => {
  const now = Math.floor(Date.now() / 1000);
  const cases = [
    { iss: 'https://securetoken.google.com/other' },
    { aud: 'other-project' },
    { exp: now - 60 },
    { iat: now + 3600 },
    { sub: '' },
  ];
  for (const claims of cases) {
    await assert.rejects(
      verifyFirebaseToken(token({ claims }), PROJECT, options),
      AuthError,
    );
  }
});

test('rejects an unsigned token and an unknown key id', async () => {
  await assert.rejects(
    verifyFirebaseToken(
      token({ header: { alg: 'none', kid: KID, typ: 'JWT' } }),
      PROJECT,
      options,
    ),
    (error) => error instanceof AuthError && error.message === 'bad-algorithm',
  );
  await assert.rejects(
    verifyFirebaseToken(
      token({ header: { alg: 'RS256', kid: 'missing', typ: 'JWT' } }),
      PROJECT,
      { keys: [jwk], fetchImpl: async () => ({ ok: false }) },
    ),
    AuthError,
  );
});

test('rejects a token that is not a JWT at all', async () => {
  await assert.rejects(verifyFirebaseToken('hello', PROJECT, options), AuthError);
});
