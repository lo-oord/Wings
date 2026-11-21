import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../data/models/community.dart';
import '../../core/storage/local_store.dart';
import '../../data/models/social.dart';
import '../../data/repositories/community_repository.dart';
import 'community_ranking.dart';

export '../../app/providers.dart'
    show communityMediaProvider, communityRepositoryProvider;

/// The three ways to read the same `posts` collection.
///
/// `forYou` is ordered on the device from a bounded page of candidates, so it
/// costs exactly the reads of a chronological page. `latest` keeps a plain
/// newest-first order available, clearly labelled, and `following` shows only
/// the accounts the member follows.
enum CommunityTab { forYou, latest, following }

class CommunityFeedState {
  const CommunityFeedState({
    this.posts = const <Post>[],
    this.loading = false,
    this.refreshing = false,
    this.loadingMore = false,
    this.loaded = false,
    this.hasMore = false,
    this.error,
  });

  final List<Post> posts;

  /// First load of an empty tab.
  final bool loading;

  /// A pull-to-refresh on top of content that is already on screen.
  final bool refreshing;

  final bool loadingMore;
  final bool loaded;
  final bool hasMore;
  final Object? error;

  bool get isEmpty => loaded && posts.isEmpty;

  CommunityFeedState copyWith({
    List<Post>? posts,
    bool? loading,
    bool? refreshing,
    bool? loadingMore,
    bool? loaded,
    bool? hasMore,
    Object? error,
    bool clearError = false,
  }) => CommunityFeedState(
    posts: posts ?? this.posts,
    loading: loading ?? this.loading,
    refreshing: refreshing ?? this.refreshing,
    loadingMore: loadingMore ?? this.loadingMore,
    loaded: loaded ?? this.loaded,
    hasMore: hasMore ?? this.hasMore,
    error: clearError ? null : (error ?? this.error),
  );
}

/// One tab of the feed.
///
/// The controller is kept alive for the whole session so switching tabs or
/// opening a post never reloads the list from Firestore, and it deduplicates
/// by document id so a refresh that overlaps a page can never show the same
/// post twice.
class CommunityFeedController extends Notifier<CommunityFeedState> {
  CommunityFeedController(this.tab);

  final CommunityTab tab;

  DateTime? _cursor;
  Set<String> _blocked = const <String>{};
  Set<String> _hidden = const <String>{};
  bool _busy = false;
  String? _uid;

  CommunityRepository get _repo => ref.read(communityRepositoryProvider);

  @override
  CommunityFeedState build() {
    Future<void>.microtask(() => load(refresh: true));
    return const CommunityFeedState(loading: true);
  }

  Future<void> load({bool refresh = false}) async {
    if (_busy) return;
    _busy = true;
    final hasContent = state.posts.isNotEmpty;
    state = state.copyWith(
      loading: !hasContent,
      refreshing: hasContent && refresh,
      clearError: true,
    );
    try {
      _uid = ref.read(authProvider)?.id;
      _blocked = _uid == null
          ? const <String>{}
          : await _repo.fetchBlockedIds(_uid!);
      _hidden = _uid == null
          ? const <String>{}
          : await _repo.fetchHiddenIds(_uid!);
      final authors = tab == CommunityTab.following && _uid != null
          ? await _followingIds(_uid!)
          : const <String>{};
      if (tab == CommunityTab.following && authors.isEmpty) {
        _cursor = null;
        state = const CommunityFeedState(loaded: true);
        return;
      }
      final page = tab == CommunityTab.forYou
          ? await _repo.latest()
          : tab == CommunityTab.latest
          ? await _repo.latest()
          : await _repo.following(authors);
      _cursor = _createdAt(page.cursor);
      var items = page.items;
      if (tab == CommunityTab.forYou && authors.isNotEmpty) {
        // Accounts the member follows are part of the candidate page but never
        // require a second, unbounded read: one extra page is enough.
        try {
          final followingPage = await _repo.following(authors);
          items = <Post>[...items, ...followingPage.items];
        } on Object {
          // The personal feed still works from the latest page.
        }
      }
      state = CommunityFeedState(
        posts: _order(items, forYou: tab == CommunityTab.forYou),
        loaded: true,
        hasMore: page.hasMore,
      );
    } on Object catch (error) {
      state = state.copyWith(
        loading: false,
        refreshing: false,
        loaded: true,
        error: error,
      );
    } finally {
      _busy = false;
    }
  }

  Future<void> loadMore() async {
    if (_busy || !state.hasMore || state.loadingMore) return;
    final cursor = _cursor;
    if (cursor == null) return;
    _busy = true;
    state = state.copyWith(loadingMore: true, clearError: true);
    try {
      final uid = _uid ?? ref.read(authProvider)?.id;
      final authors = tab == CommunityTab.following && uid != null
          ? await _followingIds(uid)
          : const <String>{};
      final page = tab == CommunityTab.following
          ? await _repo.following(authors, after: cursor)
          : await _repo.latest(after: cursor);
      _cursor = _createdAt(page.cursor);
      final seen = state.posts.map((post) => post.id).toSet();
      final extra = _order(page.items, forYou: tab == CommunityTab.forYou);
      state = state.copyWith(
        posts: <Post>[
          ...state.posts,
          for (final post in extra)
            if (seen.add(post.id)) post,
        ],
        loadingMore: false,
        hasMore: page.hasMore,
      );
    } on Object catch (error) {
      state = state.copyWith(loadingMore: false, error: error);
    } finally {
      _busy = false;
    }
  }

  /// A newly published post appears at the top immediately, before the next
  /// refresh reads it back from the server.
  void prepend(Post post) {
    if (!state.loaded) return;
    state = state.copyWith(
      posts: <Post>[
        post,
        for (final existing in state.posts)
          if (existing.id != post.id) existing,
      ],
    );
  }

  /// Keeps the visible list in step after an edit or a deletion.
  void replace(Post post) {
    state = state.copyWith(
      posts: <Post>[
        for (final existing in state.posts)
          existing.id == post.id ? post : existing,
      ],
    );
  }

  void remove(String postId) {
    state = state.copyWith(
      posts: state.posts
          .where((post) => post.id != postId)
          .toList(growable: false),
    );
  }

  Future<Set<String>> _followingIds(String uid) async {
    try {
      return await _repo.watchFollowingIds(uid).first;
    } on Object {
      return const <String>{};
    }
  }

  List<Post> _visible(List<Post> items) => items
      .where((post) => !post.isReel)
      .where((post) => !_blocked.contains(post.authorUid))
      .where((post) => !_hidden.contains(post.id))
      .toList(growable: false);

  /// Applies the personal ranking to a bounded page, or keeps the chronological
  /// order for the tab that promises it.
  List<Post> _order(List<Post> items, {required bool forYou}) {
    final visible = _visible(items);
    if (!forYou) return visible;
    final signals = ref.read(feedSignalsProvider).withNow(DateTime.now());
    return CommunityRanking.rank(visible, signals);
  }

  DateTime? _createdAt(DocumentSnapshot<Map<String, dynamic>>? cursor) {
    final value = cursor?.data()?['createdAt'];
    return value is Timestamp ? value.toDate() : null;
  }
}

final communityFeedProvider =
    NotifierProvider.family<
      CommunityFeedController,
      CommunityFeedState,
      CommunityTab
    >(CommunityFeedController.new);

// --------------------------------------------------------------- comments

class PostCommentsState {
  const PostCommentsState({
    this.comments = const <EpisodeComment>[],
    this.loading = false,
    this.loaded = false,
    this.sending = false,
    this.hasMore = false,
    this.error,
  });

  final List<EpisodeComment> comments;
  final bool loading;
  final bool loaded;
  final bool sending;
  final bool hasMore;
  final Object? error;

  PostCommentsState copyWith({
    List<EpisodeComment>? comments,
    bool? loading,
    bool? loaded,
    bool? sending,
    bool? hasMore,
    Object? error,
    bool clearError = false,
  }) => PostCommentsState(
    comments: comments ?? this.comments,
    loading: loading ?? this.loading,
    loaded: loaded ?? this.loaded,
    sending: sending ?? this.sending,
    hasMore: hasMore ?? this.hasMore,
    error: clearError ? null : (error ?? this.error),
  );
}

/// Comments of one post. The documents use the same shape as episode comments,
/// so there is one comment system in Wings, not two.
class PostCommentsController extends Notifier<PostCommentsState> {
  PostCommentsController(this.postId);

  final String postId;

  DocumentSnapshot<Map<String, dynamic>>? _cursor;
  bool _busy = false;

  CommunityRepository get _repo => ref.read(communityRepositoryProvider);

  @override
  PostCommentsState build() {
    Future<void>.microtask(load);
    return const PostCommentsState(loading: true);
  }

  Future<void> load() async {
    if (_busy) return;
    _busy = true;
    state = state.copyWith(loading: state.comments.isEmpty, clearError: true);
    try {
      final page = await _repo.pageComments(postId);
      _cursor = page.cursor;
      state = state.copyWith(
        comments: page.items,
        loading: false,
        loaded: true,
        hasMore: page.hasMore,
      );
    } on Object catch (error) {
      state = state.copyWith(loading: false, loaded: true, error: error);
    } finally {
      _busy = false;
    }
  }

  Future<void> loadMore() async {
    if (_busy || !state.hasMore) return;
    _busy = true;
    try {
      final page = await _repo.pageComments(postId, after: _cursor);
      _cursor = page.cursor;
      final seen = state.comments.map((comment) => comment.id).toSet();
      state = state.copyWith(
        comments: <EpisodeComment>[
          ...state.comments,
          for (final comment in page.items)
            if (seen.add(comment.id)) comment,
        ],
        hasMore: page.hasMore,
      );
    } on Object catch (error) {
      state = state.copyWith(error: error);
    } finally {
      _busy = false;
    }
  }

  Future<bool> add(
    String text, {
    String? parentId,
    List<MentionRef> mentions = const <MentionRef>[],
    List<AnimeRef> animeRefs = const <AnimeRef>[],
  }) async {
    final uid = ref.read(authProvider);
    final profile = ref.read(profileProvider);
    if (uid == null || profile == null) return false;
    final trimmed = text.trim();
    if (trimmed.isEmpty) return false;
    state = state.copyWith(sending: true, clearError: true);
    try {
      await _repo.addComment(
        postId: postId,
        author: profile,
        text: trimmed,
        parentId: parentId,
        mentions: mentions,
        animeRefs: animeRefs,
      );
      state = state.copyWith(sending: false);
      // The parent's reply count is rendered from a live stream, and the post
      // comment count comes from the post document, so only the list of root
      // comments has to be refreshed here.
      if (parentId == null) unawaited(load());
      return true;
    } on Object catch (error) {
      state = state.copyWith(sending: false, error: error);
      return false;
    }
  }

  Future<void> edit(EpisodeComment comment, String text) async {
    await _repo.editComment(
      postId: postId,
      commentId: comment.id,
      parentId: comment.parentId,
      text: text,
    );
    state = state.copyWith(
      comments: <EpisodeComment>[
        for (final item in state.comments)
          item.id == comment.id
              ? item.copyWith(text: text.trim(), edited: true)
              : item,
      ],
    );
  }

  Future<void> delete(EpisodeComment comment) async {
    final uid = ref.read(authProvider)?.id;
    if (uid == null) return;
    final wasRoot = comment.parentId == null;
    state = state.copyWith(
      comments: wasRoot
          ? state.comments
                .where((item) => item.id != comment.id)
                .toList(growable: false)
          : state.comments,
    );
    try {
      await _repo.deleteComment(
        postId: postId,
        commentId: comment.id,
        parentId: comment.parentId,
        uid: comment.authorUid,
      );
      if (!wasRoot) unawaited(load());
    } on Object catch (error) {
      state = state.copyWith(error: error);
      unawaited(load());
    }
  }
}

final postCommentsProvider =
    NotifierProvider.family<PostCommentsController, PostCommentsState, String>(
      PostCommentsController.new,
    );

/// Replies are only read when the reader opens the thread.
final postRepliesProvider = StreamProvider.autoDispose
    .family<List<EpisodeComment>, ({String postId, String commentId})>(
      (ref, key) => ref
          .watch(communityRepositoryProvider)
          .watchReplies(key.postId, key.commentId),
    );

final postProvider = StreamProvider.autoDispose.family<Post?, String>(
  (ref, postId) => ref.watch(communityRepositoryProvider).watchPost(postId),
);

// ------------------------------------------------------- relationships

final followingIdsProvider = StreamProvider.family<Set<String>, String>(
  (ref, uid) => ref.watch(communityRepositoryProvider).watchFollowingIds(uid),
);

final savedPostIdsProvider = StreamProvider.family<Set<String>, String>(
  (ref, uid) => ref.watch(communityRepositoryProvider).watchSavedIds(uid),
);

final blockedIdsProvider = StreamProvider.family<Set<String>, String>(
  (ref, uid) => ref.watch(communityRepositoryProvider).watchBlockedIds(uid),
);

/// Posts the member hid from their feeds. Private to the account.
final hiddenPostIdsProvider = StreamProvider.family<Set<String>, String>(
  (ref, uid) => ref.watch(communityRepositoryProvider).watchHiddenIds(uid),
);

/// Everything the personal feed and Reels ranking use, assembled from systems
/// that already exist: the follow graph, the library and watch history, the
/// moderation lists and the local view log. No extra collection, no profile
/// building job, no server round-trip.
final feedSignalsProvider = Provider<FeedSignals>((ref) {
  final uid = ref.watch(authProvider)?.id;
  final library = ref.watch(libraryProvider);
  final weights = <String, double>{};
  for (final entry in library.favorites) {
    weights[entry.anime.id] = 1;
  }
  for (final entry in library.entries) {
    weights.putIfAbsent(entry.anime.id, () => 0.75);
  }
  for (final watch in library.history) {
    weights.putIfAbsent(watch.animeId, () => 0.55);
  }
  return FeedSignals(
    following: uid == null
        ? const <String>{}
        : ref.watch(followingIdsProvider(uid)).value ?? const <String>{},
    blocked: uid == null
        ? const <String>{}
        : ref.watch(blockedIdsProvider(uid)).value ?? const <String>{},
    hidden: uid == null
        ? const <String>{}
        : ref.watch(hiddenPostIdsProvider(uid)).value ?? const <String>{},
    animeWeights: weights,
    viewedPosts: ref.watch(reelViewsProvider),
  );
});

final postLikedProvider =
    FutureProvider.family<bool, ({String postId, String uid})>(
      (ref, key) =>
          ref.watch(communityRepositoryProvider).isLiked(key.postId, key.uid),
    );

final communityCountsProvider = FutureProvider.autoDispose
    .family<CommunityCounts, String>(
      (ref, uid) => ref.watch(communityRepositoryProvider).counts(uid),
    );

class PostsPageState {
  const PostsPageState({
    this.posts = const <Post>[],
    this.loading = false,
    this.loadingMore = false,
    this.loaded = false,
    this.hasMore = false,
    this.error,
  });

  final List<Post> posts;
  final bool loading;
  final bool loadingMore;
  final bool loaded;
  final bool hasMore;
  final Object? error;

  PostsPageState copyWith({
    List<Post>? posts,
    bool? loading,
    bool? loadingMore,
    bool? loaded,
    bool? hasMore,
    Object? error,
    bool clearError = false,
  }) => PostsPageState(
    posts: posts ?? this.posts,
    loading: loading ?? this.loading,
    loadingMore: loadingMore ?? this.loadingMore,
    loaded: loaded ?? this.loaded,
    hasMore: hasMore ?? this.hasMore,
    error: clearError ? null : (error ?? this.error),
  );
}

/// Pages the posts of one account or one anime.
///
/// The same controller serves the public profile and the anime community feed,
/// so both get pagination, deduplication, hidden/blocked filtering and the same
/// deleted-post behaviour without a second implementation.
class PostsPageController extends Notifier<PostsPageState> {
  PostsPageController(this.key);

  /// `user:<uid>` or `anime:<id>`.
  final String key;

  DateTime? _cursor;
  bool _busy = false;

  CommunityRepository get _repo => ref.read(communityRepositoryProvider);

  @override
  PostsPageState build() {
    Future<void>.microtask(load);
    return const PostsPageState(loading: true);
  }

  Future<void> load() async {
    if (_busy) return;
    _busy = true;
    state = state.copyWith(loading: state.posts.isEmpty, clearError: true);
    try {
      final page = await _fetch();
      _cursor = _createdAt(page.cursor);
      state = state.copyWith(
        posts: _visible(page.items),
        loading: false,
        loaded: true,
        hasMore: page.hasMore,
      );
    } on Object catch (error) {
      state = state.copyWith(loading: false, loaded: true, error: error);
    } finally {
      _busy = false;
    }
  }

  Future<void> loadMore() async {
    if (_busy || !state.hasMore) return;
    final cursor = _cursor;
    if (cursor == null) return;
    _busy = true;
    state = state.copyWith(loadingMore: true, clearError: true);
    try {
      final page = await _fetch(after: cursor);
      _cursor = _createdAt(page.cursor);
      final seen = state.posts.map((post) => post.id).toSet();
      state = state.copyWith(
        posts: <Post>[
          ...state.posts,
          for (final post in _visible(page.items))
            if (seen.add(post.id)) post,
        ],
        loadingMore: false,
        hasMore: page.hasMore,
      );
    } on Object catch (error) {
      state = state.copyWith(loadingMore: false, error: error);
    } finally {
      _busy = false;
    }
  }

  /// Reacts to a like/edit on a card without reloading the page.
  void replace(Post post) {
    state = state.copyWith(
      posts: <Post>[
        for (final existing in state.posts)
          existing.id == post.id ? post : existing,
      ],
    );
  }

  void remove(String postId) {
    state = state.copyWith(
      posts: state.posts
          .where((post) => post.id != postId)
          .toList(growable: false),
    );
  }

  Future<PostPage> _fetch({DateTime? after}) {
    final id = key.substring(key.indexOf(':') + 1);
    return key.startsWith('anime:')
        ? _repo.byAnime(id, after: after)
        : _repo.postsBy(id, after: after);
  }

  List<Post> _visible(List<Post> items) {
    final visible = items.where((post) => !post.isReel).toList(growable: false);
    final uid = ref.read(authProvider)?.id;
    if (uid == null) return visible;
    final blocked = ref.read(blockedIdsProvider(uid)).value ?? const <String>{};
    final hidden =
        ref.read(hiddenPostIdsProvider(uid)).value ?? const <String>{};
    return visible
        .where((post) => !blocked.contains(post.authorUid))
        .where((post) => !hidden.contains(post.id))
        .toList(growable: false);
  }

  DateTime? _createdAt(DocumentSnapshot<Map<String, dynamic>>? cursor) {
    final value = cursor?.data()?['createdAt'];
    return value is Timestamp ? value.toDate() : null;
  }
}

final postsPageProvider =
    NotifierProvider.family<PostsPageController, PostsPageState, String>(
      PostsPageController.new,
    );

/// Reels already watched on this device, used to demote them in the next
/// session without writing anything to Firestore.
class ReelViewsController extends Notifier<Set<String>> {
  static const String _prefix = 'reel_view_';

  @override
  Set<String> build() {
    final store = ref.watch(localStoreProvider);
    final uid = ref.watch(authProvider)?.id ?? 'guest';
    final raw = store.getString(LocalStore.cacheBox, '$_prefix$uid');
    if (raw == null || raw.isEmpty) return const <String>{};
    return raw.split(',').where((id) => id.isNotEmpty).toSet();
  }

  Future<void> markViewed(String postId) async {
    if (state.contains(postId)) return;
    final next = <String>{...state, postId};
    // Bounded log: the 200 most recent watches are enough for ranking.
    final trimmed = next.length > 200
        ? next.skip(next.length - 200).toSet()
        : next;
    state = trimmed;
    final uid = ref.read(authProvider)?.id ?? 'guest';
    await ref
        .read(localStoreProvider)
        .setString(LocalStore.cacheBox, '$_prefix$uid', trimmed.join(','));
  }
}

final reelViewsProvider = NotifierProvider<ReelViewsController, Set<String>>(
  ReelViewsController.new,
);

final followersProvider = FutureProvider.autoDispose
    .family<List<CommunityMember>, String>(
      (ref, uid) => ref.watch(communityRepositoryProvider).followers(uid),
    );

final followingListProvider = FutureProvider.autoDispose
    .family<List<CommunityMember>, String>(
      (ref, uid) =>
          ref.watch(communityRepositoryProvider).followingMembers(uid),
    );

final savedPostsProvider = FutureProvider.autoDispose<List<Post>>((ref) async {
  final uid = ref.watch(authProvider)?.id;
  if (uid == null) return const <Post>[];
  // Rebuilds when the saved set changes, so unsaving a post removes it from
  // the list immediately.
  ref.watch(savedPostIdsProvider(uid));
  return ref.watch(communityRepositoryProvider).savedPosts(uid);
});
