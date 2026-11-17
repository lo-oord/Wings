import 'package:flutter/foundation.dart';

/// A single anime title as exposed by the catalogue layer.
///
/// The UI only ever sees this model, never raw source payloads.
@immutable
class Anime {
  const Anime({
    required this.id,
    required this.title,
    this.englishTitle,
    this.posterUrl,
    this.backdropUrl,
    this.synopsis,
    this.genres = const <String>[],
    this.type,
    this.year,
    this.status,
    this.rating,
    this.views,
    this.episodeCount,
    this.season,
    this.studios = const <String>[],
    this.releaseDate,
    this.durationMinutes,
    this.contentPath,
    this.isDubbed = false,
    this.relatedIds = const <String>[],
  });

  final String id;
  final String title;
  final String? englishTitle;
  final String? posterUrl;
  final String? backdropUrl;
  final String? synopsis;
  final List<String> genres;
  final String? type;
  final int? year;
  final String? status;
  final double? rating;
  final int? views;
  final int? episodeCount;
  final String? season;
  final List<String> studios;
  final String? releaseDate;
  final int? durationMinutes;
  final String? contentPath;
  final bool isDubbed;
  final List<String> relatedIds;

  String get displayTitle =>
      (englishTitle != null && englishTitle!.trim().isNotEmpty)
      ? englishTitle!
      : title;

  String? get imageUrl => posterUrl ?? backdropUrl;

  String get routeId => Uri.encodeComponent(id);

  Map<String, dynamic> toJson() => <String, dynamic>{
    'id': id,
    'title': title,
    'englishTitle': englishTitle,
    'posterUrl': posterUrl,
    'backdropUrl': backdropUrl,
    'synopsis': synopsis,
    'genres': genres,
    'type': type,
    'year': year,
    'status': status,
    'rating': rating,
    'views': views,
    'episodeCount': episodeCount,
    'season': season,
    'studios': studios,
    'releaseDate': releaseDate,
    'durationMinutes': durationMinutes,
    'contentPath': contentPath,
    'isDubbed': isDubbed,
    'relatedIds': relatedIds,
  };

  factory Anime.fromJson(Map<String, dynamic> json) {
    List<String> strings(Object? value) => value is List
        ? value
              .map((e) => e.toString())
              .where((e) => e.isNotEmpty)
              .toList(growable: false)
        : const <String>[];
    return Anime(
      id: json['id'] as String,
      title: json['title'] as String? ?? '',
      englishTitle: json['englishTitle'] as String?,
      posterUrl: json['posterUrl'] as String?,
      backdropUrl: json['backdropUrl'] as String?,
      synopsis: json['synopsis'] as String?,
      genres: strings(json['genres']),
      type: json['type'] as String?,
      year: (json['year'] as num?)?.toInt(),
      status: json['status'] as String?,
      rating: (json['rating'] as num?)?.toDouble(),
      views: (json['views'] as num?)?.toInt(),
      episodeCount: (json['episodeCount'] as num?)?.toInt(),
      season: json['season'] as String?,
      studios: strings(json['studios']),
      releaseDate: json['releaseDate'] as String?,
      durationMinutes: (json['durationMinutes'] as num?)?.toInt(),
      contentPath: json['contentPath'] as String?,
      isDubbed: json['isDubbed'] as bool? ?? false,
      relatedIds: strings(json['relatedIds']),
    );
  }
}

@immutable
class AnimeEpisode {
  const AnimeEpisode({
    required this.id,
    required this.number,
    required this.animeId,
    this.title,
    this.thumbnailUrl,
    this.filler = false,
  });

  final String id;
  final int number;
  final String animeId;
  final String? title;
  final String? thumbnailUrl;
  final bool filler;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'id': id,
    'number': number,
    'animeId': animeId,
    'title': title,
    'thumbnailUrl': thumbnailUrl,
    'filler': filler,
  };

  factory AnimeEpisode.fromJson(Map<String, dynamic> json) => AnimeEpisode(
    id: json['id'] as String,
    number: (json['number'] as num?)?.toInt() ?? 0,
    animeId: json['animeId'] as String? ?? '',
    title: json['title'] as String?,
    thumbnailUrl: json['thumbnailUrl'] as String?,
    filler: json['filler'] as bool? ?? false,
  );
}

/// An episode surfaced on the home feed, carrying its anime context.
@immutable
class LatestEpisode {
  const LatestEpisode({
    required this.anime,
    required this.episode,
    this.releasedAt,
  });

  final Anime anime;
  final AnimeEpisode episode;
  final DateTime? releasedAt;
}

/// How a stream server has to be handled before playback.
enum ServerFlavor { direct, pixelDrain, mediaFire, streamTape, browser }

@immutable
class StreamServer {
  const StreamServer({
    required this.name,
    required this.url,
    required this.quality,
    required this.flavor,
    this.requiresBrowser = false,
    this.isDirectFile = false,
    this.headers = const <String, String>{},
  });

  final String name;
  final String url;

  /// Raw quality label as published by the source, e.g. `1080p`.
  final String quality;
  final ServerFlavor flavor;
  final bool requiresBrowser;
  final bool isDirectFile;

  /// Extra request headers the stream host requires (referer, cookies …).
  final Map<String, String> headers;

  int get qualityRank {
    final digits = RegExp(r'\d+').firstMatch(quality)?.group(0);
    return int.tryParse(digits ?? '') ?? 0;
  }

  bool get isDownloadable => flavor != ServerFlavor.browser;
}

@immutable
class ResolvedStream {
  const ResolvedStream({
    required this.url,
    required this.server,
    this.headers = const <String, String>{},
  });

  final String url;
  final StreamServer server;
  final Map<String, String> headers;

  String get quality => server.quality;
}

/// A page of results with pagination state.
@immutable
class Paged<T> {
  const Paged({
    required this.items,
    required this.page,
    required this.hasMore,
    this.total,
  });

  const Paged.empty()
    : items = const [],
      page = 0,
      hasMore = false,
      total = null;

  final List<T> items;
  final int page;
  final bool hasMore;
  final int? total;

  Paged<T> append(Paged<T> next) => Paged<T>(
    items: <T>[...items, ...next.items],
    page: next.page,
    hasMore: next.hasMore,
    total: next.total ?? total,
  );
}

enum BrowseSort { newest, oldest, titleAsc, popular, rating }

@immutable
class BrowseQuery {
  const BrowseQuery({this.genre, this.sort = BrowseSort.newest, this.text});

  final String? genre;
  final BrowseSort sort;
  final String? text;

  BrowseQuery copyWith({
    String? genre,
    BrowseSort? sort,
    String? text,
    bool clearGenre = false,
  }) {
    return BrowseQuery(
      genre: clearGenre ? null : (genre ?? this.genre),
      sort: sort ?? this.sort,
      text: text ?? this.text,
    );
  }
}

/// A genre with the number of titles the source reports for it.
@immutable
class Genre {
  const Genre({required this.name, this.count});

  final String name;
  final int? count;
}
