import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../data/models/anime.dart';
import '../../data/models/library.dart';

class HomeFeed {
  const HomeFeed({
    required this.featured,
    required this.latest,
    required this.recentlyAdded,
    required this.popular,
    required this.recommended,
    this.featuredEpisode,
    this.latestHasMore = false,
    this.latestPage = 0,
  });

  final Anime? featured;
  final AnimeEpisode? featuredEpisode;
  final List<LatestEpisode> latest;
  final List<Anime> recentlyAdded;
  final List<Anime> popular;
  final List<Anime> recommended;
  final bool latestHasMore;
  final int latestPage;

  HomeFeed copyWith({
    List<LatestEpisode>? latest,
    bool? latestHasMore,
    int? latestPage,
  }) {
    return HomeFeed(
      featured: featured,
      featuredEpisode: featuredEpisode,
      latest: latest ?? this.latest,
      recentlyAdded: recentlyAdded,
      popular: popular,
      recommended: recommended,
      latestHasMore: latestHasMore ?? this.latestHasMore,
      latestPage: latestPage ?? this.latestPage,
    );
  }
}

class HomeFeedController extends AsyncNotifier<HomeFeed> {
  bool _loadingMore = false;

  @override
  Future<HomeFeed> build() async {
    final repository = ref.watch(animeRepositoryProvider);
    final favorites = ref.read(libraryProvider).favorites;

    final results = await Future.wait<Object>(<Future<Object>>[
      repository.browse(const BrowseQuery(sort: BrowseSort.newest)),
      repository.latest(),
      repository.browse(const BrowseQuery(sort: BrowseSort.popular)),
      if (favorites.isNotEmpty && favorites.first.anime.genres.isNotEmpty)
        repository.browse(
          BrowseQuery(
            sort: BrowseSort.rating,
            genre: favorites.first.anime.genres.first,
          ),
        )
      else
        repository.browse(const BrowseQuery(sort: BrowseSort.rating)),
    ]);

    final newest = results[0] as Paged<Anime>;
    final latest = results[1] as Paged<LatestEpisode>;
    final popular = results[2] as Paged<Anime>;
    final recommended = results[3] as Paged<Anime>;

    final featured = newest.items.isNotEmpty
        ? newest.items.first
        : (latest.items.isNotEmpty ? latest.items.first.anime : null);

    AnimeEpisode? featuredEpisode;
    if (featured != null) {
      for (final item in latest.items) {
        if (item.anime.id == featured.id) {
          featuredEpisode = item.episode;
          break;
        }
      }
      if (featuredEpisode == null) {
        try {
          final episodes = await repository.episodes(featured);
          if (episodes.isNotEmpty) featuredEpisode = episodes.first;
        } on Object {
          // The banner still works as a details entry point.
        }
      }
    }

    return HomeFeed(
      featured: featured,
      featuredEpisode: featuredEpisode,
      latest: latest.items,
      recentlyAdded: newest.items.take(14).toList(growable: false),
      popular: popular.items.take(14).toList(growable: false),
      recommended: recommended.items
          .where((anime) => anime.id != featured?.id)
          .take(14)
          .toList(growable: false),
      latestHasMore: latest.hasMore,
      latestPage: latest.page,
    );
  }

  Future<void> refresh() async {
    final previous = state;
    final result = await AsyncValue.guard(build);
    if (result.hasValue) {
      state = result;
    } else if (!previous.hasValue) {
      state = result;
    }
  }

  Future<void> loadMoreLatest() async {
    final current = state.value;
    if (current == null || _loadingMore || !current.latestHasMore) return;
    _loadingMore = true;
    try {
      final next = await ref
          .read(animeRepositoryProvider)
          .latest(page: current.latestPage + 1);
      state = AsyncData(
        current.copyWith(
          latest: <LatestEpisode>[...current.latest, ...next.items],
          latestHasMore: next.hasMore,
          latestPage: next.page,
        ),
      );
    } on Object {
      // Keep loaded content; the load-more affordance stays available.
    } finally {
      _loadingMore = false;
    }
  }
}

final homeFeedProvider = AsyncNotifierProvider<HomeFeedController, HomeFeed>(
  HomeFeedController.new,
);

/// Distinct recently watched titles for the continue-watching rail.
final continueWatchingProvider = Provider<List<WatchHistoryEntry>>((ref) {
  final history = ref.watch(libraryProvider).history;
  final seen = <String>{};
  final result = <WatchHistoryEntry>[];
  for (final entry in history) {
    if (seen.add(entry.animeId)) result.add(entry);
    if (result.length >= 10) break;
  }
  return result;
});
