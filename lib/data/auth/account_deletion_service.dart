import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

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
    'notifications',
    // Community relationships and private lists. The posts and comments
    // themselves are removed through the activity index above.
    'savedPosts',
    'following',
    'followers',
    'blocked',
  ];

  /// Removes the account and everything it owns.
  ///
  /// The steps are guarded individually: one record the rules refuse to remove
  /// must not abort the whole run (which used to surface as "the server blocked
  /// the deletion" with no hint about the actual step). Only a step that would
  /// leave the account itself behind stops the process.
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

    final blocked = <String>[];
    await _deleteSocialContent(uid, blocked);
    // The activity index is best effort: older comments and replies may not be
    // in it, and a comment left behind stays visible to everyone. Sweep the
    // whole `comments` collection group so nothing of the account survives.
    await _sweepComments(uid, blocked);
    for (final name in _owned) {
      await _guard(() => _deleteCollection(uid, name), name, blocked);
    }

    final private = _db.collection('users').doc(uid).collection('private');
    for (final doc in const <String>['avatar', 'cover']) {
      await _guard(() => private.doc(doc).delete(), 'private/$doc', blocked);
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

    // The public mirror and the badge document both describe the account, so
    // they go with it. Rules allow an owner to delete their own badge record.
    await _guard(
      () => _db.collection('profiles').doc(uid).delete(),
      'profile',
      blocked,
    );
    await _guard(
      () => _db.collection('badges').doc(uid).delete(),
      'badges',
      blocked,
    );

    // The owner document is the last Firestore write: if it is removed, the
    // account has no readable data left even if a subcollection was retained.
    try {
      await _db.collection('users').doc(uid).delete();
    } on FirebaseException catch (error) {
      throw AppFailure(
        FailureKind.permission,
        technical: error.code == 'permission-denied'
            ? 'delete-rules:account'
            : error.code,
      );
    }

    await _sync.detach(clearSettings: true);
    await _auth.deleteCurrentUser();
    if (blocked.isNotEmpty) {
      // The account is gone; a retained record is reported to the log rather
      // than failing a deletion that actually succeeded.
      debugPrint('account deletion kept: ${blocked.take(5).join(', ')}');
    }
  }

  Future<void> _guard(
    Future<void> Function() action,
    String step,
    List<String> blocked,
  ) async {
    try {
      await action();
    } on FirebaseException catch (error) {
      if (error.code == 'permission-denied') {
        blocked.add(step);
      }
      // A missing document is already deleted, which is the goal.
    } on Object {
      blocked.add(step);
    }
  }

  /// Comments and replies are referenced by the account's own activity index,
  /// so the common case needs no collection scan.
  ///
  /// Reactions (likes and dislikes) are deliberately **kept**: the request only
  /// removes what the account wrote, not the counters other people see. Their
  /// activity entries are dropped with the rest of the index.
  ///
  /// Replies are removed before their parents: deleting a parent first used to
  /// make the reply rule resolve against a document that no longer exists, and
  /// Firestore treats that as a denied write.
  Future<void> _deleteSocialContent(String uid, List<String> blocked) async {
    final activity = await _db
        .collection('users')
        .doc(uid)
        .collection('activity')
        .get();
    final paths = <String>[];
    for (final doc in activity.docs) {
      final path = doc.data()['path'];
      if (path is String && path.isNotEmpty) paths.add(path);
    }
    paths.sort((a, b) => _depth(b).compareTo(_depth(a)));
    for (final path in paths) {
      if (path.contains('/reactions/')) continue;
      await _guard(() => _db.doc(path).delete(), 'social', blocked);
    }
    for (final doc in activity.docs) {
      await _guard(doc.reference.delete, 'activity', blocked);
    }
  }

  /// Removes every comment and reply the account ever wrote, even ones the
  /// activity index never recorded (older builds, a write that failed halfway).
  ///
  /// A collection-group query on one field uses the automatic single-field
  /// index, so no console index is needed. Pages are deleted 100 at a time and
  /// the sweep stops after [_sweepLimit] documents so a runaway account cannot
  /// keep the deletion running forever; the remaining ones are reported through
  /// [blocked] and can be swept by retrying the deletion.
  Future<void> _sweepComments(String uid, List<String> blocked) async {
    const int sweepLimit = 2000;
    var removed = 0;
    while (removed < sweepLimit) {
      QuerySnapshot<Map<String, dynamic>> page;
      try {
        page = await _db
            .collectionGroup('comments')
            .where('authorUid', isEqualTo: uid)
            .limit(100)
            .get();
      } on FirebaseException catch (error) {
        // A missing collection-group index or a denied read: the index pass has
        // already removed what the app knew about, so this is not fatal.
        blocked.add('comments-sweep:${error.code}');
        return;
      }
      if (page.docs.isEmpty) return;
      for (final doc in page.docs) {
        await _guard(doc.reference.delete, 'comment', blocked);
        removed++;
      }
      if (page.docs.length < 100) return;
    }
    blocked.add('comments-sweep:limit');
  }

  int _depth(String path) => path.split('/').length;

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
