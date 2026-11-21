import 'package:cloud_firestore/cloud_firestore.dart';

import '../../core/storage/local_store.dart';
import '../../core/utils/hashtags.dart';
import '../models/community.dart';
import '../models/social.dart';
import '../models/sticker_catalog.dart';
import '../models/user_profile.dart';
import 'notification_repository.dart';

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
  SocialRepository(this._db, [this._store, this._stickers]);

  final FirebaseFirestore _db;

  /// Local cache/guard store. Optional so tests can build a repository without
  /// a Hive box.
  final LocalStore? _store;

  /// Bundled sticker catalogue. Optional so tests can build a repository
  /// without assets; when present, a comment may only reference a known id.
  final StickerCatalog? _stickers;

  /// Sticker ids are namespaced (`om_…` for OpenMoji, `cb_…` for the Wings
  /// chibi set). The same shape is enforced by the Firestore rules.
  static final RegExp stickerIdPattern = RegExp(r'^(om|cb)_[a-z0-9_]+$');

  static const int pageSize = 20;
  static const int previewSize = 3;
  static const int maxCommentLength = 1000;
  static const int minCommentLength = 1;

  /// Aggregation reads cost a document read per 1000 matches; a two minute
  /// cache means opening the same episode repeatedly costs nothing.
  static const Duration countsTtl = Duration(minutes: 2);

  /// One comment or reply per account every few seconds stops accidental
  /// double taps and scripted spam before a write reaches Firestore.
  static const Duration commentCooldown = Duration(seconds: 4);

  String _countsKey(String episodeId) => 'social_counts_$episodeId';

  DocumentReference<Map<String, dynamic>> _episode(String id) =>
      _db.collection('episodes').doc(id);

  CollectionReference<Map<String, dynamic>> _comments(String episodeId) =>
      _episode(episodeId).collection('comments');

  CollectionReference<Map<String, dynamic>> _reactions(String episodeId) =>
      _episode(episodeId).collection('reactions');

  CollectionReference<Map<String, dynamic>> _activity(String uid) =>
      _db.collection('users').doc(uid).collection('activity');

  late final NotificationRepository _notifications = NotificationRepository(
    _db,
  );

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
  Future<EpisodeCounts> counts(
    String episodeId, {
    bool allowCache = true,
  }) async {
    final store = _store;
    if (allowCache && store != null) {
      final cached = store.readCache(_countsKey(episodeId));
      if (cached is Map) {
        int read(String key) {
          final value = cached[key];
          return value is num ? value.toInt() : 0;
        }

        return EpisodeCounts(
          likes: read('likes'),
          dislikes: read('dislikes'),
          comments: read('comments'),
        );
      }
    }
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
    final counts = EpisodeCounts(
      likes: results[0],
      dislikes: results[1],
      comments: results[2],
    );
    if (store != null) {
      await store.putCache(_countsKey(episodeId), <String, dynamic>{
        'likes': counts.likes,
        'dislikes': counts.dislikes,
        'comments': counts.comments,
      }, ttl: countsTtl);
    }
    return counts;
  }

  // ----------------------------------------------------------------- comments

  /// Live newest comments. Only the visible episode's first page (or the short
  /// preview under the player) is listened to, so the listener never grows.
  Stream<List<EpisodeComment>> watchLatest(
    String episodeId, {
    int limit = pageSize,
  }) => _comments(episodeId)
      .orderBy('createdAt', descending: true)
      .limit(limit)
      .snapshots()
      // Old soft-deleted placeholders are hidden instead of being rendered.
      .map(
        (snapshot) => _ordered(
          snapshot.docs
              .map(
                (doc) => EpisodeComment.fromDoc(episodeId, doc.id, doc.data()),
              )
              .where((comment) => !comment.isDeleted)
              .toList(growable: false),
        ),
      );

  /// Pinned first, then newest to oldest. The page is already newest-first, so
  /// this is one local sort and never a second query.
  List<EpisodeComment> _ordered(List<EpisodeComment> comments) {
    final ordered = <EpisodeComment>[...comments];
    ordered.sort((a, b) {
      if (a.pinned != b.pinned) return a.pinned ? -1 : 1;
      return b.createdAt.compareTo(a.createdAt);
    });
    return ordered;
  }

  /// Medals of the first three commenters on an episode.
  ///
  /// A medal marks *who commented first*, so it has to be read oldest-first.
  /// Ranking by position in the newest-first list (the previous behaviour)
  /// handed the gold medal to every new comment and pushed the earlier
  /// commenters down to silver and bronze. Deleted placeholders are skipped so
  /// a removed comment does not hold a medal forever.
  Stream<Map<String, int>> watchTopRanks(String episodeId) =>
      _comments(episodeId).orderBy('createdAt').limit(12).snapshots().map((
        snapshot,
      ) {
        final ranks = <String, int>{};
        for (final doc in snapshot.docs) {
          final comment = EpisodeComment.fromDoc(episodeId, doc.id, doc.data());
          if (comment.isDeleted) continue;
          ranks[comment.id] = ranks.length + 1;
          if (ranks.length == 3) break;
        }
        return ranks;
      });

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
      items: _ordered(
        snapshot.docs
            .map((doc) => EpisodeComment.fromDoc(episodeId, doc.id, doc.data()))
            .where((comment) => !comment.isDeleted)
            .toList(growable: false),
      ),
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
                .where((reply) => !reply.isDeleted)
                .toList(growable: false),
          );

  Future<String> addComment({
    required String episodeId,
    required UserProfile author,
    String text = '',
    String? parentId,
    String? stickerId,
    List<MentionRef> mentions = const <MentionRef>[],
    List<AnimeRef> animeRefs = const <AnimeRef>[],
  }) async {
    final trimmed = text.trim();
    final sticker = (stickerId ?? '').trim().isEmpty ? null : stickerId!.trim();
    // A sticker on its own is a complete comment; an empty draft is not.
    if (trimmed.isEmpty && sticker == null) {
      throw ArgumentError('empty comment');
    }
    if (trimmed.length > maxCommentLength) {
      throw ArgumentError('comment too long');
    }
    if (sticker != null) {
      if (!stickerIdPattern.hasMatch(sticker)) {
        throw ArgumentError('invalid sticker');
      }
      final catalog = _stickers;
      if (catalog != null && catalog.byId(sticker) == null) {
        throw ArgumentError('unknown sticker');
      }
    }
    final store = _store;
    if (store != null) {
      final key = 'comment_guard_${author.uid}';
      final last = int.tryParse(
        store.getString(LocalStore.cacheBox, key) ?? '',
      );
      final now = DateTime.now().millisecondsSinceEpoch;
      if (last != null && now - last < commentCooldown.inMilliseconds) {
        throw StateError('comment-too-fast');
      }
      await store.setString(LocalStore.cacheBox, key, '$now');
    }
    final collection = parentId == null
        ? _comments(episodeId)
        : _comments(episodeId).doc(parentId).collection('replies');
    final ref = collection.doc();
    final batch = _db.batch();
    final hashtags = extractHashtags(
      trimmed,
      exclude: animeRefs.map((ref) => ref.title),
    );
    final data = <String, dynamic>{
      'episodeId': episodeId,
      'authorUid': author.uid,
      'authorUsername': author.username,
      'authorName': author.displayName,
      'authorBadges': author.badges.toMap(),
      'photoVersion': author.photoVersion,
      'text': trimmed,
      'stickerId': ?sticker,
      if (mentions.isNotEmpty)
        'mentions': mentions.map((item) => item.toMap()).toList(),
      if (animeRefs.isNotEmpty)
        'animeRefs': animeRefs.map((item) => item.toMap()).toList(),
      if (hashtags.isNotEmpty) 'hashtags': hashtags,
      'edited': false,
      'deleted': false,
      'pinned': false,
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
    await _invalidateCounts(episodeId);

    if (parentId != null) {
      // The author of the parent comment is told about the reply in their own
      // notification list. Best effort: the reply itself is already saved.
      try {
        final parent = await _comments(episodeId).doc(parentId).get();
        final owner = parent.data()?['authorUid'] as String? ?? '';
        await _notifications.sendReply(
          toUid: owner,
          actor: author,
          episodeId: episodeId,
          commentId: parentId,
          text: trimmed.isEmpty ? 'أرسل ملصقًا' : trimmed,
        );
      } on Object {
        // Offline or the parent vanished; the thread stays correct.
      }
    }
    return ref.id;
  }

  /// The Owner may pin any episode comment. The rules enforce the role, so a
  /// client cannot pin by simply calling this.
  Future<void> setPinnedComment({
    required String episodeId,
    required String commentId,
    String? parentId,
    required bool pinned,
  }) {
    final ref = parentId == null
        ? _comments(episodeId).doc(commentId)
        : _comments(episodeId)
              .doc(parentId)
              .collection('replies')
              .doc(commentId);
    return ref.update(<String, dynamic>{'pinned': pinned});
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

  /// Removes a comment completely, together with every reply it holds, so the
  /// thread looks exactly as if it had never been written instead of leaving a
  /// "this comment was deleted" placeholder behind.
  ///
  /// Deleting a reply removes just that reply and decrements its parent.
  Future<void> deleteComment({
    required String episodeId,
    required String commentId,
    required String uid,
    String? parentId,
  }) async {
    final comments = _comments(episodeId);
    final ref = parentId == null
        ? comments.doc(commentId)
        : comments.doc(parentId).collection('replies').doc(commentId);

    if (parentId == null) {
      // Replies are removed in chunks, keeping every batch under the 500-write
      // limit so a long thread can never fail halfway.
      final replies = await ref.collection('replies').get();
      final docs = replies.docs;
      for (var index = 0; index < docs.length; index += 400) {
        final chunk = _db.batch();
        for (final doc in docs.skip(index).take(400)) {
          chunk.delete(doc.reference);
        }
        await chunk.commit();
      }
    }

    final batch = _db.batch();
    batch.delete(ref);
    if (parentId != null) {
      batch.update(comments.doc(parentId), <String, dynamic>{
        'replyCount': FieldValue.increment(-1),
      });
    }
    batch.delete(_activity(uid).doc('comment_$commentId'));
    await batch.commit();
    await _invalidateCounts(episodeId);
  }

  /// Copies the current username, display name, badges and photo version into
  /// every comment and reply the account already wrote.
  ///
  /// Comments store a display snapshot, so without this a rename or a new
  /// verification badge would only show on future comments. The activity index
  /// makes the lookup exact and index-free, and the fingerprint in the local
  /// cache keeps repeated launches free.
  Future<void> syncAuthor(UserProfile author) async {
    final store = _store;
    final signature =
        '${author.username}|${author.displayName}|'
        '${author.badges.verified}|${author.badges.developer}|'
        '${author.photoVersion}';
    final signatureKey = 'social_author_sig_${author.uid}';
    if (store != null &&
        store.getString(LocalStore.cacheBox, signatureKey) == signature) {
      return;
    }
    try {
      final activity = await _activity(author.uid).get();
      final refs = <DocumentReference<Map<String, dynamic>>>[];
      for (final doc in activity.docs) {
        final data = doc.data();
        final type = data['type'];
        final path = data['path'];
        if (type != 'comment' && type != 'reply') continue;
        if (path is! String || !path.startsWith('episodes/')) continue;
        refs.add(_db.doc(path));
      }
      for (var index = 0; index < refs.length; index += 400) {
        final batch = _db.batch();
        for (final ref in refs.skip(index).take(400)) {
          batch.update(ref, <String, dynamic>{
            'authorUsername': author.username,
            'authorName': author.displayName,
            'authorBadges': author.badges.toMap(),
            'photoVersion': author.photoVersion,
            'updatedAt': FieldValue.serverTimestamp(),
          });
        }
        await batch.commit();
      }
      if (store != null) {
        await store.setString(LocalStore.cacheBox, signatureKey, signature);
      }
    } on Object {
      // Offline or denied: the next launch retries with the same fingerprint.
    }
  }

  Future<void> _invalidateCounts(String episodeId) async {
    try {
      await _store?.delete(LocalStore.cacheBox, _countsKey(episodeId));
    } on Object {
      // A missing cache entry is harmless.
    }
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
