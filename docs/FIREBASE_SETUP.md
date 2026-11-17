# Wings — account, sync and social setup

Everything here runs on the **Firebase free (Spark) plan**. No Cloud Functions,
no Firebase Storage, no Cloud Run, no billing upgrade.

## 1. What is stored where

| Path | Contents | Who can read | Who can write |
| --- | --- | --- | --- |
| `users/{uid}` | Full private profile: username, display name, country, age group, bio, privacy flags, statistics, badges, photo version | Owner only | Owner (badges: admins only) |
| `users/{uid}/private/avatar` | Profile picture bytes (JPEG ≤ 160 KB) + `byteSize` | Any signed-in user | Owner |
| `users/{uid}/library/{animeId}` | Favourite flag, status, watched episodes, timestamps | Owner | Owner |
| `users/{uid}/history/{animeId}__{episodeId}` | Playback position, duration, completion, timestamp | Owner | Owner |
| `users/{uid}/settings/account` | Account-level preferences (language, autoplay, remember position, speed, preferred quality) | Owner | Owner |
| `users/{uid}/meta/stats` | Same numbers as the profile statistics | Owner | Owner |
| `users/{uid}/activity/{id}` | Index of the user's own comments/reactions, used for deletion | Owner | Owner |
| `profiles/{uid}` | **Public mirror**: username, display name, badges, photo version, plus country / age group / stats **only when the owner allowed them** | Any signed-in user | Owner |
| `usernames/{normalized}` | `{uid, username, createdAt}` reservation | Exact lookup (`get`) only, even before sign-in so the sign-up form can check; listing is denied | Owner of the handle |
| `episodes/{episodeId}/reactions/{uid}` | One reaction document per user (`like` / `dislike`) | Signed-in users | The matching uid |
| `episodes/{episodeId}/comments/{commentId}` | Comment with a denormalized author snapshot | Signed-in users | Author, plus a +1 `replyCount` bump |
| `episodes/{episodeId}/comments/{commentId}/replies/{replyId}` | Reply | Signed-in users | Author |
| `reports/{reportId}` | Moderation reports (reporter uid is never exposed to users) | Admins | Signed-in users (create only) |
| `config/admins` | `{uids: [...]}` administrator allowlist | Admins | Nobody (console / Admin SDK only) |

**Never stored**: passwords, email addresses in public documents, Firebase UID
in public documents, exact birth dates, download files or their paths, device
notification settings, theme choice.

## 2. Privacy model

Firestore rules cannot hide individual fields, so private values are physically
absent from `profiles/{uid}`. The client writes `users/{uid}` and
`profiles/{uid}` together in one batch, and the public document only contains
the fields whose privacy flag is on. Turning a flag off removes the value from
the mirror on the next save — a reader can never receive data and have the UI
hide it.

Defaults are private: country, age group, favourites and statistics are all
off until the owner enables them. Only age **groups** (`13-17`, `18-24`, …) are
stored, never a birth date.

## 3. Username integrity

`usernames/{normalized}` is the uniqueness key (`Lord_Shadow` → `lord_shadow`).

* Reservation, rename and release run inside `runTransaction`, so two clients
  claiming one handle cannot both succeed.
* Rename order: reserve the new handle → update `users/{uid}` → delete the old
  reservation. Rules only accept a new username when a reservation owned by the
  caller already exists.
* Availability checks are exact document `get`s; `list` is denied, so the
  registry cannot be enumerated. `get` is allowed even for signed-out devices,
  because the sign-up form asks for the handle before the account exists.
* If the field shows “Could not check the username now”, the console log prints
  the real Firestore error. `permission-denied` means these rules are not
  published yet; `unavailable` / `not-found` means the Firestore database has
  not been created in the project (Console → Firestore Database → Create
  database).
* Live checks are debounced (450 ms), identical values are cached, empty or
  invalid values never reach Firestore, and outdated responses are ignored.

## 4. Badges (verified / developer)

Badges live in `users/{uid}.badges` and the public mirror, and **no client may
change them**: the update rule requires
`request.resource.data.badges == resource.data.badges` unless the caller is in
`config/admins`.

Free-plan administrative procedure:

1. In the Firebase console create `config/admins` with
   `{ "uids": ["<admin uid>"] }`. Only the console (or Admin SDK) can write it,
   because rules deny all writes to `config`.
2. To verify a user, the admin signs in with an allowlisted account and updates
   `users/{uid}.badges` (and the mirror) from an administrative tool, or edits
   the document directly in the console.
3. Remove the uid from `config/admins` when the admin role ends.

There is no self-service verification, and hidden UI is never used as a security
control.

## 5. Synchronization

Synchronized across devices: library entries (favourites and every status),
watch history and playback progress, and account-level preferences.

Device-only: downloaded episodes and their files (never uploaded), theme,
notification setup, onboarding state, search history, playback hardware.

* Conflict rule: last-writer-wins on each record's `updatedAt`.
* Pulls are incremental (`where updatedAt > lastPull`), so a small change never
  re-downloads the library.
* First sign-in migrates existing local guest data into the account.
* Signing into a different account clears the previous account's local library,
  history and search history before pulling, so data never leaks between
  accounts.
* Sign-out clears account data from the device.

## 6. Account deletion

`AccountDeletionService` runs a resumable client-side cascade:

1. `pendingDeletion: true` on the profile.
2. Re-authentication (password for email accounts, Google for Google accounts) —
   Firebase requires a recent login.
3. Delete every comment/reaction referenced by `users/{uid}/activity`.
4. Delete `library`, `history`, `settings`, `meta`, `activity` and the avatar in
   batches of 100.
5. Release the username reservation (the handle becomes claimable again).
6. Delete `profiles/{uid}` and `users/{uid}`.
7. Delete the Firebase Authentication user and clear local account data.

Comments are **hard deleted** (not anonymized), so no private content remains in
public threads. Replies keep their place; the parent counter is not decremented.

Limitation: Spark has no trusted backend, so the cascade runs on the client and
is authorized by rules that only allow the owner to delete their own records. If
step 3–6 is interrupted, the profile stays flagged `pendingDeletion` and the
operation can be retried; partially deleted private data is never restored.

## 7. Google Sign-In

1. `android/app/google-services.json` is committed (client configuration, not a
   secret).
2. Firebase console → Authentication → Sign-in method → enable **Google** and
   **Email/Password**.
3. Project settings → Your apps → Android `com.wings.wings` → add the SHA-1 and
   SHA-256 of the **upload keystore** (`android/key.properties`), and keep the
   debug SHA-1 as well if you test debug builds.
4. The same fingerprints must exist on the Google Cloud OAuth client if you add
   server-side token verification.
5. Google accounts created through the app receive an automatically reserved
   username; users can change it from the profile screen.

## 8. Publishing the rules and indexes

**Console (simplest):**

1. Firestore Database → Rules → paste `firestore.rules` → Publish.
2. Realtime Database → Rules → paste `database.rules.json` → Publish (the app
   stores nothing in RTDB, so both read and write are denied).
3. Firestore Database → Indexes: no composite indexes are required. Every query
   uses a single field (`createdAt` ordering, `updatedAt` inequality, `type` /
   `deleted` equality) which Firestore indexes automatically.

**CLI:**

```bash
firebase deploy --only firestore:rules,firestore:indexes,database
```

## 9. Free-plan compatibility

| Service | Used | Billing |
| --- | --- | --- |
| Authentication (email/password, Google) | Yes | Free |
| Cloud Firestore | Yes | Free (Spark quotas) |
| Realtime Database | No (rules deny everything) | Free |
| Firebase Storage | **No** (avatars live in Firestore) | — |
| Cloud Functions | **No** | — |

Cost notes: reaction and comment counts use aggregation queries
(`count()`), which bill one document read per 1000 matches. Comment pages load
20 documents at a time with a cursor; only the visible episode's newest page is
listened to. Profile reads are cached locally, and avatars are cached per
`photoVersion`.

Limitations that cannot be fixed without a paid backend:

* Statistics and reaction counts are client-written or aggregation-derived;
  they are display values, not tamper-proof counters.
* There is no server-side rate limiting. Deterministic document ids,
  idempotent writes, strict rules and App Check are the available mitigations.
* Account deletion is a client-side cascade (see §6).
* Push notifications for social events would need a trusted sender; only
  in-app notifications exist today.

## 10. Manual console actions checklist

- [ ] Enable Google and Email/Password providers.
- [ ] Add the upload-keystore SHA-1/SHA-256 to the Android app.
- [ ] Publish `firestore.rules`, `database.rules.json`.
- [ ] Create `config/admins` with the administrator uids.
- [ ] Create the `episodes` documents (they are read-only for clients).
- [ ] Optional: enable App Check with Play Integrity before enabling
      enforcement (debug builds then need a debug token).
