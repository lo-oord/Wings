# wings-media-api

Media API for Wings. It is the only place that holds the Tigris credentials;
the Flutter app never sees an access key.

| Endpoint | Method | Purpose |
| --- | --- | --- |
| `/` , `/health` | GET | Service identity, deployed version and a real Tigris probe (no secrets). |
| `/v1/uploads` | POST | Verifies the Firebase ID token and returns signed PUT URLs for up to 4 files. |
| `/v1/download` | POST | Verifies the Firebase ID token and returns signed GET URLs for up to 20 object keys. |
| `/v1/delete` | POST | Deletes objects under the caller's own `users/{uid}/` prefix. |

## Object namespaces

Keys are always built by the Worker, never by the client:

| Purpose | Key | Contents |
| --- | --- | --- |
| `post` (default) | `users/{uid}/posts/{postId}/{uuid}.{ext}` | Post pictures, video, video thumbnail |
| `avatar` | `users/{uid}/profile/avatar/{uuid}.{ext}` | Profile picture (images only) |
| `cover` | `users/{uid}/profile/cover/{uuid}.{ext}` | Profile banner (images only) |

`purpose` is optional. A request without it is a `post` request, which is the
exact shape the original Flutter client already sends, so nothing breaks.
`avatar`/`cover` also work for a profile picture uploaded through the Worker;
the app's existing avatar/cover storage in Firestore is untouched.

Accepted types: `image/jpeg`, `image/png`, `image/webp` (5 MiB each) and
`video/mp4`, `video/quicktime`, `video/webm` (50 MiB each, up to 60 seconds is
enforced by the app). The video thumbnail is uploaded as a normal picture under
the same post prefix.

## HTTP Range

The bucket is private, so the app exchanges a key for a short-lived signed GET
URL. Only the `host` header is signed, so the player's `Range` header is not part
of the signature and Tigris answers `206 Partial Content` itself. Video bytes
never pass through the Worker; `/v1/download` reports `acceptsRange: true`.
This is what media_kit/libmpv uses to seek without downloading the whole clip.

## Security model

1. `Authorization: Bearer <Firebase ID token>` is required on every `/v1` call.
2. The RS256 signature is verified against Google's JWKS
   (`securetoken@system.gserviceaccount.com`), then `iss`, `aud`, `exp`, `iat`
   and `sub` are checked. A token is never trusted because it decodes.
3. The uid comes from `sub`; a uid in the request body is ignored.
4. Ownership is structural: the uid is a signed path segment, so a member
   cannot read or delete a key outside the namespaces above, and `/v1/delete`
   refuses anything not under the caller's own prefix.
5. Uploads and downloads use short-lived SigV4 query signatures. The bucket
   stays private and no URL is stored in Firestore — only the key is.
6. Pictures are 5 MiB, video 50 MiB, 4 files per request, 20 download keys,
   12 delete keys.
7. `/health` signs a HEAD for a sentinel key that is never written and reports
   only `reachable`, the HTTP status, whether authorization was accepted and the
   latency. It never returns a credential or a signed URL.

## Local checks

```bash
cd worker/wings-media-api
npm test        # node --test: JWT, SigV4 reference vector, key rules
```

The SigV4 test reproduces the published AWS example signature
`aeeed9bb…d404` byte for byte, which proves the canonical request and signing
key derivation.

## Deploying

```bash
cd worker/wings-media-api
npx wrangler deploy
curl https://wings-media-api.<account>.workers.dev/health
```

Secrets already exist on the Worker (`TIGRIS_ACCESS_KEY_ID`,
`TIGRIS_SECRET_ACCESS_KEY`); they are never read, printed or committed here.
`/health` reports the deployed version id, so a rollout can be verified from
the outside. After deploying, Flutter's `WINGS_MEDIA_API` either uses the
built-in default or is overridden at build time:

```bash
flutter build apk --dart-define=WINGS_MEDIA_API=https://wings-media-api.<account>.workers.dev
```

Without the media API the app still works; picture and video posts show a
clear "upload unavailable" message instead of failing silently.

## Notes

- The bucket must stay private. Download URLs expire after ten minutes and are
  cached in memory by the app until shortly before expiry.
- A post whose Firestore write failed has its uploaded objects deleted by the
  app; a failed cleanup only costs storage, never access.
- There is no transcoding or automatic thumbnail generation: Tigris is object
  storage only. A video cover is an optional picture the author picks.
