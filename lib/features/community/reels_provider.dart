import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/community.dart';
import 'community_providers.dart';
import 'community_ranking.dart';

/// The candidate pool one Reels session reads.
///
/// Two small pages are enough to personalise the first minutes; further pages
/// are fetched only when the viewer approaches the end, so opening Reels costs
/// a couple of reads rather than the whole collection.
class ReelsState {
  const ReelsState({
    this.posts = const <Post>[],
    this.loading = false,
    this.loaded = false,
    this.loadingMore = false,
    this.hasMore = false,
    this.error,
  });

  final List<Post> posts;
  final bool loading;
  final bool loaded;
  final bool loadingMore;
  final bool hasMore;
  final Object? error;

  ReelsState copyWith({
    List<Post>? posts,
    bool? loading,
    bool? loaded,
    bool? loadingMore,
    bool? hasMore,
    Object? error,
    bool clearError = false,
  }) => ReelsState(
    posts: posts ?? this.posts,
    loading: loading ?? this.loading,
    loaded: loaded ?? this.loaded,
    loadingMore: loadingMore ?? this.loadingMore,
    hasMore: hasMore ?? this.hasMore,
    error: clearError ? null : (error ?? this.error),
  );
}

class ReelsController extends Notifier<ReelsState> {
  DateTime? _cursor;
  bool _busy = false;

  @override
  ReelsState build() {
    Future<void>.microtask(() => load(refresh: true));
    return const ReelsState(loading: true);
  }

  Future<void> load({bool refresh = false}) async {
    if (_busy) return;
    _busy = true;
    state = state.copyWith(loading: state.posts.isEmpty, clearError: true);
    try {
      final repo = ref.read(communityRepositoryProvider);
      final first = await repo.reels();
      var candidates = <Post>[...first.items];
      if (first.hasMore) {
        // A second page gives the ranking something to choose from and still
        // costs two bounded queries.
        final second = await repo.reels(after: _createdAt(first.cursor));
        candidates = <Post>[...candidates, ...second.items];
        _cursor = _createdAt(second.cursor);
      } else {
        _cursor = _createdAt(first.cursor);
      }
      state = ReelsState(
        posts: _rank(candidates),
        loaded: true,
        hasMore: first.hasMore,
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
      final page = await ref
          .read(communityRepositoryProvider)
          .reels(after: cursor);
      _cursor = _createdAt(page.cursor);
      final seen = state.posts.map((post) => post.id).toSet();
      final ranked = _rank(page.items);
      state = state.copyWith(
        posts: <Post>[
          ...state.posts,
          for (final post in ranked)
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

  /// Re-orders the whole pool after the viewer's signals change (a like, a new
  /// watch) without another read.
  void rerank() {
    if (state.posts.isEmpty) return;
    state = state.copyWith(posts: _rank(state.posts));
  }

  List<Post> _rank(List<Post> posts) {
    final signals = ref.read(feedSignalsProvider).withNow(DateTime.now());
    return CommunityRanking.rank(posts, signals);
  }

  DateTime? _createdAt(DocumentSnapshot<Map<String, dynamic>>? cursor) {
    final value = cursor?.data()?['createdAt'];
    return value is Timestamp ? value.toDate() : null;
  }
}

final reelsProvider = NotifierProvider<ReelsController, ReelsState>(
  ReelsController.new,
);
