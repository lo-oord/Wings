import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../../core/errors/app_failure.dart';
import '../models/user_profile.dart';
import '../repositories/auth_repository.dart';
import '../repositories/avatar_repository.dart';
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
    this._sync,
    this._db,
  );

  final FirebaseAuthRepository _auth;
  final UsernameRepository _usernames;
  final UserRepository _users;
  final AvatarRepository _avatars;
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

  Future<AuthUser> signInWithGoogle() async {
    final user = await _auth.signInWithGoogle();
    final profile = await _ensureProfile(user);
    await _sync.attach(user.id);
    return _merge(user, profile);
  }

  /// Restores the session on start-up: the profile is refreshed and the account
  /// sync is attached without showing a loading screen.
  Future<AuthUser?> restore() async {
    final user = _auth.currentUser;
    if (user == null) return null;
    final profile = await _users.fetch(user.id);
    if (profile != null) {
      await _sync.attach(user.id);
      return _merge(user, profile);
    }
    return _ensureProfile(user).then((value) => _merge(user, value));
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
      await _usernames.reserve(uid: user.id, normalized: validation.normalized);
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
        final bytes = await _avatars.compressFile(avatarPath);
        if (bytes != null) {
          await _avatars.save(uid: user.id, bytes: bytes);
          profile = profile.copyWith(photoVersion: 1);
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
    if (existing != null) return existing;

    final seeds = <String>[
      UsernameRules.sanitize(user.email.split('@').first),
      UsernameRules.sanitize(user.displayName.replaceAll(' ', '_')),
      'wings',
    ];
    String? chosen;
    for (final seed in seeds) {
      if (seed.length >= UsernameRules.minLength &&
          seed.length <= UsernameRules.maxLength) {
        if (await _usernames.isAvailable(seed)) {
          chosen = seed;
          break;
        }
      }
      for (final candidate in UsernameRules.suggestions(seed, count: 4)) {
        if (await _usernames.isAvailable(candidate)) {
          chosen = candidate;
          break;
        }
      }
      if (chosen != null) break;
    }
    if (chosen == null) {
      throw const AppFailure(
        FailureKind.permission,
        technical: 'username-unavailable',
      );
    }
    await _usernames.reserve(uid: user.id, normalized: chosen);
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
    await _users.create(profile);
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
    await _usernames.changeUsername(
      uid: profile.uid,
      previousNormalized: profile.normalizedUsername,
      nextNormalized: validation.normalized,
    );
    final next = profile.copyWith(
      username: username.trim(),
      updatedAt: DateTime.now(),
    );
    await _users.syncPublicUsername(profile.uid, username.trim());
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

  Future<Uint8List?> avatarBytes(UserProfile profile) =>
      _avatars.fetch(uid: profile.uid, version: profile.photoVersion);

  /// Keeps the public statistics in step with the local library.
  Future<void> publishStats(UserProfile profile, ProfileStats stats) =>
      _users.updateStats(profile.uid, stats);

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
