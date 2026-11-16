import 'package:dio/dio.dart';

import '../../core/utils/json_x.dart';
import '../models/anime.dart';
import 'algolia_client.dart';
import 'anime_source.dart';
import 'firestore_client.dart';
import 'wings_config.dart';

/// Catalogue implementation backed by the public read-only indexes and the
/// episode/stream documents published alongside them.
class WingsCatalogueSource implements AnimeSource {
  WingsCatalogueSource({required this._index, required this._firestore});

  final SearchIndexClient _index;
  final FirestoreClient _firestore;

  static const List<String> _seriesAttributes = <String>[
    'objectID',
    'name',
    'english_title',
    'poster',
    'poster_uri',
    'cover_uri',
    'story',
    'tags',
    'details',
    'views',
    'rating',
    'doc_ref',
    'path',
    'duration',
    'related_anime_ids',
    'aniList_poster',
    'alternative_titles',
    'type',
    'dubbed',
    'mal_id',
  ];

  static const List<String> _latestAttributes = <String>[
    'anime_id',
    'episode_id',
    'episode_name',
    'name',
    'doc_ref',
    'poster_uri',
    'poster_url_aniList',
    'thumb_uri',
    'tags',
    'type',
    'date',
    'title',
    'filler',
  ];

  @override
  String get id => 'wings-catalogue';

  @override
  Future<Paged<LatestEpisode>> latestEpisodes({
    int page = 0,
    CancelToken? cancelToken,
  }) async {
    final result = await _index.query(
      WingsConfig.indexRecent,
      page: page,
      hitsPerPage: 30,
      attributesToRetrieve: _latestAttributes,
      cancelToken: cancelToken,
    );
    final items = result.hits
        .map(_mapLatest)
        .where((e) => e.anime.id.isNotEmpty)
        .toList(growable: false);
    return Paged<LatestEpisode>(
      items: items,
      page: result.page,
      hasMore: result.hasMore,
      total: result.total,
    );
  }

  @override
  Future<Paged<Anime>> browse(
    BrowseQuery query, {
    int page = 0,
    CancelToken? cancelToken,
  }) async {
    final result = await _index.query(
      _indexFor(query.sort),
      page: page,
      hitsPerPage: 24,
      facetFilter: query.genre == null ? null : 'tags:"${query.genre}"',
      attributesToRetrieve: _seriesAttributes,
      cancelToken: cancelToken,
    );
    return Paged<Anime>(
      items: result.hits
          .map(_mapAnime)
          .where((a) => a.id.isNotEmpty)
          .toList(growable: false),
      page: result.page,
      hasMore: result.hasMore,
      total: result.total,
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
    final result = await _index.query(
      WingsConfig.indexSeries,
      text: trimmed,
      page: page,
      hitsPerPage: 24,
      attributesToRetrieve: _seriesAttributes,
      cancelToken: cancelToken,
    );
    return Paged<Anime>(
      items: result.hits
          .map(_mapAnime)
          .where((a) => a.id.isNotEmpty)
          .toList(growable: false),
      page: result.page,
      hasMore: result.hasMore,
      total: result.total,
    );
  }

  @override
  Future<Anime> animeById(String id, {CancelToken? cancelToken}) async {
    final escaped = id.replaceAll(r'\', r'\\').replaceAll('"', r'\"');
    final result = await _index.query(
      WingsConfig.indexSeries,
      filters: 'objectID:"$escaped"',
      hitsPerPage: 1,
      attributesToRetrieve: _seriesAttributes,
      cancelToken: cancelToken,
    );
    if (result.hits.isEmpty) {
      // Fall back to a title search for deep links that carry a display title.
      final byTitle = await _index.query(
        WingsConfig.indexSeries,
        text: id,
        hitsPerPage: 1,
        attributesToRetrieve: _seriesAttributes,
        cancelToken: cancelToken,
      );
      if (byTitle.hits.isEmpty) {
        throw const FormatException('anime not found');
      }
      return _mapAnime(byTitle.hits.first);
    }
    return _mapAnime(result.hits.first);
  }

  @override
  Future<List<AnimeEpisode>> episodes(
    Anime anime, {
    CancelToken? cancelToken,
  }) async {
    final path = anime.contentPath ?? 'anime_list/${anime.id}';
    final fields = await _firestore.getFields(
      '$path/episodes_summery/summery',
      cancelToken: cancelToken,
    );
    final raw = fields?['episodes'];
    if (raw is! List) return const [];

    final episodes = <String, AnimeEpisode>{};
    for (var i = 0; i < raw.length; i++) {
      final item = raw[i];
      if (item is! Map) continue;
      try {
        final map = item.cast<String, dynamic>();
        final docId = map['doc_id']?.toString() ?? map['id']?.toString();
        if (docId == null || docId.isEmpty) continue;

        // `title_translated` is usually a {ar: ...} map, but a few older
        // documents store a plain string instead.
        final translatedRaw = map['title_translated'];
        final translated = translatedRaw is Map
            ? translatedRaw.cast<String, dynamic>()
            : null;
        final displayTitle =
            translated?.str('ar') ??
            (translatedRaw is String && translatedRaw.trim().isNotEmpty
                ? translatedRaw
                : null) ??
            map['name']?.toString();
        final number = map['number'] is num
            ? (map['number'] as num).toInt()
            : int.tryParse(map['number']?.toString() ?? '') ??
                  _firstNumber(displayTitle) ??
                  i + 1;

        episodes[docId] = AnimeEpisode(
          id: docId,
          number: number,
          animeId: anime.id,
          title: displayTitle,
          thumbnailUrl: map['thumb_uri']?.toString(),
          filler: map['filler'] == true,
        );
      } on Object {
        // A single malformed record must not hide the rest of the season.
        continue;
      }
    }

    final list = episodes.values.toList()
      ..sort((a, b) => a.number.compareTo(b.number));
    return list;
  }

  @override
  Future<List<StreamServer>> servers(
    Anime anime,
    AnimeEpisode episode, {
    CancelToken? cancelToken,
  }) async {
    final path = anime.contentPath ?? 'anime_list/${anime.id}';
    var raw = <Map<String, dynamic>>[];

    final summary = await _firestore.getFields(
      '$path/episodes/${episode.id}/servers2/all_servers',
      cancelToken: cancelToken,
    );
    final values = summary?['servers'];
    if (values is List) {
      raw = values
          .whereType<Map>()
          .map((item) => item.cast<String, dynamic>())
          .where((item) => item['visible'] != false)
          .toList();
    }

    if (raw.isEmpty) {
      final documents = await _firestore.getDocuments(
        '$path/episodes/${episode.id}/servers',
        cancelToken: cancelToken,
      );
      raw = documents.where((item) => item['visible'] != false).toList();
    }

    final servers = <StreamServer>[];
    for (final item in raw) {
      final name = item.str('name');
      final link = item.str('link') ?? item.str('url');
      if (name == null || link == null) continue;
      final quality = item.str('quality') ?? '';
      final directFlag = item.boolean('direct_link') ?? false;
      final openBrowser = item.boolean('open_browser') ?? false;
      final flavor = _flavorFor(name, link, directFlag);
      servers.add(
        StreamServer(
          name: name,
          url: link,
          quality: quality.isEmpty ? '—' : quality,
          flavor: flavor,
          requiresBrowser:
              flavor == ServerFlavor.browser ||
              (openBrowser && flavor == ServerFlavor.direct),
          isDirectFile: flavor == ServerFlavor.direct,
        ),
      );
    }

    servers.sort((a, b) {
      final byQuality = b.qualityRank.compareTo(a.qualityRank);
      if (byQuality != 0) return byQuality;
      return _flavorPriority(a.flavor).compareTo(_flavorPriority(b.flavor));
    });
    return servers;
  }

  @override
  Future<List<Genre>> genres({CancelToken? cancelToken}) async {
    final result = await _index.query(
      WingsConfig.indexSeries,
      hitsPerPage: 0,
      facets: const <String>['tags'],
      cancelToken: cancelToken,
    );
    final counts = result.facets['tags'];
    if (counts == null || counts.isEmpty) return const [];
    final genres =
        counts.entries
            .where((entry) => entry.value > 0 && entry.key.trim().isNotEmpty)
            .where(
              (entry) =>
                  !entry.key.startsWith('+') && int.tryParse(entry.key) == null,
            )
            .map((entry) => Genre(name: entry.key, count: entry.value))
            .toList()
          ..sort((a, b) => (b.count ?? 0).compareTo(a.count ?? 0));
    return genres;
  }

  @override
  Future<List<Anime>> related(Anime anime, {CancelToken? cancelToken}) async {
    final ids = anime.relatedIds.take(10).toList(growable: false);
    if (ids.isEmpty) return const [];
    final results = await Future.wait(
      ids.map((id) async {
        try {
          return await animeById(id, cancelToken: cancelToken);
        } on Object {
          return null;
        }
      }),
    );
    return results.whereType<Anime>().toList(growable: false);
  }

  String _indexFor(BrowseSort sort) => switch (sort) {
    BrowseSort.newest => WingsConfig.indexByNewest,
    BrowseSort.oldest => WingsConfig.indexByOldest,
    BrowseSort.titleAsc => WingsConfig.indexByTitle,
    BrowseSort.popular => WingsConfig.indexByPopularity,
    BrowseSort.rating => WingsConfig.indexByRating,
  };

  int _flavorPriority(ServerFlavor flavor) => switch (flavor) {
    ServerFlavor.pixelDrain => 0,
    ServerFlavor.mediaFire => 1,
    ServerFlavor.direct => 2,
    ServerFlavor.streamTape => 3,
    ServerFlavor.browser => 4,
  };

  ServerFlavor _flavorFor(String name, String link, bool directFlag) {
    final code = name.trim().toUpperCase();
    if (code == 'PD') return ServerFlavor.pixelDrain;
    if (code == 'MF' || code == 'MF2') return ServerFlavor.mediaFire;
    if (code == 'ST') return ServerFlavor.streamTape;
    final isFile = RegExp(
      r'\.(mp4|m3u8|mkv)(\?|$)',
      caseSensitive: false,
    ).hasMatch(link);
    if (isFile || directFlag) return ServerFlavor.direct;
    return ServerFlavor.browser;
  }

  Anime _mapAnime(Map<String, dynamic> hit) {
    final details = hit.obj('details');
    final poster = hit.obj('poster');
    final alternative = hit.obj('alternative_titles');
    final id =
        hit.str('objectID') ?? hit.str('anime_id') ?? hit.str('name') ?? '';
    final title =
        hit.str('name') ??
        hit.str('english_title') ??
        details.str('english_title') ??
        id;
    final englishTitle =
        hit.str('english_title') ??
        details.str('english_title') ??
        alternative.str('en');
    final posterUrl =
        hit.str('poster_uri') ??
        poster.str('medium') ??
        poster.str('large') ??
        hit.str('aniList_poster') ??
        hit.str('poster_url_aniList');
    final backdropUrl =
        hit.str('cover_uri') ?? poster.str('large') ?? posterUrl;
    final year = details.integer('year') ?? hit.integer('year');
    final status = details.str('state') ?? hit.str('status');
    final studios = details.list('studio').asStringList();
    final starRating = hit.dbl('rating');
    final rating = details.dbl('mal_mean') ?? _saneRating(starRating);

    return Anime(
      id: id,
      title: title,
      englishTitle: englishTitle == title ? null : englishTitle,
      posterUrl: posterUrl,
      backdropUrl: backdropUrl,
      synopsis: cleanHtml(hit.str('story')),
      genres: hit.list('tags').asStringList(),
      type: hit.str('type') ?? details.str('type'),
      year: year == 0 ? null : year,
      status: status,
      rating: rating,
      views: hit.integer('views'),
      episodeCount: details.integer('episodes') ?? hit.integer('episodes'),
      season: details.str('season'),
      studios: studios,
      releaseDate: details.str('start_date'),
      durationMinutes: hit.integer('duration'),
      contentPath: hit.str('doc_ref') ?? hit.str('path'),
      isDubbed: hit.boolean('dubbed') ?? false,
      relatedIds: hit.list('related_anime_ids').asStringList(),
    );
  }

  LatestEpisode _mapLatest(Map<String, dynamic> hit) {
    final highlight = hit.obj('_highlightResult');

    String? pick(String key) {
      final direct = hit.str(key);
      if (direct != null) return direct;
      final raw = highlight?[key];
      if (raw is Map) {
        final value = raw['value'];
        if (value is String && value.trim().isNotEmpty) {
          return value.replaceAll(RegExp(r'</?em>'), '').trim();
        }
      }
      return null;
    }

    final animeId = pick('anime_id') ?? pick('objectID') ?? pick('name') ?? '';
    final title = pick('name') ?? pick('title') ?? animeId;
    final docRef = pick('doc_ref');
    final poster = pick('poster_uri') ?? pick('poster_url_aniList');
    final episodeId = pick('episode_id') ?? '';
    final episodeTitle = pick('episode_name');
    final number = int.tryParse(episodeId) ?? _firstNumber(episodeTitle) ?? 0;
    final anime = Anime(
      id: animeId,
      title: title,
      posterUrl: poster,
      backdropUrl: pick('poster_url_aniList') ?? poster,
      genres: hit.list('tags').asStringList(),
      type: pick('type'),
      contentPath: docRef ?? 'anime_list/$animeId',
    );
    final episode = AnimeEpisode(
      id: episodeId,
      number: number,
      animeId: animeId,
      title: episodeTitle,
      thumbnailUrl: pick('thumb_uri'),
    );
    return LatestEpisode(
      anime: anime,
      episode: episode,
      releasedAt: _parseTimestamp(hit['date'] ?? highlight?['date']),
    );
  }

  static double? _saneRating(double? value) {
    if (value == null || value <= 0 || value > 10) return null;
    return value;
  }

  static int? _firstNumber(String? value) {
    if (value == null) return null;
    final match = RegExp(r'\d+').firstMatch(value);
    if (match == null) return null;
    return int.tryParse(match.group(0)!);
  }

  static DateTime? _parseTimestamp(dynamic value) {
    if (value == null) return null;
    if (value is num) {
      return DateTime.fromMillisecondsSinceEpoch(value.toInt() * 1000);
    }
    if (value is String) return DateTime.tryParse(value);
    if (value is Map) {
      final seconds = value['_seconds'] ?? value['seconds'];
      if (seconds is Map) {
        final inner = seconds['value'];
        final parsed = int.tryParse(inner?.toString() ?? '');
        if (parsed != null) {
          return DateTime.fromMillisecondsSinceEpoch(parsed * 1000);
        }
      }
      if (seconds is num) {
        return DateTime.fromMillisecondsSinceEpoch(seconds.toInt() * 1000);
      }
      final timestamp = value['timestampValue'];
      if (timestamp is String) return DateTime.tryParse(timestamp);
    }
    return null;
  }
}
