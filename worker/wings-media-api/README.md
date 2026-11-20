# wings-media-api

Media API for the Wings community. It is the only place that holds the Tigris
credentials; the Flutter app never sees an access key.

| Endpoint | Method | Purpose |
| --- | --- | --- |
| `/` , `/health` | GET | Service identity (no secrets). |
| `/v1/uploads` | POST | Verifies the Firebase ID token and returns signed PUT URLs for up to 4 pictures. |
| `/v1/download` | POST | Verifies the Firebase ID token and returns signed GET URLs for up to 20 object keys. |
| `/v1/delete` | POST | Deletes objects under the caller's own `users/{uid}/` prefix. |

## Security model

1. `Authorization: Bearer <Firebase ID token>` is required on every `/v1` call.
2. The RS256 signature is verified against Google's JWKS
   (`securetoken@system.gserviceaccount.com`), then `iss`, `aud`, `exp`, `iat`
   and `sub` are checked. A token is never trusted because it decodes.
3. The uid comes from `sub`; a uid in the request body is ignored.
4. Object keys are built by the Worker (`users/{uid}/posts/{postId}/{uuid}.{ext}`),
   so a member cannot choose a path outside their own prefix.
5. Uploads and downloads use short-lived SigV4 query signatures. The bucket
   stays private.
6. Only `image/jpeg`, `image/png` and `image/webp` are accepted, up to 5 MiB
   each and 4 files per request. Payloads never pass through the Worker.

## Local checks

```bash
cd worker/wings-media-api
npm test        # node --test: JWT verification + SigV4 reference vector
```

The SigV4 test reproduces the published AWS example signature
`aeeed9bb…d404` byte for byte, which proves the canonical request and signing
key derivation.

## Deploying (needs the owner's approval)

```bash
cd worker/wings-media-api
npx wrangler deploy
```

Secrets already exist on the Worker (`TIGRIS_ACCESS_KEY_ID`,
`TIGRIS_SECRET_ACCESS_KEY`). They are never read, printed or committed here.
After deploying, build the app with the Worker URL:

```bash
flutter build apk --dart-define=WINGS_MEDIA_API=https://wings-media-api.<account>.workers.dev
```

Without that define the app still works; picture posts show a clear
"upload unavailable" message instead of failing silently.

## Notes

- The bucket must stay private. Download URLs are signed, expire after ten
  minutes, and are cached in memory by the app until shortly before expiry.
- A post whose Firestore write failed has its uploaded objects deleted by the
  app; a failed cleanup only costs storage, never access.
