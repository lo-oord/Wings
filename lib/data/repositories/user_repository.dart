import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/user_profile.dart';

/// Profiles live in two documents:
///
/// * `users/{uid}` — the owner-only document with every field.
/// * `profiles/{uid}` — the public mirror holding only the fields the owner
///   allowed, which is the only profile other users may read.
///
/// Firestore rules cannot hide individual fields, so privacy is enforced by
/// keeping private values out of the public document entirely.
class UserRepository {
  UserRepository(this._db);

  final FirebaseFirestore _db;

  static const String usersCollection = 'users';
  static const String profilesCollection = 'profiles';

  DocumentReference<Map<String, dynamic>> _user(String uid) =>
      _db.collection(usersCollection).doc(uid);

  DocumentReference<Map<String, dynamic>> _public(String uid) =>
      _db.collection(profilesCollection).doc(uid);

  Stream<UserProfile?> watch(String uid) => _user(uid).snapshots().map(
    (snapshot) => snapshot.exists && snapshot.data() != null
        ? UserProfile.fromMap(uid, snapshot.data()!)
        : null,
  );

  Future<UserProfile?> fetch(String uid) async {
    final snapshot = await _user(uid).get();
    final data = snapshot.data();
    if (!snapshot.exists || data == null) return null;
    return UserProfile.fromMap(uid, data);
  }

  Stream<UserProfile?> watchPublic(String uid) => _public(uid).snapshots().map(
    (snapshot) => snapshot.exists && snapshot.data() != null
        ? UserProfile.fromPublicMap(uid, snapshot.data()!)
        : null,
  );

  Future<UserProfile?> fetchPublic(String uid) async {
    final snapshot = await _public(uid).get();
    final data = snapshot.data();
    if (!snapshot.exists || data == null) return null;
    return UserProfile.fromPublicMap(uid, data);
  }

  /// Creates the owner document, its public mirror and the stats document.
  Future<void> create(UserProfile profile) async {
    final batch = _db.batch();
    final data = profile.toMap()..['createdAt'] = FieldValue.serverTimestamp();
    batch.set(_user(profile.uid), data);
    batch.set(_public(profile.uid), profile.toMapPublic());
    batch.set(
      _user(profile.uid).collection('meta').doc('stats'),
      profile.stats.toMap()..['updatedAt'] = FieldValue.serverTimestamp(),
    );
    await batch.commit();
  }

  /// Saves the owner document and refreshes the public mirror. Both writes are
  /// owned by the same user, so one batch keeps them consistent.
  ///
  /// The mirror is written without `merge`: a merge never removes a key, so a
  /// privacy switch that was turned off would otherwise leave the old value
  /// readable by other users.
  Future<void> save(UserProfile profile) async {
    final batch = _db.batch();
    batch.set(_user(profile.uid), profile.toMap(), SetOptions(merge: true));
    batch.set(_public(profile.uid), profile.toMapPublic());
    await batch.commit();
  }

  /// Re-creates a missing public mirror (for example when an older account or
  /// an interrupted sign-up left `profiles/{uid}` behind).
  ///
  /// Best effort: a sign-in must never fail because this repair was rejected.
  Future<void> ensurePublicMirror(UserProfile profile) async {
    try {
      final snapshot = await _public(profile.uid).get();
      if (snapshot.exists) return;
      await _public(profile.uid).set(profile.toMapPublic());
    } on Object {
      // Offline or denied; the next profile save recreates the mirror.
    }
  }

  Future<void> setPrivacy(UserProfile profile) => save(profile);

  Future<void> updateStats(String uid, ProfileStats stats) async {
    final profile = await fetch(uid);
    if (profile == null) return;
    await save(profile.copyWith(stats: stats, updatedAt: DateTime.now()));
  }

  Future<void> setPhotoVersion(String uid, int version) async {
    final now = FieldValue.serverTimestamp();
    final batch = _db.batch();
    batch.update(_user(uid), <String, dynamic>{
      'photoVersion': version,
      'updatedAt': now,
    });
    batch.set(_public(uid), <String, dynamic>{
      'photoVersion': version,
      'updatedAt': now,
    }, SetOptions(merge: true));
    await batch.commit();
  }

  Future<void> markPendingDeletion(String uid, {bool pending = true}) async {
    await _user(uid).set(<String, dynamic>{
      'pendingDeletion': pending,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  /// Reads the public mirror ids reserved for the same username, used to keep
  /// the mirror in sync after a rename.
  Future<void> syncPublicUsername(String uid, String username) async {
    await _public(uid).set(<String, dynamic>{
      'username': username,
      'normalizedUsername': username.trim().toLowerCase(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }
}
