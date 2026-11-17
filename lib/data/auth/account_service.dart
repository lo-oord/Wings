import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../../core/errors/app_failure.dart';
import '../models/user_profile.dart';
import '../repositories/auth_repository.dart';
import '../repositories/avatar_repository.dart';
import '../repositories/cover_repository.dart';
import '../repositories/user_repository.dart';
import '../repositories/username_repository.dart';
import '../sync/cloud_sync_service.dart';
import '../username/username_rules.dart';
import 'firebase_auth_repository.dart';

/// Coordinates identity, username reservation, profile documents, the profile
/// picture and the first cloud sync.
///
/// The Firebase account is created first (it provides the uid), then the
/// username is reserved atomically. If any later step fails the whole
/// registration is rolled back so a user never ends up as an account without a
/// username, or with a handle they cannot prove.
class AccountService {
  AccountService(
    this._auth,
    this._usernames,
    this._users,
    this._avatars,
    this._covers,
    this._sync,
    this._db,
  );

  final FirebaseAuthRepository _auth;
  final UsernameRepository _usernames;
  final UserRepository _users;
  final AvatarRepository _avatars;
  final CoverRepository _covers;
  final CloudSyncService _sync;
  final FirebaseFirestore _db;

  // --------------------------------------------------------------- signing in

  Future<AuthUser> signIn({
    required String email,
    required String password,
  }) async {
    final user = await _auth.signIn(email: email, password: password);
    final profile = await _ensureProfile(user);
    await _sync.attach(user.id);
    return _merge(user, profile);
  }

  /// Google sign-in creates the Firebase user before the profile exists, so a
  /// failure here would leave an account with no username: the app would look
  /// broken while the user is already visible in the Firebase console. The
  /// session is therefore closed again on failure, and the next attempt reuses
  /// the same Firebase account.
  Future<AuthUser> signInWithGoogle() async {
    final user = await _auth.signInWithGoogle();
    try {
      final profile = await _ensureProfile(user);
      await _sync.attach(user.id);
      return _merge(user, profile);
    } on Object {
      try {
        await _auth.signOut();
      } on Object {
        // The identity is recoverable on the next attempt either way.
      }
      rethrow;
    }
  }

  /// Restores the session on start-up: the profile is refreshed and the account
  /// sync is attached without showing a loading screen.
  Future<AuthUser?> restore() async {
    final user = _auth.currentUser;
    if (user == null) return null;
    final profile = await _users.fetch(user.id);
    if (profile != null) {
      await _users.ensurePublicMirror(profile);
      await _sync.attach(user.id);
      return _merge(user, profile);
    }
    return _ensureProfile(user).then((value) => _merge(user, value));
  }

  /// Creates the missing profile for an already signed-in account. Used when
  /// the app opens on an account left behind by an interrupted sign-up.
  Future<UserProfile> ensureProfile(AuthUser user) async {
    final profile = await _ensureProfile(user);
    await _sync.attach(user.id);
    return profile;
  }

  // -------------------------------------------------------------- register

  Future<AuthUser> register({
    required String displayName,
    required String username,
    required String country,
    required String ageGroup,
    required String email,
    required String password,
    String? avatarPath,
  }) async {
    final validation = UsernameRules.validate(username);
    if (!validation.ok) {
      throw const AppFailure(
        FailureKind.permission,
        technical: 'username-invalid',
      );
    }
    final user = await _auth.createAccount(
      email: email,
      password: password,
      displayName: displayName,
    );
    var reserved = false;
    try {
      try {
        await _usernames.reserve(
          uid: user.id,
          normalized: validation.normalized,
        );
      } on UsernameTakenException {
        throw const AppFailure(
          FailureKind.permission,
          technical: 'username-taken',
        );
      }
      reserved = true;
      final now = DateTime.now();
      var profile = UserProfile(
        uid: user.id,
        username: username.trim(),
        displayName: displayName.trim(),
        country: country,
        ageGroup: ageGroup,
        createdAt: now,
        updatedAt: now,
      );
      if (avatarPath != null) {
        // A picture that cannot be compressed or stored must not cancel a
        // valid registration; the user can pick one later from the profile.
        try {
          final bytes = await _avatars.compressFile(avatarPath);
          if (bytes != null) {
            await _avatars.save(uid: user.id, bytes: bytes);
            profile = profile.copyWith(photoVersion: 1);
          }
        } on Object {
          // Keep the account without a picture.
        }
      }
      await _users.create(profile);
      await _auth.sendEmailVerification();
      await _sync.attach(user.id);
      return _merge(user, profile);
    } on Object {
      if (reserved) {
        try {
          await _usernames.release(
            uid: user.id,
            normalized: validation.normalized,
          );
        } on Object {
          // Best effort; the reservation is orphaned but never reassigned.
        }
      }
      try {
        await _db.collection('users').doc(user.id).delete();
        await _db.collection('profiles').doc(user.id).delete();
      } on Object {
        // Rules may already block these writes after a partial failure.
      }
      try {
        await _auth.deleteCurrentUser();
      } on Object {
        await _auth.signOut();
      }
      rethrow;
    }
  }

  /// Creates a profile for accounts that arrive without one (Google, or an
  /// older email account) and reserves an available handle for them.
  Future<UserProfile> _ensureProfile(AuthUser user) async {
    final existing = await _users.fetch(user.id);
    if (existing != null) {
      // Repair an interrupted sign-up that created the owner document but not
      // the public mirror, and make sure no other user can claim the handle.
      await _users.ensurePublicMirror(existing);
      return existing;
    }

    final seeds = <String>[
      UsernameRules.sanitize(user.email.split('@').first),
      UsernameRules.sanitize(user.displayName.replaceAll(' ', '_')),
      'wings',
    ];
    String? chosen;
    for (final seed in seeds) {
      if (chosen != null) break;
      final candidates = <String>[
        if (seed.length >= UsernameRules.minLength &&
            seed.length <= UsernameRules.maxLength)
          seed,
        ...UsernameRules.suggestions(seed, count: 4),
      ];
      for (final candidate in candidates) {
        if (!await _usernames.isAvailable(candidate)) continue;
        try {
          await _usernames.claim(uid: user.id, normalized: candidate);
          chosen = candidate;
          break;
        } on UsernameTakenException {
          // Another device claimed it between the check and the transaction.
          continue;
        }
      }
    }
    if (chosen == null) {
      throw const AppFailure(
        FailureKind.permission,
        technical: 'username-unavailable',
      );
    }
    final now = DateTime.now();
    final profile = UserProfile(
      uid: user.id,
      username: chosen,
      displayName: user.displayName.trim().isEmpty
          ? chosen
          : user.displayName.trim(),
      createdAt: now,
      updatedAt: now,
    );
    try {
      await _users.create(profile);
    } on Object {
      try {
        await _usernames.release(uid: user.id, normalized: chosen);
      } on Object {
        // The handle stays reserved to this uid, so it is never taken by
        // someone else while the account is unusable.
      }
      rethrow;
    }
    return profile;
  }

  // -------------------------------------------------------------- profile

  Future<UserProfile> updateProfile({
    required UserProfile profile,
    String? displayName,
    String? bio,
    String? country,
    String? ageGroup,
  }) async {
    final next = profile.copyWith(
      displayName: displayName?.trim(),
      bio: bio?.trim(),
      country: country,
      ageGroup: ageGroup,
      updatedAt: DateTime.now(),
    );
    await _users.save(next);
    if ((displayName ?? '').trim().isNotEmpty) {
      await _auth.setDisplayName(displayName!.trim());
    }
    return next;
  }

  Future<UserProfile> updatePrivacy({
    required UserProfile profile,
    required ProfilePrivacy privacy,
  }) async {
    final next = profile.copyWith(privacy: privacy, updatedAt: DateTime.now());
    await _users.save(next);
    return next;
  }

  /// Rename order matters for the security rules:
  /// 1. claim the new handle in a transaction,
  /// 2. write the profile (the rule accepts it because the reservation exists),
  /// 3. release the previous handle, and only then let it be reused.
  Future<UserProfile> changeUsername({
    required UserProfile profile,
    required String username,
  }) async {
    final validation = UsernameRules.validate(username);
    if (!validation.ok) {
      throw const AppFailure(
        FailureKind.permission,
        technical: 'username-invalid',
      );
    }
    // Regular accounts rename once every 48 hours; a verified or developer
    // account may rename as often as it likes. The rule mirrors this check, so
    // a tampered client cannot skip the wait.
    final now = DateTime.now();
    if (!profile.canChangeUsernameAt(now)) {
      throw const AppFailure(
        FailureKind.permission,
        technical: 'username-cooldown',
      );
    }
    final next = profile.copyWith(
      username: username.trim(),
      usernameChangedAt: now,
      updatedAt: now,
    );
    final previous = profile.normalizedUsername;
    await _usernames.claim(uid: profile.uid, normalized: validation.normalized);
    try {
      await _users.save(next);
    } on Object {
      // The rename never happened, so the freshly claimed handle is released
      // again instead of being held forever.
      if (previous != validation.normalized) {
        try {
          await _usernames.release(
            uid: profile.uid,
            normalized: validation.normalized,
          );
        } on Object {
          // Best effort: an orphaned reservation is never reassigned.
        }
      }
      rethrow;
    }
    if (previous.isNotEmpty && previous != validation.normalized) {
      try {
        await _usernames.release(uid: profile.uid, normalized: previous);
      } on Object {
        // The old handle stays reserved; it is harmless and can be released by
        // the next rename.
      }
    }
    return next;
  }

  /// Compresses and stores the picture, then bumps `photoVersion` so every
  /// device invalidates its cached image.
  Future<UserProfile> saveAvatar({
    required UserProfile profile,
    required String path,
  }) async {
    final bytes = await _avatars.compressFile(path);
    if (bytes == null) {
      throw const AppFailure(
        FailureKind.storage,
        technical: 'avatar-too-large',
      );
    }
    await _avatars.save(uid: profile.uid, bytes: bytes);
    final version = profile.photoVersion + 1;
    await _users.setPhotoVersion(profile.uid, version);
    return profile.copyWith(photoVersion: version, updatedAt: DateTime.now());
  }

  Future<UserProfile> removeAvatar(UserProfile profile) async {
    await _avatars.remove(profile.uid);
    final version = profile.photoVersion + 1;
    await _users.setPhotoVersion(profile.uid, version);
    return profile.copyWith(photoVersion: version, updatedAt: DateTime.now());
  }

  /// Stores the wide banner shown behind the profile header. The cover is
  /// separate from the avatar and, like it, lives in Firestore bytes rather
  /// than Firebase Storage.
  Future<UserProfile> saveCover({
    required UserProfile profile,
    required String path,
  }) async {
    final bytes = await _covers.compressFile(path);
    if (bytes == null) {
      throw const AppFailure(FailureKind.storage, technical: 'cover-too-large');
    }
    await _covers.save(uid: profile.uid, bytes: bytes);
    final version = profile.coverVersion + 1;
    await _users.setCoverVersion(profile.uid, version);
    return profile.copyWith(coverVersion: version, updatedAt: DateTime.now());
  }

  Future<UserProfile> removeCover(UserProfile profile) async {
    await _covers.remove(profile.uid);
    final version = profile.coverVersion + 1;
    await _users.setCoverVersion(profile.uid, version);
    return profile.copyWith(coverVersion: version, updatedAt: DateTime.now());
  }

  Future<Uint8List?> avatarBytes(UserProfile profile) =>
      _avatars.fetch(uid: profile.uid, version: profile.photoVersion);

  Future<Uint8List?> coverBytes(UserProfile profile) =>
      _covers.fetch(uid: profile.uid, version: profile.coverVersion);

  /// Keeps the public statistics and shared favourites in step with the local
  /// library. Only display values are published; progress and history stay in
  /// the owner-only documents.
  Future<UserProfile> publishStats(
    UserProfile profile,
    ProfileStats stats, {
    List<ProfileFavorite>? favorites,
  }) async {
    final next = profile.copyWith(
      stats: stats,
      favorites: favorites ?? profile.favorites,
      updatedAt: DateTime.now(),
    );
    await _users.save(next);
    return next;
  }

  Future<void> signOut() async {
    await _sync.detach();
    await _auth.signOut();
  }

  AuthUser _merge(AuthUser user, UserProfile profile) => user.copyWith(
    displayName: profile.displayName,
    username: profile.username,
    country: profile.country,
    bio: profile.bio,
    emailVerified: _auth.emailVerified,
  );
}
