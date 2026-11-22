import 'dart:async';

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
  bool _disposed = false;

  /// When the feed was last confirmed by the network. A tab switch must not
  /// re-send five catalogue requests; the manual refresh always bypasses this.
  DateTime? _lastNetworkAt;
  static const Duration _networkFloor = Duration(minutes: 2);

  /// Last successful feed, so a cold start paints real content on the first
  /// frame instead of holding a skeleton for as long as the network needs.
  static const String _cacheKey = 'home_feed_v1';

  @override
  Future<HomeFeed> build() async {
    _disposed = false;
    ref.onDispose(() => _disposed = true);
    final cached = _readCache();
    if (cached != null) {
      // The cached feed is shown at once; the network copy replaces it in the
      // background as soon as it arrives.
      unawaited(_refreshFromNetwork());
      return cached;
    }
    return _fetch();
  }

  Future<void> _refreshFromNetwork() async {
    final last = _lastNetworkAt;
    if (last != null && DateTime.now().difference(last) < _networkFloor) {
      return;
    }
    _lastNetworkAt = DateTime.now();
    try {
      final fresh = await _fetch();
      if (_disposed) return;
      state = AsyncData(fresh);
    } on Object {
      // Keep the cached feed when the catalogue is unreachable.
    }
  }

  HomeFeed? _readCache() {
    try {
      final raw = ref
          .read(localStoreProvider)
          .readCache(_cacheKey, allowStale: true);
      if (raw is! Map) return null;
      return _feedFromJson(raw.cast<String, dynamic>());
    } on Object {
      return null;
    }
  }

  void _writeCache(HomeFeed feed) {
    try {
      unawaited(
        ref
            .read(localStoreProvider)
            .putCache(
              _cacheKey,
              _feedToJson(feed),
              ttl: const Duration(minutes: 15),
            ),
      );
    } on Object {
      // A cache write never blocks the feed.
    }
  }

  Future<HomeFeed> _fetch() async {
    final repository = ref.read(animeRepositoryProvider);
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

    final feed = HomeFeed(
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
    _writeCache(feed);
    return feed;
  }

  Future<void> refresh() async {
    final previous = state;
    _lastNetworkAt = DateTime.now();
    final result = await AsyncValue.guard(_fetch);
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

Map<String, dynamic> _feedToJson(HomeFeed feed) => <String, dynamic>{
  'latest': <Map<String, dynamic>>[
    for (final item in feed.latest)
      <String, dynamic>{
        'anime': item.anime.toJson(),
        'episode': item.episode.toJson(),
        if (item.releasedAt != null)
          'releasedAt': item.releasedAt!.toIso8601String(),
      },
  ],
  'recentlyAdded': feed.recentlyAdded.map((anime) => anime.toJson()).toList(),
  'popular': feed.popular.map((anime) => anime.toJson()).toList(),
  'recommended': feed.recommended.map((anime) => anime.toJson()).toList(),
  'hasMore': feed.latestHasMore,
  'page': feed.latestPage,
};

HomeFeed? _feedFromJson(Map<String, dynamic> raw) {
  List<Anime> readAnime(Object? value) {
    if (value is! List) return const <Anime>[];
    return value
        .whereType<Map>()
        .map((item) => Anime.fromJson(item.cast<String, dynamic>()))
        .where((anime) => anime.id.isNotEmpty)
        .toList(growable: false);
  }

  final latest = <LatestEpisode>[];
  final rawLatest = raw['latest'];
  if (rawLatest is List) {
    for (final item in rawLatest.whereType<Map>()) {
      final map = item.cast<String, dynamic>();
      final anime = map['anime'];
      final episode = map['episode'];
      if (anime is! Map || episode is! Map) continue;
      latest.add(
        LatestEpisode(
          anime: Anime.fromJson(anime.cast<String, dynamic>()),
          episode: AnimeEpisode.fromJson(episode.cast<String, dynamic>()),
          releasedAt: map['releasedAt'] is String
              ? DateTime.tryParse(map['releasedAt'] as String)
              : null,
        ),
      );
    }
  }

  final recentlyAdded = readAnime(raw['recentlyAdded']);
  final popular = readAnime(raw['popular']);
  final recommended = readAnime(raw['recommended']);
  if (recentlyAdded.isEmpty && latest.isEmpty && popular.isEmpty) return null;
  final featured = recentlyAdded.isNotEmpty
      ? recentlyAdded.first
      : (latest.isNotEmpty ? latest.first.anime : null);
  AnimeEpisode? featuredEpisode;
  for (final item in latest) {
    if (item.anime.id == featured?.id) {
      featuredEpisode = item.episode;
      break;
    }
  }
  return HomeFeed(
    featured: featured,
    featuredEpisode: featuredEpisode,
    latest: latest,
    recentlyAdded: recentlyAdded,
    popular: popular,
    recommended: recommended,
    latestHasMore: raw['hasMore'] == true,
    latestPage: (raw['page'] as num?)?.toInt() ?? 0,
  );
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
