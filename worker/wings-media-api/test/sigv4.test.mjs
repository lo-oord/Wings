import assert from 'node:assert/strict';
import test from 'node:test';

import { encodeKeyPath, encodeRfc3986, presignUrl } from '../src/sigv4.js';

// The reference vector from the AWS documentation for query-string
// authentication (GET Object). Matching it proves the canonical request,
// credential scope and signing-key derivation are all correct.
const REFERENCE = {
  endpoint: 'https://examplebucket.s3.amazonaws.com',
  bucket: '',
  key: 'test.txt',
  region: 'us-east-1',
  accessKeyId: 'AKIAIOSFODNN7EXAMPLE',
  secretAccessKey: 'wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY',
  expires: 86400,
  now: new Date(Date.UTC(2013, 4, 24, 0, 0, 0)),
};

test('presigns the AWS reference request exactly', async () => {
  const url = await presignUrl({ method: 'GET', ...REFERENCE });
  assert.match(
    url,
    /X-Amz-Signature=aeeed9bbccd4d02ee5c0109b86d86835f995330da4c265957d157751f604d404$/,
  );
});

test('includes the documented query parameters and no credentials', async () => {
  const url = await presignUrl({ method: 'GET', ...REFERENCE });
  const query = new URL(url).searchParams;
  assert.equal(query.get('X-Amz-Algorithm'), 'AWS4-HMAC-SHA256');
  assert.equal(
    query.get('X-Amz-Credential'),
    'AKIAIOSFODNN7EXAMPLE/20130524/us-east-1/s3/aws4_request',
  );
  assert.equal(query.get('X-Amz-Date'), '20130524T000000Z');
  assert.equal(query.get('X-Amz-Expires'), '86400');
  assert.equal(query.get('X-Amz-SignedHeaders'), 'host');
  assert.ok(!url.includes(REFERENCE.secretAccessKey));
});

test('a different object, method or expiry changes the signature', async () => {
  const base = await presignUrl({ method: 'GET', ...REFERENCE });
  const otherKey = await presignUrl({
    method: 'GET',
    ...REFERENCE,
    key: 'test2.txt',
  });
  const put = await presignUrl({ method: 'PUT', ...REFERENCE });
  const longer = await presignUrl({ method: 'GET', ...REFERENCE, expires: 60 });
  const signatures = new Set(
    [base, otherKey, put, longer].map((value) =>
      new URL(value).searchParams.get('X-Amz-Signature'),
    ),
  );
  assert.equal(signatures.size, 4);
});

test('path-style keys keep their separators and encode special characters', async () => {
  const url = await presignUrl({
    ...REFERENCE,
    method: 'PUT',
    endpoint: 'https://t3.storage.dev',
    bucket: 'wings-media',
    key: 'users/abc/posts/p1/file-1.jpg',
    region: 'auto',
    accessKeyId: 'key',
    secretAccessKey: 'secret',
  });
  assert.ok(url.startsWith('https://t3.storage.dev/wings-media/users/abc/posts/p1/file-1.jpg?'));
  assert.equal(encodeKeyPath('a b/c.jpg'), 'a%20b/c.jpg');
  assert.equal(encodeRfc3986("a!'()*b"), 'a%21%27%28%29%2Ab');
});

test('an object with spaces is encoded in the canonical path', async () => {
  const url = await presignUrl({
    ...REFERENCE,
    method: 'GET',
    bucket: 'wings-media',
    endpoint: 'https://t3.storage.dev',
    key: 'users/a b/x.jpg',
  });
  assert.ok(url.includes('/wings-media/users/a%20b/x.jpg'));
});
