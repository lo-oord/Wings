# Wings — account, sync and social setup

Everything here runs on the **Firebase free (Spark) plan**. No Cloud Functions,
no Firebase Storage, no Cloud Run, no billing upgrade.

## 0. If sign-up or Google sign-in is failing

The most common cause is that the rules in this repository are not published
yet. The old rule for `users/{uid}/meta/{docId}` only allowed the four counters,
while the client also writes `updatedAt`, so **every** profile creation was
rejected: email registration failed outright and Google sign-in left an
account in Firebase Authentication with no profile. Publish `firestore.rules`
(section 8) before testing again.

Other setup that must exist before Google sign-in can work:

* Authentication → Sign-in method → **Google** enabled.
* The **SHA-1 and SHA-256** of the signing key added to the Android app
  `com.wings.wings` in Firebase (section 7).
* The web OAuth client id (`client_type: 3` inside
  `android/app/google-services.json`) is passed to `google_sign_in` as
  `serverClientId`. Without it the plugin returns no `idToken` and Firebase
  rejects the credential. It is read from
  `lib/data/auth/firebase_auth_repository.dart` (override with
  `--dart-define=GOOGLE_SERVER_CLIENT_ID=...`).

## 1. What is stored where

| Path | Contents | Who can read | Who can write |
| --- | --- | --- | --- |
| `users/{uid}` | Full private profile: username, display name, country, age group, bio, privacy flags, statistics, badges, photo version | Owner only | Owner (badges: admins only) |
| `users/{uid}/private/avatar` | Profile picture bytes (JPEG ≤ 160 KB) + `byteSize` | Any signed-in user | Owner |
| `users/{uid}/private/cover` | Cover banner bytes (JPEG ≤ 480 KB) + `byteSize` | Any signed-in user | Owner |
| `users/{uid}/library/{animeId}` | Favourite flag, status, watched episodes, timestamps | Owner | Owner |
| `users/{uid}/history/{animeId}__{episodeId}` | Playback position, duration, completion, timestamp | Owner | Owner |
| `users/{uid}/settings/account` | Account-level preferences (language, autoplay, remember position, speed, preferred quality) | Owner | Owner |
| `users/{uid}/meta/stats` | Same numbers as the profile statistics | Owner | Owner |
| `users/{uid}/activity/{id}` | Index of the user's own comments/reactions, used for deletion | Owner | Owner |
| `profiles/{uid}` | **Public mirror**: username, display name, badges, photo version, plus country / age group / stats **only when the owner allowed them** | Any signed-in user | Owner |
| `usernames/{normalized}` | `{uid, username, createdAt}` reservation | Exact lookup (`get`) only, even before sign-in so the sign-up form can check; listing is denied | Owner of the handle |
| `episodes/{episodeId}/reactions/{uid}` | One reaction document per user (`like` / `dislike`) | Signed-in users | The matching uid |
| `episodes/{episodeId}/comments/{commentId}` | Comment with a denormalized author snapshot | Signed-in users | Author (text/snapshot), `replyCount` ±1 |
| `episodes/{episodeId}/comments/{commentId}/replies/{replyId}` | Reply | Signed-in users | Author, or the thread's author for deletes |
| `episodes/{episodeId}/stats/watch/viewers/{uid}` | One document per account that really watched the episode | Signed-in users | The account itself, on create only |
| `anime/{animeId}/stats/watch/viewers/{uid}` | One document per account that watched the title | Signed-in users | The account itself, on create only |
| `episodes|anime/.../stats/views` | **Legacy** counter from older builds, frozen and no longer read | Nobody | Nobody |
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

Defaults are private: bio, country, age group, favourites and statistics are
all off until the owner enables them. Only age **groups** (`13-17`, `18-24`, …)
are stored, never a birth date.

The owner controls the mirror from **الملف الشخصي → الخصوصية**:

| Switch | What it publishes |
| --- | --- |
| إظهار حسابي للآخرين (`showProfile`) | Master switch. When off the mirror keeps only the handle, display name and badges (`private: true`); the public profile screen shows a “does not share their profile” note. |
| إظهار النبذة (`bio`) | The bio text (≤ 300 characters). |
| إظهار الدولة (`country`) | The two-letter country code. |
| إظهار الفئة العمرية (`age`) | The age **group** only. |
| إظهار الإحصائيات (`stats`) | Anime watched, episodes watched, favourites and completed counts. |
| إظهار المفضلة (`favorites`) | Up to 12 favourite titles (id, title, artwork only — never progress or history). |

Saving the sheet republishes the statistics and favourites immediately, so
turning a switch off removes the value from the mirror at once. Because a
Firestore `set(merge: true)` never deletes a key, the mirror is written with a
plain `set`: a disabled field really disappears instead of being hidden in the
UI.

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

1. Re-authentication (password for email accounts, Google for Google accounts) —
   Firebase requires a recent login. This happens **before any write**, so a
   wrong password or a cancelled Google prompt leaves the account untouched.
2. `pendingDeletion: true` on the profile (best effort; the flag never blocks
   the deletion).
3. Delete every comment/reaction referenced by `users/{uid}/activity`.
4. Delete `library`, `history`, `settings`, `meta`, `activity` and the
   avatar/cover in batches of 100.
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
6. `google_sign_in` 7.x needs the **web** OAuth client id as
   `serverClientId`; the app uses the value from the project's
   `google-services.json`. If the Firebase project changes, either replace that
   file and the constant in `firebase_auth_repository.dart`, or build with
   `--dart-define=GOOGLE_SERVER_CLIENT_ID=<web client id>`.
7. Google sign-in is atomic: if the profile cannot be created after the
   Firebase account is, the app signs out again instead of leaving an account
   with no username, and the next attempt reuses the same Firebase user.

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
listened to, and the player preview streams just three comments. Profile reads
are cached locally; avatars and covers are cached per `photoVersion` /
`coverVersion`.

Write protection added for views and comments:

* A view is stored as `stats/watch/viewers/{uid}` — one document per account,
  creatable only by that account and never updateable or deletable. The number
  on screen is a `count()` over those documents, so no client can write an
  arbitrary value or count the same person twice.
* A view is only recorded after 15 seconds of playback, and only for a signed-in
  account; opening and closing an episode no longer inflates it.
* The old `stats/views` counters are frozen in the rules and ignored by the app,
  because they were the source of the inflated numbers. They can be deleted by
  hand from the console.
* Comments and replies have a 4-second local cooldown, and the rules validate the
  author snapshot, the timestamps and the reply parent.
* `/watch/...` keeps a single listener while the episode is open; pagination is
  cursor-based at 20 documents per page.

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

## 11. What changed in this revision (previous pass)

Rules:

* `users/{uid}/meta/{docId}` accepts the `updatedAt` the client writes — the
  previous `hasOnly` check rejected every profile creation, which broke email
  registration, avatar upload and username changes (all of them write the
  profile).
* `library`, `history`, `settings` and `meta` now allow the owner to **delete**
  documents; the old single read/write rule rejected deletes because a delete
  has no `request.resource.data`.
* `profiles/{uid}` create and update are separate rules, so a new mirror never
  compares against a document that does not exist yet. The owner still cannot
  change their own badges.
* `config/*` is unreadable by clients (`get()` inside rules still works), so the
  administrator allowlist is not exposed.
* `private/avatar` keeps its own ≤ 200 KB write rule and is excluded from the
  owner catch-all.
* New privacy fields (`showProfile`, `bio`) are validated in the rules.

Client:

* Username rename order is now claim → write profile → release the old handle.
  The old single transaction created the reservation and the profile in the
  same commit, and the rules could not see the reservation yet, so every rename
  was rejected.
* Google sign-in passes `serverClientId` and signs out again when profile
  creation fails, instead of leaving a half-created account.
* Signing in repairs a profile/mirror left behind by an interrupted sign-up.
* Firestore `permission-denied` and `unavailable` errors now have their own
  Arabic messages instead of the generic “something went wrong”.
* The episode screen is laid out like YouTube: reactions, share, download and
  save sit in a horizontal bar directly under the video, with the comment
  composer and comments in the same page instead of behind a button.

## 12. What changed in this revision (comments, views, cover, floating player)

**Publish the new `firestore.rules` before testing this build.** The new
features add these paths and will otherwise fail with `permission-denied`:

* `users/{uid}/private/cover` (read: signed-in, write: owner, ≤ 500 KB)
* `episodes/{episodeId}/stats/views` (create at 1 or +1 only)
* `anime/{animeId}/stats/views` (create at 1 or +1 only)
* `coverVersion` on `users/{uid}` and `profiles/{uid}`
* Comment and reply creation now also validates the author snapshot and both
  timestamps

Feature map:

| Screen | What changed |
| --- | --- |
| Player | Action bar redesigned: one segmented like/dislike pill plus spaced pills for share, download, save and comments, with a divider before the comments block. Episode views sit under the episode number. The episode list has dividers between entries. |
| Comments | The player shows the **three newest** comments and one “all comments” action. The full page (`/episode/{id}/comments`) streams the newest page, loads older pages as you scroll and keeps a composer pinned at the bottom. |
| Views | `ViewsRepository` records one viewer document per account and per episode/title after 15 seconds of playback; the count is a `count()` over those documents. Numbers are cached for 5 minutes. Episode count shows under the episode, title total on the details screen — only real app views, never the catalogue's estimated figure. |
| Settings | The account banner is now a proper card: real avatar, name, handle, email, one chevron, matching the settings groups. |
| Profile | Cover banner (`users/{uid}/private/cover`) with change/remove actions, separate from the avatar. Public profiles show the same banner. |
| Deletion | Re-authentication runs first, a password is mandatory for email accounts, Google accounts get an explicit confirmation step, and the cover document is removed too. A rules block now reports “publish the latest rules” instead of a generic error. |
| Floating player | Leaving a playing episode hands the live session to a draggable mini player (expand / pause / close), hosted above every route. Leaving the app on Android 8+ requests system picture-in-picture with a 16:9 window; `android:supportsPictureInPicture` is declared in the manifest. |
| Sources | Server lists are de-duplicated by quality + flavour + URL, and the duplicate comments command was removed from the portrait player overlay. |

Manual steps for this revision:

- [ ] Publish `firestore.rules` (required for cover, views and deletion).
- [ ] Rebuild the APK; the manifest now declares picture-in-picture support.
- [ ] Optional: seed `anime/{id}/stats/views` is **not** needed — the counter is
      created on the first real view.

## 13. What changed in this revision (polish, real views, hard deletes)

**Publish the updated `firestore.rules` again.** This revision changes these
paths and behaviours:

* `episodes/{episodeId}/stats/watch/viewers/{uid}` and
  `anime/{animeId}/stats/watch/viewers/{uid}` (create: own uid only; no update,
  no delete; readable/listed so `count()` works).
* `stats/views` on both episodes and anime is now **frozen** (`allow read, write:
  if false`). It is no longer used by the app.
* Comment updates also accept an author-snapshot refresh
  (`authorUsername`, `authorName`, `authorBadges`, `photoVersion`, `updatedAt`),
  which is how a rename or a new badge reaches comments that were already
  written.
* `replyCount` may now be decremented by exactly one (never below zero) when a
  reply is deleted, and the author of a thread may delete the replies inside it.
* The owner of `users/{uid}` may copy the badges an administrator already
  published on `profiles/{uid}`. They still cannot grant themselves a badge:
  the rule compares the value with the public mirror.

Feature map:

| Area | What changed |
| --- | --- |
| Splash | A branded splash (mark, wordmark, progress line) is drawn on the first frame while the store, Firebase, downloads and notifications load; the Android launch window uses the same dark background and app mark. |
| Transitions | Every pushed route uses one shared fade + short slide transition, and reduced-motion users get none. The register wizard fades between steps. |
| Auth states | The Google button shows its own spinner and label, a dimmed overlay blocks a second tap while signing in or creating the account, the login error is a proper inline card, and the verification screen polls quietly so it moves on by itself once the link is used. |
| Comments | Deleting a comment now removes the document **and every reply under it**, with no “this comment was deleted” placeholder. Legacy placeholders are filtered out of every list. |
| Views | Real unique-viewer counters; the fake catalogue figure was removed from the details screen. |
| Identity | A rename, a new verification badge or a new profile picture is copied into the account's existing comments and replies, and the public profile already streams live. Badges are read from the public mirror so an admin grant appears immediately, including on the user's own handle. |
| Navigation | Signing out or finishing onboarding re-evaluates the route; signed-out users cannot land on an account screen and the back button falls back to the home tab instead of doing nothing. |
| Settings | Sign-out asks for confirmation, “Share the app” was added, and the notification-permission chevron follows the text direction. |

Manual steps:

- [ ] Publish `firestore.rules` (required for the new view documents, comment
      deletion and the badge mirror).
- [ ] Optional: delete the old `stats/views` documents from the console; the app
      no longer reads them.
