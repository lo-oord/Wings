import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/social.dart';
import '../models/user_profile.dart';

/// Episode reactions, comments, replies and reports.
///
/// Collections:
/// * `episodes/{episodeId}/reactions/{uid}` — one deterministic document per
///   user, so repeated taps can never create duplicates.
/// * `episodes/{episodeId}/comments/{commentId}` and its `replies`
///   subcollection.
/// * `users/{uid}/activity/{activityId}` — an index of the signed-in user's
///   social documents, used for an exact, index-free account deletion.
/// * `reports/{reportId}` — moderation reports; not readable by ordinary
///   users.
class SocialRepository {
  SocialRepository(this._db);

  final FirebaseFirestore _db;

  static const int pageSize = 20;
  static const int maxCommentLength = 1000;
  static const int minCommentLength = 1;

  DocumentReference<Map<String, dynamic>> _episode(String id) =>
      _db.collection('episodes').doc(id);

  CollectionReference<Map<String, dynamic>> _comments(String episodeId) =>
      _episode(episodeId).collection('comments');

  CollectionReference<Map<String, dynamic>> _reactions(String episodeId) =>
      _episode(episodeId).collection('reactions');

  CollectionReference<Map<String, dynamic>> _activity(String uid) =>
      _db.collection('users').doc(uid).collection('activity');

  // ---------------------------------------------------------------- reactions

  Future<ReactionType?> myReaction(String episodeId, String uid) async {
    final snapshot = await _reactions(episodeId).doc(uid).get();
    final type = snapshot.data()?['type'];
    return ReactionType.values.where((value) => value.name == type).firstOrNull;
  }

  /// Sets, switches or removes the current user's reaction. Passing null
  /// deletes it; the document id is the uid, so there is never a duplicate.
  Future<void> setReaction({
    required String episodeId,
    required String uid,
    required ReactionType? type,
  }) async {
    final ref = _reactions(episodeId).doc(uid);
    final batch = _db.batch();
    if (type == null) {
      batch.delete(ref);
      batch.delete(_activity(uid).doc('reaction_$episodeId'));
      await batch.commit();
      return;
    }
    batch.set(ref, <String, dynamic>{
      'uid': uid,
      'episodeId': episodeId,
      'type': type.name,
      'updatedAt': FieldValue.serverTimestamp(),
    });
    batch.set(_activity(uid).doc('reaction_$episodeId'), <String, dynamic>{
      'type': 'reaction',
      'episodeId': episodeId,
      'path': 'episodes/$episodeId/reactions/$uid',
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    await batch.commit();
  }

  /// Aggregation queries return counts in one round trip with a single
  /// document read billed per 1000 matches, which keeps the free plan cheap.
  Future<EpisodeCounts> counts(String episodeId) async {
    final results = await Future.wait(<Future<int>>[
      _reactions(episodeId)
          .where('type', isEqualTo: ReactionType.like.name)
          .count()
          .get()
          .then((value) => value.count ?? 0),
      _reactions(episodeId)
          .where('type', isEqualTo: ReactionType.dislike.name)
          .count()
          .get()
          .then((value) => value.count ?? 0),
      _comments(episodeId)
          .where('deleted', isEqualTo: false)
          .count()
          .get()
          .then((value) => value.count ?? 0),
    ]);
    return EpisodeCounts(
      likes: results[0],
      dislikes: results[1],
      comments: results[2],
    );
  }

  // ----------------------------------------------------------------- comments

  /// Live first page. Only the visible episode's newest page is listened to.
  Stream<List<EpisodeComment>> watchLatest(String episodeId) =>
      _comments(episodeId)
          .orderBy('createdAt', descending: true)
          .limit(pageSize)
          .snapshots()
          .map(
            (snapshot) => snapshot.docs
                .map(
                  (doc) =>
                      EpisodeComment.fromDoc(episodeId, doc.id, doc.data()),
                )
                .toList(growable: false),
          );

  /// Cursor pagination for older comments.
  Future<CommentPage> page(
    String episodeId, {
    DocumentSnapshot<Map<String, dynamic>>? after,
  }) async {
    var query = _comments(episodeId)
        .orderBy('createdAt', descending: true)
        .limit(pageSize);
    if (after != null) query = query.startAfterDocument(after);
    final snapshot = await query.get();
    return CommentPage(
      items: snapshot.docs
          .map((doc) => EpisodeComment.fromDoc(episodeId, doc.id, doc.data()))
          .toList(growable: false),
      cursor: snapshot.docs.isEmpty ? null : snapshot.docs.last,
      hasMore: snapshot.docs.length == pageSize,
    );
  }

  Stream<List<EpisodeComment>> watchReplies(
    String episodeId,
    String commentId,
  ) =>
      _comments(episodeId)
          .doc(commentId)
          .collection('replies')
          .orderBy('createdAt')
          .limit(pageSize)
          .snapshots()
          .map(
            (snapshot) => snapshot.docs
                .map(
                  (doc) => EpisodeComment.fromDoc(
                    episodeId,
                    doc.id,
                    doc.data(),
                    parentId: commentId,
                  ),
                )
                .toList(growable: false),
          );

  Future<String> addComment({
    required String episodeId,
    required UserProfile author,
    required String text,
    String? parentId,
  }) async {
    final trimmed = text.trim();
    if (trimmed.length < minCommentLength || trimmed.isEmpty) {
      throw ArgumentError('empty comment');
    }
    if (trimmed.length > maxCommentLength) {
      throw ArgumentError('comment too long');
    }
    final collection = parentId == null
        ? _comments(episodeId)
        : _comments(episodeId).doc(parentId).collection('replies');
    final ref = collection.doc();
    final batch = _db.batch();
    final data = <String, dynamic>{
      'episodeId': episodeId,
      'authorUid': author.uid,
      'authorUsername': author.username,
      'authorName': author.displayName,
      'authorBadges': author.badges.toMap(),
      'photoVersion': author.photoVersion,
      'text': trimmed,
      'edited': false,
      'deleted': false,
      'replyCount': 0,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    };
    if (parentId != null) {
      data['parentId'] = parentId;
      batch.update(_comments(episodeId).doc(parentId), <String, dynamic>{
        'replyCount': FieldValue.increment(1),
      });
    }
    batch.set(ref, data);
    batch.set(_activity(author.uid).doc('comment_${ref.id}'), <String, dynamic>{
      'type': parentId == null ? 'comment' : 'reply',
      'episodeId': episodeId,
      'commentId': ref.id,
      'path': ref.path,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    await batch.commit();
    return ref.id;
  }

  Future<void> editComment({
    required String episodeId,
    required String commentId,
    required String path,
    required String text,
  }) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty || trimmed.length > maxCommentLength) {
      throw ArgumentError('invalid comment');
    }
    final ref = path.contains('/replies/')
        ? _comments(episodeId).doc(commentId)
        : _comments(episodeId).doc(commentId);
    await ref.update(<String, dynamic>{
      'text': trimmed,
      'edited': true,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  /// Soft deletes the comment: the text is removed immediately and the document
  /// stays as an empty placeholder so replies keep their place.
  Future<void> deleteComment({
    required String episodeId,
    required String commentId,
    required String uid,
  }) async {
    final ref = _comments(episodeId).doc(commentId);
    final batch = _db.batch();
    batch.update(ref, <String, dynamic>{
      'text': '',
      'deleted': true,
      'updatedAt': FieldValue.serverTimestamp(),
    });
    batch.delete(_activity(uid).doc('comment_$commentId'));
    await batch.commit();
  }

  Future<void> report({
    required String reporterUid,
    required String targetType,
    required String reason,
    String? episodeId,
    String? commentId,
  }) async {
    await _db.collection('reports').add(<String, dynamic>{
      'reporterUid': reporterUid,
      'targetType': targetType,
      'reason': reason,
      'episodeId': episodeId,
      'commentId': commentId,
      'status': 'open',
      'createdAt': FieldValue.serverTimestamp(),
    });
  }
}
