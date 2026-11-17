import 'dart:math';

import 'package:dio/dio.dart';

import '../../core/errors/app_failure.dart';
import '../../core/storage/local_store.dart';
import '../../core/utils/title_series.dart';
import '../models/anime.dart';
import '../sources/anime_source.dart';
import '../sources/hls_variants.dart';
import '../sources/server_resolver.dart';

/// Application-facing catalogue API.
///
/// It owns caching, offline fallback and error translation, so screens never
/// know which catalogue implementation is in use.
class AnimeRepository {
  AnimeRepository(this._source, this._resolver, this._store);

  final AnimeSource _source;
  final ServerResolver _resolver;
  final LocalStore _store;
  final Map<String, _MemoryEntry<Object>> _memory =
      <String, _MemoryEntry<Object>>{};
  final Random _random = Random();

  static const Duration _cacheTtl = Duration(minutes: 15);
  static const Duration _detailsTtl = Duration(hours: 6);
  static const Duration _genresTtl = Duration(hours: 12);

  Future<Paged<LatestEpisode>> latest({
    int page = 0,
    CancelToken? cancelToken,
  }) async {
    const ttl = _cacheTtl;
    final key = 'latest:$page';
    try {
      final result = await _source.latestEpisodes(
        page: page,
        cancelToken: cancelToken,
      );
      await _store.putCache(
        key,
        result.items.map(_latestToJson).toList(),
        ttl: ttl,
      );
      return result;
    } on Object catch (error) {
      final cached = _cachedPaged<LatestEpisode>(key, _latestFromJson);
      if (cached != null) return cached;
      throw _failure(error);
    }
  }

  Future<Paged<Anime>> browse(
    BrowseQuery query, {
    int page = 0,
    CancelToken? cancelToken,
  }) async {
    final key = 'browse:${query.sort.name}:${query.genre ?? '-'}:$page';
    try {
      final result = await _source.browse(
        query,
        page: page,
        cancelToken: cancelToken,
      );
      await _store.putCache(
        key,
        result.items.map((a) => a.toJson()).toList(),
        ttl: _cacheTtl,
      );
      return result;
    } on Object catch (error) {
      final cached = _cachedPaged<Anime>(key, Anime.fromJson);
      if (cached != null) return cached;
      throw _failure(error);
    }
  }

  Future<Paged<Anime>> search(
    String text, {
    int page = 0,
    CancelToken? cancelToken,
  }) async {
    try {
      return await _source.search(text, page: page, cancelToken: cancelToken);
    } on Object catch (error) {
      throw _failure(error);
    }
  }

  Future<Anime> details(
    String id, {
    CancelToken? cancelToken,
    bool force = false,
  }) async {
    final memoryKey = 'details:$id';
    if (!force) {
      final memo = _memory[memoryKey];
      if (memo != null && !memo.isExpired) return memo.value as Anime;
    }
    try {
      final anime = await _source.animeById(id, cancelToken: cancelToken);
      _memory[memoryKey] = _MemoryEntry<Object>(anime, _detailsTtl);
      await _store.putCache(memoryKey, anime.toJson(), ttl: _detailsTtl);
      return anime;
    } on Object catch (error) {
      final cached = _store.readCache(memoryKey, allowStale: true);
      if (cached is Map) {
        final anime = Anime.fromJson(cached.cast<String, dynamic>());
        _memory[memoryKey] = _MemoryEntry<Object>(anime, _detailsTtl);
        return anime;
      }
      throw _failure(error);
    }
  }

  Future<List<AnimeEpisode>> episodes(
    Anime anime, {
    CancelToken? cancelToken,
  }) async {
    final key = 'episodes:${anime.id}';
    try {
      final list = await _source.episodes(anime, cancelToken: cancelToken);
      await _store.putCache(
        key,
        list.map((e) => e.toJson()).toList(),
        ttl: _cacheTtl,
      );
      return list;
    } on Object catch (error) {
      final cached = _store.readCache(key, allowStale: true);
      if (cached is List) {
        return cached
            .whereType<Map>()
            .map((json) => AnimeEpisode.fromJson(json.cast<String, dynamic>()))
            .toList(growable: false);
      }
      throw _failure(error);
    }
  }

  Future<List<StreamServer>> servers(
    Anime anime,
    AnimeEpisode episode, {
    CancelToken? cancelToken,
  }) async {
    try {
      final servers = await _source.servers(
        anime,
        episode,
        cancelToken: cancelToken,
      );
      return await _withQualities(servers);
    } on Object catch (error) {
      throw _failure(error);
    }
  }

  /// Turns a master HLS link into one entry per published quality.
  ///
  /// Sources usually hand out a single `.m3u8` address; without expanding its
  /// ladder the picker could only show the label the source wrote, and the
  /// viewer had no way to choose 1080p or 480p. A media playlist or a failed
  /// request keeps the original server untouched.
  Future<List<StreamServer>> _withQualities(List<StreamServer> servers) async {
    if (servers.isEmpty) return servers;
    // Only the first handful of direct links are probed: a source that lists
    // dozens of mirrors should not turn one tap into dozens of requests.
    var probes = 0;
    final groups = await Future.wait(
      servers.map((server) async {
        if (!server.isDirectFile || server.requiresBrowser) {
          return <StreamServer>[server];
        }
        if (probes >= 6) return <StreamServer>[server];
        probes++;
        final variants = await hlsVariants(server.url, headers: server.headers);
        if (variants.length < 2) return <StreamServer>[server];
        return <StreamServer>[
          for (final variant in variants)
            StreamServer(
              name: server.name,
              url: variant.url,
              quality: variant.quality,
              flavor: server.flavor,
              headers: server.headers,
              isDirectFile: true,
            ),
        ];
      }),
    );
    final expanded = <StreamServer>[for (final group in groups) ...group];
    expanded.sort((a, b) {
      final byQuality = b.qualityRank.compareTo(a.qualityRank);
      if (byQuality != 0) return byQuality;
      return a.name.compareTo(b.name);
    });
    return expanded;
  }

  Future<ResolvedStream?> resolve(StreamServer server) =>
      _resolver.resolve(server);

  /// Resolves servers in quality order until one plays.
  Future<ResolvedStream?> resolveFirstPlayable(
    List<StreamServer> servers, {
    String? preferredQuality,
  }) async {
    final candidates = servers.where((s) => !s.requiresBrowser).toList();
    if (preferredQuality != null) {
      candidates.sort((a, b) {
        final aPreferred = a.quality == preferredQuality ? 0 : 1;
        final bPreferred = b.quality == preferredQuality ? 0 : 1;
        if (aPreferred != bPreferred) return aPreferred.compareTo(bPreferred);
        return b.qualityRank.compareTo(a.qualityRank);
      });
    }
    for (final candidate in candidates) {
      final resolved = await _resolver.resolve(candidate);
      if (resolved != null) return resolved;
    }
    return null;
  }

  Future<List<Genre>> genres() async {
    final memo = _memory['genres'];
    if (memo != null && !memo.isExpired) return memo.value as List<Genre>;
    final cached = _store.readCache('genres');
    if (cached is List && cached.isNotEmpty) {
      final genres = cached
          .whereType<Map>()
          .map(
            (json) => Genre(
              name: json['name']?.toString() ?? '',
              count: (json['count'] as num?)?.toInt(),
            ),
          )
          .where((g) => g.name.isNotEmpty)
          .toList(growable: false);
      if (genres.isNotEmpty) {
        _memory['genres'] = _MemoryEntry<Object>(genres, _genresTtl);
        return genres;
      }
    }
    try {
      final genres = await _source.genres();
      _memory['genres'] = _MemoryEntry<Object>(genres, _genresTtl);
      await _store.putCache(
        'genres',
        genres
            .map((g) => <String, dynamic>{'name': g.name, 'count': g.count})
            .toList(),
        ttl: _genresTtl,
      );
      return genres;
    } on Object catch (error) {
      throw _failure(error);
    }
  }

  /// Titles that share the source's own "related" links, then titles that
  /// actually share genres with this one.
  ///
  /// A source often publishes no related list at all, which used to leave the
  /// section empty or filled from an unrelated feed. The genre pass below keeps
  /// the rail truthful and ranks every candidate by how much it overlaps.
  Future<List<Anime>> related(Anime anime, {CancelToken? cancelToken}) async {
    final found = <String, Anime>{};
    try {
      for (final item in await _source.related(
        anime,
        cancelToken: cancelToken,
      )) {
        if (item.id != anime.id) found.putIfAbsent(item.id, () => item);
      }
    } on Object {
      // A source without related links falls through to the genre pass.
    }

    final wanted = anime.genres.map(normalizeArabicText).toSet();
    if (found.length < 8 && anime.genres.isNotEmpty) {
      for (final genre in anime.genres.take(2)) {
        try {
          final page = await _source.browse(
            BrowseQuery(sort: BrowseSort.popular, genre: genre),
            cancelToken: cancelToken,
          );
          for (final item in page.items) {
            if (item.id == anime.id) continue;
            found.putIfAbsent(item.id, () => item);
          }
        } on Object {
          // Try the next genre or keep what was found so far.
        }
      }
    }

    final items = found.values.toList();
    items.sort((a, b) {
      final byOverlap = _overlap(b, wanted).compareTo(_overlap(a, wanted));
      if (byOverlap != 0) return byOverlap;
      return (b.rating ?? 0).compareTo(a.rating ?? 0);
    });
    return items.take(12).toList(growable: false);
  }

  int _overlap(Anime anime, Set<String> wanted) {
    if (wanted.isEmpty) return 0;
    var score = 0;
    for (final genre in anime.genres) {
      if (wanted.contains(normalizeArabicText(genre))) score += 10;
    }
    return score;
  }

  /// Fetches a random real title for the discovery shortcut.
  Future<Anime?> randomAnime() async {
    try {
      final page = await browse(
        const BrowseQuery(sort: BrowseSort.popular),
        page: _random.nextInt(8),
      );
      if (page.items.isEmpty) return null;
      return page.items[_random.nextInt(page.items.length)];
    } on AppFailure {
      return null;
    }
  }

  AppFailure _failure(Object error) {
    if (error is AppFailure) return error;
    return AppFailure.from(error);
  }

  Paged<T>? _cachedPaged<T>(
    String key,
    T Function(Map<String, dynamic>) decode,
  ) {
    final cached = _store.readCache(key, allowStale: true);
    if (cached is! List || cached.isEmpty) return null;
    final items = cached
        .whereType<Map>()
        .map((json) => decode(json.cast<String, dynamic>()))
        .toList(growable: false);
    return Paged<T>(items: items, page: 0, hasMore: false, total: items.length);
  }

  Map<String, dynamic> _latestToJson(LatestEpisode item) => <String, dynamic>{
    'anime': item.anime.toJson(),
    'episode': item.episode.toJson(),
    'releasedAt': item.releasedAt?.toIso8601String(),
  };

  LatestEpisode _latestFromJson(Map<String, dynamic> json) => LatestEpisode(
    anime: Anime.fromJson((json['anime'] as Map).cast<String, dynamic>()),
    episode: AnimeEpisode.fromJson(
      (json['episode'] as Map).cast<String, dynamic>(),
    ),
    releasedAt: DateTime.tryParse(json['releasedAt'] as String? ?? ''),
  );
}

class _MemoryEntry<T> {
  _MemoryEntry(this.value, this.ttl) : _createdAt = DateTime.now();

  final T value;
  final Duration ttl;
  final DateTime _createdAt;

  bool get isExpired => DateTime.now().difference(_createdAt) > ttl;
}
