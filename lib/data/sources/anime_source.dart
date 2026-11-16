import 'package:dio/dio.dart';

import '../models/anime.dart';

/// Source-independent catalogue contract.
///
/// The presentation layer depends only on this interface, so additional
/// catalogues can be added without touching any screen.
abstract interface class AnimeSource {
  /// Non-user-facing identifier used for logging and cache namespacing.
  String get id;

  Future<Paged<LatestEpisode>> latestEpisodes({
    int page,
    CancelToken? cancelToken,
  });

  Future<Paged<Anime>> browse(
    BrowseQuery query, {
    int page,
    CancelToken? cancelToken,
  });

  Future<Paged<Anime>> search(
    String text, {
    int page,
    CancelToken? cancelToken,
  });

  Future<Anime> animeById(String id, {CancelToken? cancelToken});

  Future<List<AnimeEpisode>> episodes(Anime anime, {CancelToken? cancelToken});

  Future<List<StreamServer>> servers(
    Anime anime,
    AnimeEpisode episode, {
    CancelToken? cancelToken,
  });

  Future<List<Genre>> genres({CancelToken? cancelToken});

  Future<List<Anime>> related(Anime anime, {CancelToken? cancelToken});
}
