// Rules for the media objects the Worker hands out, kept pure so they can be
// unit-tested without a network or the Workers runtime.
//
// A key is always built by the Worker, never by the client:
//   users/{uid}/posts/{postId}/{uuid}.{ext}          community pictures/videos
//   users/{uid}/profile/avatar/{uuid}.{ext}          profile picture
//   users/{uid}/profile/cover/{uuid}.{ext}           profile banner
//
// Ownership is structural: the uid is the second path segment, so a member can
// only ever write or delete under their own prefix whatever the request says.

export const MAX_IMAGE_BYTES = 5 * 1024 * 1024;
export const MAX_VIDEO_BYTES = 50 * 1024 * 1024;
export const MAX_FILES = 4;
export const MAX_DOWNLOAD_KEYS = 20;
export const MAX_DELETE_KEYS = 12;

export const ALLOWED_TYPES = new Map([
  ['image/jpeg', 'jpg'],
  ['image/png', 'png'],
  ['image/webp', 'webp'],
  ['video/mp4', 'mp4'],
  ['video/quicktime', 'mov'],
  ['video/webm', 'webm'],
]);

/** `post` keeps the original request shape; `avatar`/`cover` are images only. */
export const PURPOSES = new Set(['post', 'avatar', 'cover']);

const POST_KEY =
  /^users\/([A-Za-z0-9_-]{1,128})\/posts\/([A-Za-z0-9]{1,64})\/([A-Za-z0-9-]{8,64})\.(jpg|png|webp|mp4|mov|webm)$/;

const PROFILE_KEY =
  /^users\/([A-Za-z0-9_-]{1,128})\/profile\/(avatar|cover)\/([A-Za-z0-9-]{8,64})\.(jpg|png|webp)$/;

const POST_ID = /^[A-Za-z0-9]{1,64}$/;

/** A rejected media request; `status` is what the API answers with. */
export class MediaError extends Error {
  constructor(code, status = 400) {
    super(code);
    this.name = 'MediaError';
    this.code = code;
    this.status = status;
  }
}

export function limitFor(contentType) {
  return String(contentType).startsWith('video/')
    ? MAX_VIDEO_BYTES
    : MAX_IMAGE_BYTES;
}

/**
 * Validates the body of `POST /v1/uploads` and returns a normalized request.
 *
 * `purpose` is optional and defaults to `post`, so the original Flutter client
 * (which only ever sent `postId` and `files`) keeps working unchanged.
 */
export function normalizeUploadRequest(body) {
  const purpose = body?.purpose ?? 'post';
  if (typeof purpose !== 'string' || !PURPOSES.has(purpose)) {
    throw new MediaError('bad-purpose');
  }
  let postId = null;
  if (purpose === 'post') {
    postId = body.postId;
    if (typeof postId !== 'string' || !POST_ID.test(postId)) {
      throw new MediaError('bad-post-id');
    }
  }
  const files = body?.files;
  if (!Array.isArray(files) || files.length === 0 || files.length > MAX_FILES) {
    throw new MediaError('bad-file-count');
  }
  const normalized = files.map((file) => {
    if (!file || typeof file !== 'object') throw new MediaError('bad-file');
    const contentType = file.contentType;
    if (typeof contentType !== 'string' || !ALLOWED_TYPES.has(contentType)) {
      throw new MediaError('unsupported-type', 415);
    }
    if (purpose !== 'post' && contentType.startsWith('video/')) {
      throw new MediaError('unsupported-type', 415);
    }
    if (
      typeof file.size !== 'number' ||
      !Number.isFinite(file.size) ||
      file.size <= 0 ||
      file.size > limitFor(contentType)
    ) {
      throw new MediaError('file-too-large', 413);
    }
    return { contentType, size: file.size };
  });
  return { purpose, postId, files: normalized };
}

/** Builds the object key. `id` exists so tests can be deterministic. */
export function buildObjectKey({
  uid,
  purpose = 'post',
  postId,
  contentType,
  id = crypto.randomUUID(),
}) {
  if (typeof uid !== 'string' || !/^[A-Za-z0-9_-]{1,128}$/.test(uid)) {
    throw new MediaError('bad-subject');
  }
  if (!PURPOSES.has(purpose)) throw new MediaError('bad-purpose');
  const extension = ALLOWED_TYPES.get(contentType);
  if (!extension) throw new MediaError('unsupported-type', 415);
  if (purpose === 'post') {
    if (typeof postId !== 'string' || !POST_ID.test(postId)) {
      throw new MediaError('bad-post-id');
    }
    return `users/${uid}/posts/${postId}/${id}.${extension}`;
  }
  if (contentType.startsWith('video/')) {
    throw new MediaError('unsupported-type', 415);
  }
  return `users/${uid}/profile/${purpose}/${id}.${extension}`;
}

/** The uid an object key belongs to, or null when the key is not ours. */
export function keyOwner(key) {
  if (typeof key !== 'string' || key.length > 512) return null;
  const match = POST_KEY.exec(key) ?? PROFILE_KEY.exec(key);
  return match ? match[1] : null;
}

/** Any signed-in member may read community and profile media. */
export function isReadableKey(key) {
  return keyOwner(key) !== null;
}

/** Only the owner may delete, because the uid is part of the signed path. */
export function isOwnKey(uid, key) {
  return typeof uid === 'string' && uid.length > 0 && keyOwner(key) === uid;
}
