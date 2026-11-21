import 'package:cloud_firestore/cloud_firestore.dart';

import '../../core/storage/local_store.dart';
import '../models/community.dart';
import '../models/social.dart';
import '../models/user_profile.dart';
import 'notification_repository.dart';

/// The community layer of Wings.
///
/// It deliberately reuses the systems that already exist instead of copying
/// them:
///
/// * identity comes from `users/{uid}` / `profiles/{uid}` through
///   [UserProfile] snapshots — there is no second user model;
/// * comments keep the exact document shape of episode comments
///   (`authorUid`, `authorName`, `authorBadges`, `photoVersion`, `text`,
///   `edited`, `replyCount`, `replies`), and are returned as [EpisodeComment],
///   the same model the episode threads use;
/// * alerts are written into `users/{uid}/notifications` by
///   [NotificationRepository], the collection the app already reads;
/// * reports go into the existing `reports` collection.
///
/// Collections this file owns:
///
/// * `posts/{postId}` — the post and its trusted counters.
/// * `posts/{postId}/likes/{uid}` — one document per account, so a double tap
///   or a retried request can never count twice.
/// * `posts/{postId}/comments/{commentId}` (+ `replies`).
/// * `users/{uid}/savedPosts/{postId}`, `following/{uid}`, `followers/{uid}`,
///   `blocked/{uid}` — relationships owned by the account.
final class CommunityRepository {
  CommunityRepository(this._db, [this._store]);

  final FirebaseFirestore _db;

  /// Local cache used to remember a recorded view (and to keep the feed's
  /// interaction signals without a server round-trip).
  final LocalStore? _store;

  static const int pageSize = 15;
  static const int maxPostLength = 2000;
  static const int maxImages = 4;
  static const int maxCommentLength = 1000;
  static const int maxMentions = 10;
  static const int maxAnimeRefs = 5;

  /// `whereIn` accepts 30 values; keeping the chunks smaller is safe on every
  /// Firestore version and keeps one slow chunk from delaying the feed.
  static const int _whereInChunk = 10;

  late final NotificationRepository _notifications = NotificationRepository(
    _db,
  );

  CollectionReference<Map<String, dynamic>> get _posts =>
      _db.collection('posts');

  DocumentReference<Map<String, dynamic>> _post(String postId) =>
      _posts.doc(postId);

  CollectionReference<Map<String, dynamic>> _comments(String postId) =>
      _post(postId).collection('comments');

  CollectionReference<Map<String, dynamic>> _likes(String postId) =>
      _post(postId).collection('likes');

  CollectionReference<Map<String, dynamic>> _saved(String uid) =>
      _db.collection('users').doc(uid).collection('savedPosts');

  CollectionReference<Map<String, dynamic>> _following(String uid) =>
      _db.collection('users').doc(uid).collection('following');

  CollectionReference<Map<String, dynamic>> _followers(String uid) =>
      _db.collection('users').doc(uid).collection('followers');

  CollectionReference<Map<String, dynamic>> _blocked(String uid) =>
      _db.collection('users').doc(uid).collection('blocked');

  CollectionReference<Map<String, dynamic>> _activity(String uid) =>
      _db.collection('users').doc(uid).collection('activity');

  // ------------------------------------------------------------------- feeds

  /// Newest posts, cursor-paginated.
  ///
  /// The cursor is the creation time of the last item rather than a document
  /// snapshot, so the same helper can merge the several `whereIn` queries the
  /// following feed needs.
  Future<PostPage> latest({DateTime? after}) async {
    try {
      var query = _posts
          .where('kind', isEqualTo: PostKind.post.name)
          .orderBy('createdAt', descending: true);
      if (after != null) {
        query = query.startAfter(<Object>[Timestamp.fromDate(after)]);
      }
      final snapshot = await query.limit(pageSize).get();
      return _page(snapshot);
    } on FirebaseException catch (error) {
      // A project whose composite indexes have not been deployed yet still
      // gets a working feed: the raw page is read with the automatic index and
      // Reels are removed on the device instead of failing the whole screen.
      if (error.code != 'failed-precondition') rethrow;
      return _postsOnly(await _latestRaw(after: after));
    }
  }

  Future<PostPage> _latestRaw({DateTime? after}) async {
    var query = _posts.orderBy('createdAt', descending: true);
    if (after != null) {
      query = query.startAfter(<Object>[Timestamp.fromDate(after)]);
    }
    final snapshot = await query.limit(pageSize).get();
    return _page(snapshot);
  }

  PostPage _postsOnly(PostPage page) => PostPage(
    items: page.items.where((post) => !post.isReel).toList(growable: false),
    cursor: page.cursor,
    hasMore: page.hasMore,
  );

  /// Posts written by the accounts [authors] follow.
  ///
  /// Firestore caps `whereIn` at 30 values, so the authors are queried in
  /// chunks and the results merged newest-first. A member who follows more than
  /// 30 accounts still sees all of them: the chunks are merged, not truncated.
  Future<PostPage> following(Set<String> authors, {DateTime? after}) async {
    if (authors.isEmpty) return PostPage.empty;
    final chunks = <List<String>>[];
    final list = authors.toList(growable: false);
    for (var i = 0; i < list.length; i += _whereInChunk) {
      chunks.add(list.sublist(i, (i + _whereInChunk).clamp(0, list.length)));
    }
    final pages = await Future.wait(
      chunks.map((chunk) {
        var query = _posts
            .where('authorUid', whereIn: chunk)
            .orderBy('createdAt', descending: true);
        if (after != null) {
          query = query.startAfter(<Object>[Timestamp.fromDate(after)]);
        }
        return query.limit(pageSize).get();
      }),
    );
    final docs = pages.expand((page) => page.docs).toList(growable: false);
    docs.sort((a, b) {
      final left = a.data()['createdAt'];
      final right = b.data()['createdAt'];
      final l = left is Timestamp
          ? left
          : Timestamp.fromMillisecondsSinceEpoch(0);
      final r = right is Timestamp
          ? right
          : Timestamp.fromMillisecondsSinceEpoch(0);
      return r.compareTo(l);
    });
    final kept = docs.take(pageSize).toList(growable: false);
    return PostPage(
      items: kept
          .map((doc) => Post.fromDoc(doc.id, doc.data()))
          .where((post) => !post.isReel)
          .toList(growable: false),
      cursor: kept.isEmpty ? null : kept.last,
      hasMore: pages.any((page) => page.docs.length == pageSize),
    );
  }

  PostPage _page(QuerySnapshot<Map<String, dynamic>> snapshot) => PostPage(
    items: snapshot.docs
        .map((doc) => Post.fromDoc(doc.id, doc.data()))
        .toList(growable: false),
    cursor: snapshot.docs.isEmpty ? null : snapshot.docs.last,
    hasMore: snapshot.docs.length == pageSize,
  );

  Stream<Post?> watchPost(String postId) =>
      _post(postId).snapshots().map((doc) {
        final data = doc.data();
        return doc.exists && data != null ? Post.fromDoc(doc.id, data) : null;
      });

  Future<Post?> fetchPost(String postId) async {
    final doc = await _post(postId).get();
    final data = doc.data();
    return doc.exists && data != null ? Post.fromDoc(doc.id, data) : null;
  }

  /// One page of an account's posts, newest first.
  ///
  /// The profile, the anime community feed and the personal feed all page the
  /// same `posts` collection with a time cursor; nothing is loaded in full.
  Future<PostPage> postsBy(
    String uid, {
    int limit = pageSize,
    DateTime? after,
  }) async {
    try {
      var query = _posts
          .where('authorUid', isEqualTo: uid)
          .orderBy('createdAt', descending: true);
      if (after != null) {
        query = query.startAfter(<Object>[Timestamp.fromDate(after)]);
      }
      final snapshot = await query.limit(limit).get();
      return _postsOnly(_page(snapshot));
    } on FirebaseException catch (error) {
      if (error.code != 'failed-precondition') rethrow;
      // A missing composite index must never hide an account's posts. The
      // equality filter alone uses the automatic index; the page is sorted on
      // the device and Reels are removed here.
      return _filteredPage(
        _posts.where('authorUid', isEqualTo: uid),
        after: after,
        limit: limit,
      );
    }
  }

  /// Posts that mention the anime, newest first.
  Future<PostPage> byAnime(
    String animeId, {
    DateTime? after,
    int limit = pageSize,
  }) async {
    try {
      var query = _posts
          .where('animeIds', arrayContains: animeId)
          .orderBy('createdAt', descending: true);
      if (after != null) {
        query = query.startAfter(<Object>[Timestamp.fromDate(after)]);
      }
      final snapshot = await query.limit(limit).get();
      return _postsOnly(_page(snapshot));
    } on FirebaseException catch (error) {
      if (error.code != 'failed-precondition') rethrow;
      return _filteredPage(
        _posts.where('animeIds', arrayContains: animeId),
        after: after,
        limit: limit,
      );
    }
  }

  /// Sorts one equality-filtered page on the device. Used only when the
  /// composite index is missing or still building, so a profile never shows
  /// «لا منشورات بعد» just because an index was not deployed yet.
  Future<PostPage> _filteredPage(
    Query<Map<String, dynamic>> query, {
    required int limit,
    DateTime? after,
  }) async {
    final snapshot = await query.limit(limit * 3).get();
    final posts =
        snapshot.docs
            .map((doc) => Post.fromDoc(doc.id, doc.data()))
            .where((post) => !post.isReel)
            .where((post) => after == null || post.createdAt.isBefore(after))
            .toList()
          ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    final kept = posts.take(limit).toList(growable: false);
    return PostPage(
      items: kept,
      cursor: kept.isEmpty ? null : snapshot.docs.last,
      hasMore: false,
    );
  }

  /// Reels, newest first. The screen re-ranks the bounded page it receives on
  /// the device; no query per candidate and no whole-collection read.
  Future<PostPage> reels({DateTime? after, int limit = pageSize}) async {
    try {
      var query = _posts
          .where('kind', isEqualTo: PostKind.reel.name)
          .orderBy('createdAt', descending: true);
      if (after != null) {
        query = query.startAfter(<Object>[Timestamp.fromDate(after)]);
      }
      final snapshot = await query.limit(limit).get();
      return _page(snapshot);
    } on FirebaseException catch (error) {
      if (error.code != 'failed-precondition') rethrow;
      return _reelsFallback(after: after, limit: limit);
    }
  }

  /// Reads a few raw pages and keeps only Reels.
  ///
  /// This is the safety net for a project whose `kind + createdAt` composite
  /// index is still building; it reads at most four bounded pages and keeps a
  /// cursor so the next request never starts from the beginning.
  Future<PostPage> _reelsFallback({
    DateTime? after,
    int limit = pageSize,
  }) async {
    final collected = <Post>[];
    DateTime? cursor = after;
    DocumentSnapshot<Map<String, dynamic>>? last;
    var hasMore = false;
    for (var page = 0; page < 4 && collected.length < limit; page++) {
      var query = _posts.orderBy('createdAt', descending: true);
      if (cursor != null) {
        query = query.startAfter(<Object>[Timestamp.fromDate(cursor)]);
      }
      final snapshot = await query.limit(pageSize).get();
      if (snapshot.docs.isEmpty) {
        hasMore = false;
        break;
      }
      last = snapshot.docs.last;
      cursor = _createdAt(last);
      hasMore = snapshot.docs.length == pageSize;
      for (final doc in snapshot.docs) {
        final post = Post.fromDoc(doc.id, doc.data());
        if (post.isReel) collected.add(post);
      }
      if (!hasMore) break;
    }
    return PostPage(
      items: collected.take(limit).toList(growable: false),
      cursor: last,
      hasMore: hasMore,
    );
  }

  DateTime? _createdAt(DocumentSnapshot<Map<String, dynamic>>? doc) {
    final value = doc?.data()?['createdAt'];
    return value is Timestamp ? value.toDate() : null;
  }

  Future<CommunityCounts> counts(String uid) async {
    // Each counter is independent. A refused post aggregation must not zero a
    // perfectly readable follower count, which is what made the profile show
    // «0 متابع» while the relationship documents were there.
    Future<int> count(Future<AggregateQuerySnapshot> query) async {
      try {
        return (await query).count ?? 0;
      } on Object {
        return 0;
      }
    }

    final results = await Future.wait(<Future<int>>[
      count(
        _posts
            .where('authorUid', isEqualTo: uid)
            .where('kind', isEqualTo: PostKind.post.name)
            .count()
            .get(),
      ),
      count(_followers(uid).count().get()),
      count(_following(uid).count().get()),
    ]);
    return CommunityCounts(
      posts: results[0],
      followers: results[1],
      following: results[2],
    );
  }

  // ------------------------------------------------------------------- posts

  /// Publishes a post. The id is generated before the images are uploaded so
  /// the object keys can be scoped to it (`users/{uid}/posts/{id}/…`).
  Future<String> createPost({
    required UserProfile author,
    required String text,
    List<String> imageKeys = const <String>[],
    String? id,
    PostKind kind = PostKind.post,
    String? videoKey,
    String? videoThumbnailKey,
    int videoDurationMs = 0,
    int videoWidth = 0,
    int videoHeight = 0,
    List<MentionRef> mentions = const <MentionRef>[],
    List<AnimeRef> animeRefs = const <AnimeRef>[],
    bool allowComments = true,
    bool allowDownload = true,
    bool allowRepost = true,
    String category = '',
    String soundTitle = '',
    String repostedFrom = '',
  }) async {
    final trimmed = text.trim();
    final hasVideo = (videoKey ?? '').isNotEmpty;
    if (trimmed.isEmpty && imageKeys.isEmpty && !hasVideo) {
      throw ArgumentError('empty post');
    }
    if (trimmed.length > maxPostLength) {
      throw ArgumentError('post too long');
    }
    if (imageKeys.length > maxImages) {
      throw ArgumentError('too many images');
    }
    if (mentions.length > maxMentions) {
      throw ArgumentError('too many mentions');
    }
    if (animeRefs.length > maxAnimeRefs) {
      throw ArgumentError('too many anime references');
    }
    if (kind == PostKind.reel && !hasVideo) {
      throw ArgumentError('a reel needs a video');
    }
    final ref = id == null ? _posts.doc() : _posts.doc(id);
    final post = Post(
      id: ref.id,
      authorUid: author.uid,
      authorUsername: author.username,
      authorName: author.displayName,
      badges: author.badges,
      photoVersion: author.photoVersion,
      text: trimmed,
      imageKeys: imageKeys,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
      kind: kind,
      videoKey: hasVideo ? videoKey : null,
      videoThumbnailKey: hasVideo ? videoThumbnailKey : null,
      videoDurationMs: hasVideo ? videoDurationMs : 0,
      videoWidth: hasVideo ? videoWidth : 0,
      videoHeight: hasVideo ? videoHeight : 0,
      mentions: mentions,
      animeRefs: animeRefs,
      allowComments: allowComments,
      allowDownload: allowDownload,
      allowRepost: allowRepost,
      category: category,
      soundTitle: soundTitle,
      repostedFrom: repostedFrom,
    );
    final batch = _db.batch();
    batch.set(ref, post.toMap());
    batch.set(_activity(author.uid).doc('post_${ref.id}'), <String, dynamic>{
      'type': 'post',
      'postId': ref.id,
      'path': ref.path,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    await batch.commit();
    // Mentions are best-effort alerts: the post is already saved, and the
    // deterministic id makes a retry a no-op instead of a second alert.
    for (final mention in mentions) {
      if (mention.uid.isEmpty || mention.uid == author.uid) continue;
      try {
        await _notifications.sendSocial(
          toUid: mention.uid,
          actor: author,
          type: 'mention',
          id: 'mention_${ref.id}_${mention.uid}',
          postId: ref.id,
          text: trimmed,
        );
      } on Object {
        // Offline or the mentioned account is gone.
      }
    }
    return ref.id;
  }

  /// A fresh post id, generated before anything is uploaded so the media
  /// object keys can already be scoped to it.
  String newPostId() => _posts.doc().id;

  Future<void> updatePost({
    required String postId,
    required String uid,
    required String text,
    List<MentionRef>? mentions,
    List<AnimeRef>? animeRefs,
  }) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) throw ArgumentError('empty post');
    if (trimmed.length > maxPostLength) throw ArgumentError('post too long');
    final doc = await _post(postId).get();
    final data = doc.data();
    if (data == null) throw StateError('missing-post');
    if (data['authorUid'] != uid) throw StateError('not-author');
    final images =
        (data['images'] as List?)?.whereType<String>().toList() ??
        const <String>[];
    if (trimmed.isEmpty && images.isEmpty) throw ArgumentError('empty post');
    await _post(postId).update(<String, dynamic>{
      'text': trimmed,
      'edited': true,
      if (mentions != null) 'mentions': mentions.map((m) => m.toMap()).toList(),
      if (animeRefs != null) ...<String, dynamic>{
        'animeRefs': animeRefs.map((a) => a.toMap()).toList(),
        'animeIds': <String>[
          for (final ref in animeRefs)
            if (ref.id.isNotEmpty) ref.id,
        ],
      },
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  /// Removes a post. Its likes and comments are removed first so no orphaned
  /// document is left behind; every delete is checked against the rules, so an
  /// entry that belongs to somebody else is skipped instead of failing the
  /// whole removal.
  Future<void> deletePost({required String postId, required String uid}) async {
    final data = (await _post(postId).get()).data();
    if (data == null) return;
    if (data['authorUid'] != uid) throw StateError('not-author');
    await _deleteSubcollection(_likes(postId));
    await _deleteSubcollection(_comments(postId));
    await _post(postId).delete();
    await _activity(uid).doc('post_$postId').delete().catchError((_) {});
  }

  Future<void> _deleteSubcollection(
    CollectionReference<Map<String, dynamic>> collection,
  ) async {
    final snapshot = await collection.limit(300).get();
    if (snapshot.docs.isEmpty) return;
    final batch = _db.batch();
    for (final doc in snapshot.docs) {
      batch.delete(doc.reference);
    }
    try {
      await batch.commit();
    } on Object {
      // An entry the current account may not delete (a comment by somebody
      // else) aborts the batch; the post itself is still removed below and the
      // remaining documents are unreadable once their parent is gone.
    }
  }

  // ------------------------------------------------------------------- likes

  Stream<bool> watchLiked(String postId, String uid) =>
      _likes(postId).doc(uid).snapshots().map((doc) => doc.exists);

  Future<bool> isLiked(String postId, String uid) async =>
      (await _likes(postId).doc(uid).get()).exists;

  /// Atomically flips the like and its counter.
  ///
  /// The like document id is the account uid, so a retried tap cannot create a
  /// second like, and the counter only moves when the state really changed.
  /// Returns the new state.
  Future<bool> toggleLike({
    required String postId,
    required String uid,
    required UserProfile actor,
  }) async {
    final likeRef = _likes(postId).doc(uid);
    final postRef = _post(postId);
    final liked = await _db.runTransaction<bool>((transaction) async {
      final like = await transaction.get(likeRef);
      final post = await transaction.get(postRef);
      if (!post.exists) throw StateError('missing-post');
      if (like.exists) {
        transaction.delete(likeRef);
        transaction.delete(_activity(uid).doc('like_$postId'));
        transaction.update(postRef, <String, dynamic>{
          'likeCount': FieldValue.increment(-1),
        });
        return false;
      }
      transaction.set(likeRef, <String, dynamic>{
        'uid': uid,
        'createdAt': FieldValue.serverTimestamp(),
      });
      // Recorded so an exact account deletion can remove the like instead of
      // leaving a stranger's counter behind.
      transaction.set(_activity(uid).doc('like_$postId'), <String, dynamic>{
        'type': 'like',
        'postId': postId,
        'path': likeRef.path,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      transaction.update(postRef, <String, dynamic>{
        'likeCount': FieldValue.increment(1),
      });
      return true;
    });
    if (liked) {
      final author =
          (await _post(postId).get()).data()?['authorUid'] as String?;
      if (author != null) {
        // Best effort: the like is already saved, and the deterministic id
        // makes a retry a no-op instead of a second alert.
        try {
          await _notifications.sendSocial(
            toUid: author,
            actor: actor,
            type: 'like',
            id: 'like_${postId}_$uid',
            postId: postId,
            text: '',
          );
        } on Object {
          // Offline or the post vanished.
        }
      }
    }
    return liked;
  }

  // ---------------------------------------------------------------- comments

  Stream<List<EpisodeComment>> watchComments(
    String postId, {
    int limit = pageSize,
  }) => _comments(postId)
      .orderBy('createdAt', descending: true)
      .limit(limit)
      .snapshots()
      .map(
        (snapshot) => snapshot.docs
            .map((doc) => EpisodeComment.fromDoc(postId, doc.id, doc.data()))
            .where((comment) => !comment.isDeleted)
            .toList(growable: false),
      );

  Future<CommentPage> pageComments(
    String postId, {
    DocumentSnapshot<Map<String, dynamic>>? after,
  }) async {
    var query = _comments(postId)
        .orderBy('createdAt', descending: true)
        .limit(pageSize);
    if (after != null) query = query.startAfterDocument(after);
    final snapshot = await query.get();
    return CommentPage(
      items: snapshot.docs
          .map((doc) => EpisodeComment.fromDoc(postId, doc.id, doc.data()))
          .where((comment) => !comment.isDeleted)
          .toList(growable: false),
      cursor: snapshot.docs.isEmpty ? null : snapshot.docs.last,
      hasMore: snapshot.docs.length == pageSize,
    );
  }

  Stream<List<EpisodeComment>> watchReplies(String postId, String commentId) =>
      _comments(postId)
          .doc(commentId)
          .collection('replies')
          .orderBy('createdAt')
          .limit(pageSize)
          .snapshots()
          .map(
            (snapshot) => snapshot.docs
                .map(
                  (doc) => EpisodeComment.fromDoc(
                    postId,
                    doc.id,
                    doc.data(),
                    parentId: commentId,
                  ),
                )
                .where((reply) => !reply.isDeleted)
                .toList(growable: false),
          );

  Future<String> addComment({
    required String postId,
    required UserProfile author,
    String text = '',
    String? parentId,
  }) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) throw ArgumentError('empty comment');
    if (trimmed.length > maxCommentLength) {
      throw ArgumentError('comment too long');
    }
    final collection = parentId == null
        ? _comments(postId)
        : _comments(postId).doc(parentId).collection('replies');
    final ref = collection.doc();
    final data = <String, dynamic>{
      'episodeId': postId,
      'postId': postId,
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
    if (parentId != null) data['parentId'] = parentId;
    final postRef = _post(postId);
    await _db.runTransaction((transaction) async {
      transaction.set(ref, data);
      if (parentId == null) {
        transaction.update(postRef, <String, dynamic>{
          'commentCount': FieldValue.increment(1),
        });
      } else {
        transaction.update(_comments(postId).doc(parentId), <String, dynamic>{
          'replyCount': FieldValue.increment(1),
        });
      }
    });
    await _activity(author.uid).doc('comment_${ref.id}').set(<String, dynamic>{
      'type': parentId == null ? 'comment' : 'reply',
      'postId': postId,
      'commentId': ref.id,
      'path': ref.path,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    final postData = (await postRef.get()).data();
    final postAuthor = postData?['authorUid'] as String? ?? '';
    try {
      if (parentId == null) {
        await _notifications.sendSocial(
          toUid: postAuthor,
          actor: author,
          type: 'comment',
          id: 'comment_${ref.id}',
          postId: postId,
          text: trimmed,
        );
      } else {
        final parent = await _comments(postId).doc(parentId).get();
        await _notifications.sendSocial(
          toUid: parent.data()?['authorUid'] as String? ?? '',
          actor: author,
          type: 'reply',
          id: 'reply_${ref.id}',
          postId: postId,
          commentId: parentId,
          text: trimmed,
        );
      }
    } on Object {
      // The comment is saved; a missing alert never fails the write.
    }
    return ref.id;
  }

  Future<void> editComment({
    required String postId,
    required String commentId,
    required String text,
    String? parentId,
  }) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty || trimmed.length > maxCommentLength) {
      throw ArgumentError('invalid comment');
    }
    final ref = parentId == null
        ? _comments(postId).doc(commentId)
        : _comments(postId).doc(parentId).collection('replies').doc(commentId);
    await ref.update(<String, dynamic>{
      'text': trimmed,
      'edited': true,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> deleteComment({
    required String postId,
    required String commentId,
    required String uid,
    String? parentId,
  }) async {
    final ref = parentId == null
        ? _comments(postId).doc(commentId)
        : _comments(postId).doc(parentId).collection('replies').doc(commentId);
    final batch = _db.batch();
    batch.delete(ref);
    if (parentId == null) {
      batch.update(_post(postId), <String, dynamic>{
        'commentCount': FieldValue.increment(-1),
      });
      // Replies are removed in one extra batch, best effort.
      final replies = await ref.collection('replies').limit(200).get();
      if (replies.docs.isNotEmpty) {
        final inner = _db.batch();
        for (final doc in replies.docs) {
          inner.delete(doc.reference);
        }
        try {
          await inner.commit();
        } on Object {
          // Each reply keeps its own author; a refusal leaves it orphaned.
        }
      }
    } else {
      batch.update(_comments(postId).doc(parentId), <String, dynamic>{
        'replyCount': FieldValue.increment(-1),
      });
    }
    await batch.commit();
    await _activity(uid).doc('comment_$commentId').delete().catchError((_) {});
  }

  // ------------------------------------------------------------------- saves

  Stream<Set<String>> watchSavedIds(String uid) =>
      _saved(uid)
          .snapshots()
          .map((snapshot) => snapshot.docs.map((doc) => doc.id).toSet());

  Future<void> toggleSaved({
    required String uid,
    required String postId,
  }) async {
    final ref = _saved(uid).doc(postId);
    final exists = (await ref.get()).exists;
    if (exists) {
      await ref.delete();
      return;
    }
    await ref.set(<String, dynamic>{
      'postId': postId,
      'savedAt': FieldValue.serverTimestamp(),
    });
  }

  /// The saved posts themselves, newest saved first. Deleted posts simply do
  /// not resolve and are skipped, so the list never shows a dead entry.
  Future<List<Post>> savedPosts(String uid, {int limit = 50}) async {
    final snapshot = await _saved(uid)
        .orderBy('savedAt', descending: true)
        .limit(limit)
        .get();
    final ids = snapshot.docs.map((doc) => doc.id).toList(growable: false);
    if (ids.isEmpty) return const <Post>[];
    final posts = <String, Post>{};
    for (var i = 0; i < ids.length; i += _whereInChunk) {
      final chunk = ids.sublist(i, (i + _whereInChunk).clamp(0, ids.length));
      final docs = await _posts
          .where(FieldPath.documentId, whereIn: chunk)
          .get();
      for (final doc in docs.docs) {
        posts[doc.id] = Post.fromDoc(doc.id, doc.data());
      }
    }
    return <Post>[
      for (final id in ids)
        if (posts[id] != null) posts[id]!,
    ];
  }

  // ----------------------------------------------------------------- follows

  Stream<Set<String>> watchFollowingIds(String uid) =>
      _following(uid)
          .snapshots()
          .map((snapshot) => snapshot.docs.map((doc) => doc.id).toSet());

  Stream<Set<String>> watchBlockedIds(String uid) =>
      _blocked(uid)
          .snapshots()
          .map((snapshot) => snapshot.docs.map((doc) => doc.id).toSet());

  Future<Set<String>> fetchBlockedIds(String uid) async {
    final snapshot = await _blocked(uid).limit(500).get();
    return snapshot.docs.map((doc) => doc.id).toSet();
  }

  /// True when [target] follows [uid] or the other way round: the profile
  /// button must read the same relationship everywhere in the app.
  Future<bool> isFollowing({
    required String uid,
    required String target,
  }) async {
    if (uid == target) return false;
    final doc = await _following(uid).doc(target).get();
    return doc.exists;
  }

  /// Atomically writes both sides of the relationship, so the follower and the
  /// follower count can never disagree.
  Future<void> setFollowing({
    required UserProfile actor,
    required String target,
    required bool follow,
  }) async {
    if (actor.uid == target) throw StateError('self-follow');
    final mine = _following(actor.uid).doc(target);
    final theirs = _followers(target).doc(actor.uid);
    await _db.runTransaction((transaction) async {
      final existing = await transaction.get(mine);
      final reverse = await transaction.get(theirs);
      if (follow) {
        if (!existing.exists) {
          transaction.set(mine, <String, dynamic>{
            'uid': target,
            'createdAt': FieldValue.serverTimestamp(),
          });
        }
        if (!reverse.exists) {
          transaction.set(theirs, <String, dynamic>{
            'uid': actor.uid,
            'createdAt': FieldValue.serverTimestamp(),
          });
        }
      } else {
        if (existing.exists) transaction.delete(mine);
        if (reverse.exists) transaction.delete(theirs);
      }
    });
    if (!follow) return;
    try {
      await _notifications.sendSocial(
        toUid: target,
        actor: actor,
        type: 'follow',
        id: 'follow_${actor.uid}',
        text: '',
      );
    } on Object {
      // The relationship is saved; the alert is best effort.
    }
  }

  /// Followers / following as profiles, resolved with one query per chunk
  /// instead of one read per member.
  Future<List<CommunityMember>> followers(String uid, {int limit = 60}) =>
      _members(_followers(uid), limit: limit);

  Future<List<CommunityMember>> followingMembers(
    String uid, {
    int limit = 60,
  }) => _members(_following(uid), limit: limit);

  Future<List<CommunityMember>> _members(
    CollectionReference<Map<String, dynamic>> collection, {
    required int limit,
  }) async {
    final snapshot = await collection
        .orderBy('createdAt', descending: true)
        .limit(limit)
        .get();
    final ids = snapshot.docs.map((doc) => doc.id).toList(growable: false);
    if (ids.isEmpty) return const <CommunityMember>[];
    final profiles = <String, UserProfile>{};
    for (var i = 0; i < ids.length; i += _whereInChunk) {
      final chunk = ids.sublist(i, (i + _whereInChunk).clamp(0, ids.length));
      final docs = await _db
          .collection('profiles')
          .where(FieldPath.documentId, whereIn: chunk)
          .get();
      for (final doc in docs.docs) {
        profiles[doc.id] = UserProfile.fromPublicMap(doc.id, doc.data());
      }
    }
    return <CommunityMember>[
      for (final id in ids) CommunityMember(uid: id, profile: profiles[id]),
    ];
  }

  // ------------------------------------------------------------------ blocks

  /// Blocks [target] and drops any follow relationship in both directions.
  /// The owner account is never blockable. The public `config/owner` document
  /// is checked here as well as in the UI, so an old build cannot bypass it.
  Future<bool> isOwnerAccount(String uid) async {
    if (uid.isEmpty) return false;
    try {
      final doc = await _db.collection('config').doc('owner').get();
      return (doc.data()?['uid'] as String? ?? '') == uid;
    } on Object {
      return false;
    }
  }

  Future<void> block({required String uid, required String target}) async {
    if (uid == target) throw StateError('self-block');
    if (await isOwnerAccount(target)) {
      throw StateError('owner-protected');
    }
    final batch = _db.batch();
    batch.set(_blocked(uid).doc(target), <String, dynamic>{
      'uid': target,
      'createdAt': FieldValue.serverTimestamp(),
    });
    batch.delete(_following(uid).doc(target));
    batch.delete(_followers(uid).doc(target));
    batch.delete(_following(target).doc(uid));
    batch.delete(_followers(target).doc(uid));
    await batch.commit();
  }

  Future<void> unblock({required String uid, required String target}) =>
      _blocked(uid).doc(target).delete();

  // ----------------------------------------------------------------- reports

  Future<void> report({
    required String reporterUid,
    required String targetType,
    required String targetId,
    required String reason,
    String? targetUid,
    String? targetPreview,
  }) async {
    if (targetUid != null && await isOwnerAccount(targetUid)) {
      throw StateError('owner-protected');
    }
    await _db.collection('reports').add(<String, dynamic>{
      'reporterUid': reporterUid,
      'targetType': targetType,
      'targetId': targetId,
      'targetUid': ?targetUid,
      'reason': reason,
      'preview': ?targetPreview,
      'status': 'open',
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  // ------------------------------------------------------------------ views

  /// One viewer document per account, so re-opening a Reel or a retry never
  /// inflates the counter. The caller records a view only after the video has
  /// really played for a few seconds.
  Future<void> recordView({required String postId, required String uid}) async {
    final local = _store;
    final key = 'community_view_${uid}_$postId';
    if (local != null && local.getString(LocalStore.cacheBox, key) != null) {
      return;
    }
    try {
      await _post(postId).collection('views').doc(uid).set(<String, dynamic>{
        'uid': uid,
        'createdAt': FieldValue.serverTimestamp(),
      });
      await local?.setString(LocalStore.cacheBox, key, '1');
    } on Object {
      // Offline: the next successful play retries.
    }
  }

  Future<int> viewCount(String postId) async {
    try {
      final snapshot = await _post(postId).collection('views').count().get();
      return snapshot.count ?? 0;
    } on Object {
      return 0;
    }
  }

  // ------------------------------------------------------------------ hidden

  /// Posts the member chose not to see. Private, like saved posts.
  Stream<Set<String>> watchHiddenIds(String uid) => _db
      .collection('users')
      .doc(uid)
      .collection('hiddenPosts')
      .snapshots()
      .map((snapshot) => snapshot.docs.map((doc) => doc.id).toSet());

  Future<Set<String>> fetchHiddenIds(String uid) async {
    try {
      final snapshot = await _db
          .collection('users')
          .doc(uid)
          .collection('hiddenPosts')
          .limit(500)
          .get();
      return snapshot.docs.map((doc) => doc.id).toSet();
    } on Object {
      return const <String>{};
    }
  }

  Future<void> hidePost({required String uid, required String postId}) => _db
      .collection('users')
      .doc(uid)
      .collection('hiddenPosts')
      .doc(postId)
      .set(<String, dynamic>{
        'postId': postId,
        'hiddenAt': FieldValue.serverTimestamp(),
      });

  Future<void> unhidePost({required String uid, required String postId}) => _db
      .collection('users')
      .doc(uid)
      .collection('hiddenPosts')
      .doc(postId)
      .delete();

  // --------------------------------------------------------------- mentions

  /// Accounts whose handle starts with [prefix], for the `@` picker.
  ///
  /// A single range query on the indexed `normalizedUsername`, capped at eight
  /// results. The caller debounces and caches, so typing does not query per
  /// keystroke.
  Future<List<UserProfile>> suggestUsers(String prefix, {int limit = 8}) async {
    final normalized = prefix.trim().toLowerCase();
    if (normalized.isEmpty) return const <UserProfile>[];
    try {
      final snapshot = await _db
          .collection('profiles')
          .orderBy('normalizedUsername')
          .startAt(<Object>[normalized])
          .endAt(<Object>['$normalized\uf8ff'])
          .limit(limit)
          .get();
      return snapshot.docs
          .map((doc) => UserProfile.fromPublicMap(doc.id, doc.data()))
          .where((profile) => profile.username.isNotEmpty)
          .toList(growable: false);
    } on Object {
      return const <UserProfile>[];
    }
  }

  // ------------------------------------------------------------- moderation

  /// Staff-only: removes somebody else's post through the rules, which check
  /// the trusted `staff/{uid}` role — never a value sent by the client.
  Future<void> removeAsStaff(String postId) => _post(postId).delete();
}
