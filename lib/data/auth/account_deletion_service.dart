import 'package:cloud_firestore/cloud_firestore.dart';

import '../../core/errors/app_failure.dart';
import '../repositories/user_repository.dart';
import '../repositories/username_repository.dart';
import '../sync/cloud_sync_service.dart';
import 'firebase_auth_repository.dart';

/// Deletes an account and everything it owns.
///
/// Firestore does not cascade-delete subcollections, so the process is
/// explicit and resumable:
///
/// 1. Re-authenticate first (Firebase requires a recent login for `delete()`),
///    so a cancelled password/Google prompt never touches the database.
/// 2. Flag the profile as `pendingDeletion` so a half-finished run is visible.
/// 3. Walk `users/{uid}/activity` and delete each referenced comment and
///    reaction, then the index entries.
/// 4. Delete every subcollection in batches, then the avatar document.
/// 5. Release the username reservation so the handle becomes claimable again.
/// 6. Delete the public mirror and the owner document.
/// 7. Delete the Firebase Authentication user and clear local account data.
///
/// Because Cloud Functions are not available on the free plan, this runs on the
/// client and is authorized by Firestore rules that only allow the owner to
/// delete their own records. A failure at any step leaves the data consistent
/// enough to retry: nothing was made public and the account stays flagged.
class AccountDeletionService {
  AccountDeletionService(
    this._db,
    this._auth,
    this._users,
    this._usernames,
    this._sync,
  );

  final FirebaseFirestore _db;
  final FirebaseAuthRepository _auth;
  final UserRepository _users;
  final UsernameRepository _usernames;
  final CloudSyncService _sync;

  static const List<String> _owned = <String>[
    'library',
    'history',
    'settings',
    'meta',
    'activity',
  ];

  Future<void> deleteAccount({required String uid, String? password}) async {
    final profile = await _users.fetch(uid);

    // A recent login is mandatory for `user.delete()`. Doing it before any
    // Firestore write means a wrong password or a cancelled Google prompt
    // leaves the account exactly as it was.
    await _auth.reauthenticate(password: password);

    try {
      await _users.markPendingDeletion(uid);
    } on Object {
      // The flag is only a marker; never let it block the deletion itself.
    }

    try {
      await _deleteSocialContent(uid);
      for (final name in _owned) {
        await _deleteCollection(uid, name);
      }
      final private = _db.collection('users').doc(uid).collection('private');
      for (final doc in const <String>['avatar', 'cover']) {
        try {
          await private.doc(doc).delete();
        } on Object {
          // Missing or already removed.
        }
      }

      if (profile != null) {
        try {
          await _usernames.release(
            uid: uid,
            normalized: profile.normalizedUsername,
          );
        } on Object {
          // A reservation owned by another account is left untouched.
        }
      }

      await _db.collection('profiles').doc(uid).delete();
      await _db.collection('users').doc(uid).delete();
    } on FirebaseException catch (error) {
      // Surface the exact Firestore code so the UI can explain whether the
      // rules are outdated or the data is simply unreachable.
      throw AppFailure(
        FailureKind.permission,
        technical: error.code == 'permission-denied'
            ? 'delete-rules'
            : error.code,
      );
    }

    await _sync.detach(clearSettings: true);
    await _auth.deleteCurrentUser();
  }

  /// Comments and reactions are referenced by the account's own activity index,
  /// so deletion needs no collection-group index or collection scan.
  Future<void> _deleteSocialContent(String uid) async {
    final activity = await _db
        .collection('users')
        .doc(uid)
        .collection('activity')
        .get();
    for (final doc in activity.docs) {
      final path = doc.data()['path'];
      if (path is String && path.isNotEmpty) {
        try {
          await _db.doc(path).delete();
        } on Object {
          // Already removed or not deletable; the account still goes away.
        }
      }
      await doc.reference.delete();
    }
  }

  /// Deletes a subcollection in small batches to stay under write limits and to
  /// make an interrupted run cheap to resume.
  Future<void> _deleteCollection(String uid, String name) async {
    final collection = _db.collection('users').doc(uid).collection(name);
    while (true) {
      final snapshot = await collection.limit(100).get();
      if (snapshot.docs.isEmpty) return;
      final batch = _db.batch();
      for (final doc in snapshot.docs) {
        batch.delete(doc.reference);
      }
      await batch.commit();
      if (snapshot.docs.length < 100) return;
    }
  }
}
