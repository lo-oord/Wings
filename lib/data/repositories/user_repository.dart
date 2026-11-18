import 'dart:async';

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

  /// Administrator-managed official marks. A document here always wins over
  /// the badge copies in the profile documents, which is what stops a client
  /// write from turning a fresh grant back to `false`.
  static const String badgesCollection = 'badges';

  DocumentReference<Map<String, dynamic>> _user(String uid) =>
      _db.collection(usersCollection).doc(uid);

  DocumentReference<Map<String, dynamic>> _public(String uid) =>
      _db.collection(profilesCollection).doc(uid);

  DocumentReference<Map<String, dynamic>> _badges(String uid) =>
      _db.collection(badgesCollection).doc(uid);

  Stream<UserProfile?> watch(String uid) => _user(uid).snapshots().map(
    (snapshot) => snapshot.exists && snapshot.data() != null
        ? UserProfile.fromMap(uid, snapshot.data()!)
        : null,
  );

  Future<UserProfile?> fetch(String uid) async {
    final snapshot = await _user(uid).get();
    final data = snapshot.data();
    if (!snapshot.exists || data == null) return null;
    return _applyBadges(UserProfile.fromMap(uid, data));
  }

  /// The authoritative badge document, or null when no administrator has
  /// granted anything.
  ///
  /// A missing document means **no badges**: that is how an administrator
  /// revokes a mark. It throws when the document cannot be read at all
  /// (offline, or rules that predate `badges/{uid}`), so callers can tell a
  /// revocation from an unknown state instead of reviving a stale copy.
  Future<ProfileBadges?> fetchBadges(String uid) async {
    final snapshot = await _badges(uid).get();
    final data = snapshot.data();
    if (!snapshot.exists || data == null) return null;
    return ProfileBadges.fromMap(data);
  }

  /// Overrides the badges copied on a profile document with the administrator
  /// document when it exists. Without it the copies stay as they are, because
  /// an administrator may grant a mark directly in the console.
  Future<UserProfile> _applyBadges(UserProfile profile) async {
    try {
      final badges = await fetchBadges(profile.uid);
      if (badges == null) return profile;
      return badges == profile.badges
          ? profile
          : profile.copyWith(badges: badges);
    } on Object {
      // Rules not published yet or offline: keep the stored copy for now.
      return profile;
    }
  }

  /// Live official badges. A missing document emits `null` (no record) so the
  /// caller keeps the copies already on the profile instead of clearing them.
  Stream<ProfileBadges?> watchBadges(String uid) =>
      _badges(uid).snapshots().map((snapshot) {
        final data = snapshot.data();
        if (!snapshot.exists || data == null) return null;
        return ProfileBadges.fromMap(data);
      });

  /// The public mirror plus the official badges, merged into one stream so a
  /// handle in a comment picks up both a rename and a new grant immediately.
  Stream<UserProfile?> watchPublic(String uid) {
    final controller = StreamController<UserProfile?>();
    StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? profileSub;
    StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? badgeSub;
    Map<String, dynamic>? profileData;
    ProfileBadges? badges;
    var hasProfile = false;
    var hasBadges = false;

    void emit() {
      if (!hasProfile) return;
      final data = profileData;
      if (data == null) {
        controller.add(null);
        return;
      }
      var profile = UserProfile.fromPublicMap(uid, data);
      if (hasBadges && badges != null) {
        profile = profile.copyWith(badges: badges);
      }
      controller.add(profile);
    }

    controller.onListen = () {
      profileSub = _public(uid).snapshots().listen((snapshot) {
        hasProfile = true;
        profileData = snapshot.data();
        emit();
      }, onError: controller.addError);
      // A missing or unreadable badge document never breaks the profile; the
      // stored badges keep rendering until the rules are published.
      badgeSub = _badges(uid).snapshots().listen((snapshot) {
        hasBadges = true;
        final data = snapshot.data();
        // No document = no administrator record, so the copies already on the
        // profile stay (that is where a console grant lives). Values that are
        // explicitly `false` do clear the mark.
        badges = snapshot.exists && data != null
            ? ProfileBadges.fromMap(data)
            : null;
        emit();
      }, onError: (Object _) {});
    };
    controller.onCancel = () async {
      await profileSub?.cancel();
      await badgeSub?.cancel();
      profileSub = null;
      badgeSub = null;
    };
    return controller.stream;
  }

  Future<UserProfile?> fetchPublic(String uid) async {
    final snapshot = await _public(uid).get();
    final data = snapshot.data();
    if (!snapshot.exists || data == null) return null;
    return _applyBadges(UserProfile.fromPublicMap(uid, data));
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

  /// Bumps the cover version in both profile documents so every device drops
  /// its cached banner and fetches the new one.
  Future<void> setCoverVersion(String uid, int version) async {
    final now = FieldValue.serverTimestamp();
    final batch = _db.batch();
    batch.update(_user(uid), <String, dynamic>{
      'coverVersion': version,
      'updatedAt': now,
    });
    batch.set(_public(uid), <String, dynamic>{
      'coverVersion': version,
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
