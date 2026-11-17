import 'package:dio/dio.dart';

import '../../core/utils/title_series.dart';
import '../models/anime.dart';
import 'anime_source.dart';
import 'cartoony_source.dart';

/// Fan-out catalogue that serves several independent sources as one.
///
/// Results keep their own identity, so nothing is hidden or replaced when one
/// source fails: search, browse and the latest feed merge whatever answered.
/// A single request routes back to the source that owns the identifier.
class MultiSourceCatalogue implements AnimeSource {
  MultiSourceCatalogue(List<AnimeSource> sources)
    : _sources = List<AnimeSource>.unmodifiable(sources);

  final List<AnimeSource> _sources;

  static const int _mergedPageSize = 30;
  static const int _mergedLatestSize = 40;

  @override
  String get id => 'multi-source';

  AnimeSource get _primary {
    if (_sources.isEmpty) {
      throw StateError('no catalogue sources configured');
    }
    return _sources.first;
  }

  AnimeSource _route(String animeId) {
    for (final source in _sources) {
      final candidate = source;
      if (candidate is CartoonySource && candidate.owns(animeId)) {
        return candidate;
      }
    }
    return _primary;
  }

  @override
  Future<Paged<LatestEpisode>> latestEpisodes({
    int page = 0,
    CancelToken? cancelToken,
  }) async {
    final failures = <Object>[];
    final pages = await Future.wait(
      _sources.map(
        (source) => _attempt(
          () => source.latestEpisodes(page: page, cancelToken: cancelToken),
          failures,
        ),
      ),
    );
    if (page > 0) {
      return _firstPage<LatestEpisode>(pages) ??
          _fail<Paged<LatestEpisode>>(failures);
    }

    final items = <LatestEpisode>[];
    final seen = <String>{};
    for (final result in pages) {
      for (final item in result?.items ?? const <LatestEpisode>[]) {
        if (seen.add('${item.anime.id}:${item.episode.id}')) {
          items.add(item);
        }
      }
    }
    if (items.isEmpty) return _fail<Paged<LatestEpisode>>(failures);
    return Paged<LatestEpisode>(
      items: items.take(_mergedLatestSize).toList(growable: false),
      page: 0,
      hasMore: pages.any((page) => page?.hasMore ?? false),
      total: items.length,
    );
  }

  @override
  Future<Paged<Anime>> browse(
    BrowseQuery query, {
    int page = 0,
    CancelToken? cancelToken,
  }) async {
    final failures = <Object>[];
    final pages = await Future.wait(
      _sources.map(
        (source) => _attempt(
          () => source.browse(query, page: page, cancelToken: cancelToken),
          failures,
        ),
      ),
    );

    // Interleave so every source is represented on the first screen, then
    // continue filling from whichever still has results.
    final items = <Anime>[];
    final longest = pages.fold<int>(
      0,
      (length, result) =>
          (result?.items.length ?? 0) > length ? result!.items.length : length,
    );
    for (var index = 0; index < longest; index++) {
      for (final result in pages) {
        final list = result?.items ?? const <Anime>[];
        if (index < list.length) items.add(list[index]);
      }
    }
    if (items.isEmpty) return _fail<Paged<Anime>>(failures);

    return Paged<Anime>(
      items: items.take(_mergedPageSize).toList(growable: false),
      page: page,
      hasMore: pages.any((result) => result?.hasMore ?? false),
    );
  }

  @override
  Future<Paged<Anime>> search(
    String text, {
    int page = 0,
    CancelToken? cancelToken,
  }) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return const Paged<Anime>.empty();

    // Deeper pages continue through the main catalogue; the additional sources
    // return their matches on the first page.
    if (page > 0) {
      return _primary.search(trimmed, page: page, cancelToken: cancelToken);
    }

    final failures = <Object>[];
    final results = await Future.wait(
      _sources.map(
        (source) => _attempt(
          () => source.search(trimmed, cancelToken: cancelToken),
          failures,
        ),
      ),
    );

    final items = <Anime>[];
    final seen = <String>{};
    for (final result in results) {
      for (final anime in result?.items ?? const <Anime>[]) {
        if (seen.add(anime.id)) items.add(anime);
      }
    }
    if (items.isEmpty) return _fail<Paged<Anime>>(failures);

    // Relevance first: an exact title beats a title that only contains the
    // words, which in turn beats a category match. Without this the merged list
    // kept the order of the sources, so a loosely related title could appear
    // above the one the viewer typed.
    final needle = normalizeArabicText(trimmed);
    final tokens = needle
        .split(RegExp(r'\s+'))
        .where((token) => token.isNotEmpty)
        .toList(growable: false);
    int score(Anime anime) {
      var best = 0;
      for (final raw in <String>[anime.title, anime.englishTitle ?? '']) {
        final title = normalizeArabicText(raw.trim());
        if (title.isEmpty) continue;
        if (title == needle) {
          if (best < 1000) best = 1000;
        } else if (title.startsWith(needle)) {
          if (best < 700) best = 700;
        } else if (title.contains(needle)) {
          if (best < 450) best = 450;
        } else if (tokens.isNotEmpty && tokens.every(title.contains)) {
          final missing = title.length - needle.length;
          final partial = (300 - missing.clamp(0, 120)).clamp(80, 300);
          if (best < partial) best = partial;
        }
      }
      if (best == 0) {
        final genres = anime.genres.map(normalizeArabicText).join(' ');
        if (tokens.any(genres.contains)) best = 120;
      }
      // A small popularity nudge only breaks ties between equal matches.
      final rating = anime.rating ?? 0;
      return best + (rating * 2).round();
    }

    final ranked = items.asMap().entries.toList()
      ..sort((a, b) {
        final byScore = score(b.value).compareTo(score(a.value));
        if (byScore != 0) return byScore;
        return a.key.compareTo(b.key);
      });

    final grouped = groupTitlesBySeason(
      ranked.map((entry) => entry.value).toList(growable: false),
      (anime) => anime.title,
    );
    return Paged<Anime>(
      items: grouped.take(_mergedPageSize).toList(growable: false),
      page: 0,
      hasMore: results.any((result) => result?.hasMore ?? false),
      total: grouped.length,
    );
  }

  @override
  Future<Anime> animeById(String animeId, {CancelToken? cancelToken}) =>
      _route(animeId).animeById(animeId, cancelToken: cancelToken);

  @override
  Future<List<AnimeEpisode>> episodes(
    Anime anime, {
    CancelToken? cancelToken,
  }) => _route(anime.id).episodes(anime, cancelToken: cancelToken);

  @override
  Future<List<StreamServer>> servers(
    Anime anime,
    AnimeEpisode episode, {
    CancelToken? cancelToken,
  }) => _route(anime.id).servers(anime, episode, cancelToken: cancelToken);

  @override
  Future<List<Genre>> genres({CancelToken? cancelToken}) async {
    final failures = <Object>[];
    final lists = await Future.wait(
      _sources.map((source) => _attempt(() => source.genres(), failures)),
    );

    final counts = <String, int>{};
    for (final list in lists) {
      for (final genre in list ?? const <Genre>[]) {
        counts.update(
          genre.name,
          (value) => value + (genre.count ?? 1),
          ifAbsent: () => genre.count ?? 1,
        );
      }
    }
    if (counts.isEmpty) return _fail<List<Genre>>(failures);
    final merged =
        counts.entries
            .map((entry) => Genre(name: entry.key, count: entry.value))
            .toList()
          ..sort((a, b) => (b.count ?? 0).compareTo(a.count ?? 0));
    return merged;
  }

  @override
  Future<List<Anime>> related(Anime anime, {CancelToken? cancelToken}) =>
      _route(anime.id).related(anime, cancelToken: cancelToken);

  Future<T?> _attempt<T>(
    Future<T> Function() task,
    List<Object> failures,
  ) async {
    try {
      return await task();
    } on Object catch (error) {
      failures.add(error);
      return null;
    }
  }

  Paged<T>? _firstPage<T>(List<Paged<T>?> pages) {
    for (final page in pages) {
      if (page != null) return page;
    }
    return null;
  }

  T _fail<T>(List<Object> failures) {
    final error = failures.isEmpty
        ? StateError('no catalogue sources configured')
        : failures.first;
    if (error is Error) throw error;
    throw error;
  }
}
