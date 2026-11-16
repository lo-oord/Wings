import 'dart:math';

import 'package:dio/dio.dart';

import '../../core/errors/app_failure.dart';
import '../../core/storage/local_store.dart';
import '../models/anime.dart';
import '../sources/anime_source.dart';
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
      return await _source.servers(anime, episode, cancelToken: cancelToken);
    } on Object catch (error) {
      throw _failure(error);
    }
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

  Future<List<Anime>> related(Anime anime, {CancelToken? cancelToken}) async {
    try {
      return await _source.related(anime, cancelToken: cancelToken);
    } on Object catch (_) {
      return const [];
    }
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
