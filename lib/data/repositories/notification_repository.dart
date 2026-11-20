import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/social_notification.dart';
import '../models/user_profile.dart';

/// Community alerts stored per account.
///
/// A reply is written by the device that posted it, straight into the parent
/// comment author's `notifications` subcollection. That keeps the feature
/// serverless: no Cloud Function is needed, and the rules allow a signed-in user
/// to create exactly one kind of document there.
class NotificationRepository {
  NotificationRepository(this._db);

  final FirebaseFirestore _db;

  CollectionReference<Map<String, dynamic>> _mine(String uid) =>
      _db.collection('users').doc(uid).collection('notifications');

  Stream<List<SocialNotification>> watch(String uid, {int limit = 50}) =>
      _mine(uid)
          .orderBy('createdAt', descending: true)
          .limit(limit)
          .snapshots()
          .map(
            (snapshot) => snapshot.docs
                .map((doc) => SocialNotification.fromDoc(doc.id, doc.data()))
                .where(
                  (item) =>
                      item.episodeId.isNotEmpty ||
                      item.postId.isNotEmpty ||
                      item.type == 'admin',
                )
                .toList(growable: false),
          );

  Future<List<SocialNotification>> unread(String uid) async {
    final snapshot = await _mine(uid)
        .where('read', isEqualTo: false)
        .limit(20)
        .get();
    final items = snapshot.docs
        .map((doc) => SocialNotification.fromDoc(doc.id, doc.data()))
        .toList(growable: false);
    items.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return items;
  }

  /// Records a reply for the author of the parent comment.
  Future<void> sendReply({
    required String toUid,
    required UserProfile actor,
    required String episodeId,
    required String commentId,
    required String text,
    String? episodeNumber,
    String? animeTitle,
  }) async {
    if (toUid.isEmpty || toUid == actor.uid) return;
    final payload = <String, dynamic>{
      'type': 'reply',
      'toUid': toUid,
      'actorUid': actor.uid,
      'actorName': actor.displayName,
      'actorUsername': actor.username,
      'actorBadges': actor.badges.toMap(),
      'photoVersion': actor.photoVersion,
      'text': text.length > 180 ? '${text.substring(0, 180)}…' : text,
      'episodeId': episodeId,
      'commentId': commentId,
      'read': false,
      'createdAt': FieldValue.serverTimestamp(),
    };
    if (episodeNumber != null) payload['episodeNumber'] = episodeNumber;
    if (animeTitle != null) payload['animeTitle'] = animeTitle;
    await _mine(toUid).add(payload);
  }

  /// A community alert: a like, a comment, a reply or a new follower.
  ///
  /// The document id is chosen by the caller and is deterministic
  /// (`like_{postId}_{actor}`), so retrying a request after a timeout can never
  /// post the same alert twice: the second write is refused as an existing
  /// document. The shape is re-checked by the rules, which also verify that
  /// `actorUid` is the signed-in account.
  Future<void> sendSocial({
    required String toUid,
    required UserProfile actor,
    required String type,
    required String id,
    String postId = '',
    String commentId = '',
    String text = '',
  }) async {
    if (toUid.isEmpty || toUid == actor.uid) return;
    if (!const <String>{'like', 'comment', 'reply', 'follow'}.contains(type)) {
      throw ArgumentError('unknown alert type');
    }
    final payload = <String, dynamic>{
      'type': type,
      'toUid': toUid,
      'actorUid': actor.uid,
      'actorName': actor.displayName,
      'actorUsername': actor.username,
      'actorBadges': actor.badges.toMap(),
      'photoVersion': actor.photoVersion,
      'text': text.length > 180 ? '${text.substring(0, 180)}…' : text,
      'read': false,
      'createdAt': FieldValue.serverTimestamp(),
    };
    if (postId.isNotEmpty) payload['postId'] = postId;
    if (commentId.isNotEmpty) payload['commentId'] = commentId;
    try {
      await _mine(toUid).doc(id).set(payload);
    } on FirebaseException catch (error) {
      // `already-exists` is the expected result of a retried like or follow:
      // the alert is already there, so this is a success, not a failure.
      if (error.code == 'already-exists') return;
      rethrow;
    }
  }

  Future<void> markRead(String uid, Iterable<String> ids) async {
    final list = ids.toList(growable: false);
    if (list.isEmpty) return;
    final batch = _db.batch();
    for (final id in list.take(400)) {
      batch.update(_mine(uid).doc(id), <String, dynamic>{'read': true});
    }
    await batch.commit();
  }

  Future<void> markAllRead(String uid) async {
    final snapshot = await _mine(uid)
        .where('read', isEqualTo: false)
        .limit(200)
        .get();
    if (snapshot.docs.isEmpty) return;
    final batch = _db.batch();
    for (final doc in snapshot.docs) {
      batch.update(doc.reference, <String, dynamic>{'read': true});
    }
    await batch.commit();
  }

  Future<void> remove(String uid, String id) => _mine(uid).doc(id).delete();

  Future<void> clear(String uid) async {
    final snapshot = await _mine(uid).limit(200).get();
    if (snapshot.docs.isEmpty) return;
    final batch = _db.batch();
    for (final doc in snapshot.docs) {
      batch.delete(doc.reference);
    }
    await batch.commit();
  }
}
