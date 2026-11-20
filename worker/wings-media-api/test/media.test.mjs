import assert from 'node:assert/strict';
import test from 'node:test';

import {
  MAX_VIDEO_BYTES,
  MediaError,
  buildObjectKey,
  isOwnKey,
  isReadableKey,
  keyOwner,
  limitFor,
  normalizeUploadRequest,
} from '../src/media.js';

const uid = 'Ab3_x-9';

test('post keys keep the original layout the Flutter client already stores', () => {
  const key = buildObjectKey({
    uid,
    postId: 'p1AbC',
    contentType: 'image/jpeg',
    id: '11111111-2222-3333-4444-555555555555',
  });
  assert.equal(
    key,
    'users/Ab3_x-9/posts/p1AbC/11111111-2222-3333-4444-555555555555.jpg',
  );
  assert.equal(keyOwner(key), uid);
  assert.ok(isReadableKey(key));
  assert.ok(isOwnKey(uid, key));
  assert.ok(!isOwnKey('someone-else', key));
});

test('avatar and cover keys live under the same structural owner prefix', () => {
  const avatar = buildObjectKey({
    uid,
    purpose: 'avatar',
    contentType: 'image/webp',
    id: 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee',
  });
  const cover = buildObjectKey({
    uid,
    purpose: 'cover',
    contentType: 'image/png',
    id: 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee',
  });
  assert.equal(
    avatar,
    'users/Ab3_x-9/profile/avatar/aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee.webp',
  );
  assert.equal(
    cover,
    'users/Ab3_x-9/profile/cover/aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee.png',
  );
  assert.equal(keyOwner(avatar), uid);
  assert.ok(isReadableKey(cover));
});

test('a profile picture cannot be a video', () => {
  assert.throws(
    () =>
      buildObjectKey({
        uid,
        purpose: 'avatar',
        contentType: 'video/mp4',
        id: 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee',
      }),
    (error) => error instanceof MediaError && error.code === 'unsupported-type',
  );
});

test('keys outside the owned namespaces are not readable', () => {
  for (const key of [
    'users/Ab3_x-9/private/avatar',
    'users/Ab3_x-9/profile/avatar',
    'users/Ab3_x-9/posts/p1/x.jpg',
    '../users/Ab3_x-9/posts/p1/11111111-2222-3333-4444-555555555555.jpg',
    'users/Ab3_x-9/profile/avatar/../../x.jpg',
    'users/Ab3_x-9/posts/p1/11111111-2222-3333-4444-555555555555.gif',
  ]) {
    assert.equal(keyOwner(key), null, key);
    assert.ok(!isReadableKey(key), key);
  }
});

test('upload requests without a purpose keep the phase-one shape', () => {
  const request = normalizeUploadRequest({
    postId: 'p1AbC',
    files: [
      { contentType: 'image/jpeg', size: 1024 },
      { contentType: 'video/mp4', size: MAX_VIDEO_BYTES },
    ],
  });
  assert.equal(request.purpose, 'post');
  assert.equal(request.postId, 'p1AbC');
  assert.equal(request.files.length, 2);
});

test('upload requests validate purpose, post id, count, type and size', () => {
  const file = { contentType: 'image/jpeg', size: 1024 };
  assert.throws(
    () => normalizeUploadRequest({ purpose: 'story', files: [file] }),
    /bad-purpose/,
  );
  assert.throws(
    () => normalizeUploadRequest({ purpose: 'post', files: [file] }),
    /bad-post-id/,
  );
  assert.throws(
    () => normalizeUploadRequest({ postId: 'p1', files: [] }),
    /bad-file-count/,
  );
  assert.throws(
    () =>
      normalizeUploadRequest({
        postId: 'p1',
        files: Array.from({ length: 5 }, () => file),
      }),
    /bad-file-count/,
  );
  assert.throws(
    () =>
      normalizeUploadRequest({
        postId: 'p1',
        files: [{ contentType: 'image/gif', size: 10 }],
      }),
    /unsupported-type/,
  );
  assert.throws(
    () =>
      normalizeUploadRequest({
        postId: 'p1',
        files: [{ contentType: 'video/mp4', size: MAX_VIDEO_BYTES + 1 }],
      }),
    /file-too-large/,
  );
  assert.throws(
    () =>
      normalizeUploadRequest({
        purpose: 'avatar',
        files: [{ contentType: 'video/mp4', size: 1000 }],
      }),
    /unsupported-type/,
  );
});

test('the image and video ceilings match the Flutter service', () => {
  assert.equal(limitFor('image/jpeg'), 5 * 1024 * 1024);
  assert.equal(limitFor('video/mp4'), 50 * 1024 * 1024);
});

test('chat keys are namespaced by conversation and stay readable by their owner', () => {
  const key = buildObjectKey({
    uid,
    purpose: 'chat',
    chatId: 'abc_DEF-1',
    contentType: 'audio/mp4',
    id: '11111111-2222-3333-4444-555555555555',
  });
  assert.equal(
    key,
    'users/Ab3_x-9/chats/abc_DEF-1/11111111-2222-3333-4444-555555555555.m4a',
  );
  assert.equal(keyOwner(key), uid);
  assert.ok(isOwnKey(uid, key));
  assert.ok(!isOwnKey('someone-else', key));
  assert.ok(isReadableKey(key));
});

test('a chat upload without a valid conversation id is rejected', () => {
  const file = { contentType: 'image/jpeg', size: 1000 };
  assert.throws(
    () => normalizeUploadRequest({ purpose: 'chat', files: [file] }),
    /bad-chat-id/,
  );
  assert.throws(
    () =>
      normalizeUploadRequest({
        purpose: 'chat',
        chatId: '../escape',
        files: [file],
      }),
    /bad-chat-id/,
  );
});

test('chat audio and document ceilings match the Flutter service', () => {
  assert.equal(limitFor('audio/mp4'), 12 * 1024 * 1024);
  assert.equal(limitFor('application/pdf'), 20 * 1024 * 1024);
  const normalized = normalizeUploadRequest({
    purpose: 'chat',
    chatId: 'a_b',
    files: [
      { contentType: 'audio/mp4', size: 12 * 1024 * 1024 },
      { contentType: 'application/pdf', size: 20 * 1024 * 1024 },
    ],
  });
  assert.equal(normalized.purpose, 'chat');
  assert.equal(normalized.chatId, 'a_b');
  assert.equal(normalized.postId, null);
  assert.equal(normalized.files.length, 2);
});
