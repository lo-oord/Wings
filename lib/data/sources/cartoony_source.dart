import 'package:dio/dio.dart';

import '../../core/utils/json_x.dart';
import '../../core/utils/title_series.dart';
import '../models/anime.dart';
import 'anime_source.dart';
import 'cartoony_crypto.dart';

/// The two public catalogues published by the site.
enum CartoonyCatalog {
  /// «سبيستون غو» — the Spacetoon Go library.
  spacetoonGo(slug: 'sp', label: 'سبيستون غو'),

  /// «كرتون أيام زمان» — classic cartoons.
  classic(slug: 'tg', label: 'كرتون أيام زمان');

  const CartoonyCatalog({required this.slug, required this.label});

  /// Path segment used by the endpoints and by the stored identifier.
  final String slug;

  /// User-facing catalogue name.
  final String label;
}

/// Catalogue implementation for the public Cartoony / Carateen site.
///
/// The endpoints answer with an encrypted JSON envelope and serve HLS streams.
/// Shows, episodes and stream links are read directly; nothing is scraped from
/// rendered pages. Two instances exist, one per public catalogue, so each one
/// behaves as an independent source in the app.
class CartoonySource implements AnimeSource {
  CartoonySource(this._dio, {required this.catalog});

  final Dio _dio;
  final CartoonyCatalog catalog;

  /// Primary host. The site also answers on its previous domain, which is used
  /// as a fallback when the primary host refuses a request.
  static const String baseUrl = 'https://cartoony.net';

  static const List<String> _bases = <String>[baseUrl, 'https://carateen.tv'];

  static const int _pageSize = 24;

  @override
  String get id => 'cartoony-${catalog.slug}';

  /// User-facing source name.
  String get label => catalog.label;

  /// Prefix that marks identifiers owned by this source.
  String get idPrefix => 'c${catalog.slug}';

  List<Map<String, dynamic>>? _shows;
  Future<List<Map<String, dynamic>>>? _pending;
  final Map<String, String> _qualities = <String, String>{};

  /// Host that answered the last request; its referer is required by the
  /// stream host before it serves playlists or segments.
  String _lastBase = baseUrl;

  bool owns(String id) => id.startsWith('$idPrefix:');

  String encodeId(int showId) => '$idPrefix:$showId';

  int? _showIdOf(String id) {
    if (!owns(id)) return null;
    return int.tryParse(id.substring(idPrefix.length + 1));
  }

  @override
  Future<Paged<LatestEpisode>> latestEpisodes({
    int page = 0,
    CancelToken? cancelToken,
  }) async {
    if (catalog != CartoonyCatalog.spacetoonGo || page > 0) {
      return const Paged<LatestEpisode>.empty();
    }
    final raw = await _request(
      '/api/sp/recentEpisodes',
      cancelToken: cancelToken,
    );
    if (raw is! List) return const Paged<LatestEpisode>.empty();
    final items = <LatestEpisode>[];
    for (final item in raw.whereType<Map>()) {
      final map = item.cast<String, dynamic>();
      final showId = map.integer('tv_series_id');
      final title = map.str('name');
      if (showId == null || title == null) continue;
      final episodeId = map.integer('id')?.toString();
      final animeId = encodeId(showId);
      final anime = Anime(
        id: animeId,
        title: title,
        posterUrl: map.str('cover_full_path'),
        backdropUrl: map.str('cover_full_path'),
        contentPath: animeId,
      );
      items.add(
        LatestEpisode(
          anime: anime,
          episode: AnimeEpisode(
            id: episodeId ?? '',
            number: map.integer('number') ?? 0,
            animeId: animeId,
            title: map.str('pref'),
            thumbnailUrl: map.str('cover_full_path'),
          ),
        ),
      );
    }
    return Paged<LatestEpisode>(
      items: items,
      page: 0,
      hasMore: false,
      total: items.length,
    );
  }

  @override
  Future<Paged<Anime>> browse(
    BrowseQuery query, {
    int page = 0,
    CancelToken? cancelToken,
  }) async {
    final shows = await _catalogue();
    var matched = shows
        .where((show) {
          final genre = query.genre;
          if (genre == null) return true;
          final needle = normalizeArabicText(genre);
          return _genresOf(show)
              .any((item) => normalizeArabicText(item) == needle);
        })
        .toList(growable: false);

    matched = _sorted(matched, query.sort);
    return _page(matched, page);
  }

  @override
  Future<Paged<Anime>> search(
    String text, {
    int page = 0,
    CancelToken? cancelToken,
  }) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return const Paged<Anime>.empty();
    final shows = await _catalogue();
    final tokens = normalizeArabicText(trimmed)
        .split(RegExp(r'\s+'))
        .where((token) => token.isNotEmpty)
        .toList(growable: false);
    final matched = shows
        .where((show) {
          final haystack = normalizeArabicText(
            '${_titleOf(show)} ${_genresOf(show).join(' ')}',
          );
          return tokens.every(haystack.contains);
        })
        .toList(growable: false);
    return _page(matched, page);
  }

  @override
  Future<Anime> animeById(String id, {CancelToken? cancelToken}) async {
    final showId = _showIdOf(id);
    if (showId == null) throw const FormatException('anime not found');
    final shows = await _catalogue();
    for (final show in shows) {
      if (show.integer('id') == showId) return _mapShow(show);
    }
    throw const FormatException('anime not found');
  }

  @override
  Future<List<AnimeEpisode>> episodes(
    Anime anime, {
    CancelToken? cancelToken,
  }) async {
    final showId = _showIdOf(anime.id);
    if (showId == null) return const <AnimeEpisode>[];
    final path = catalog == CartoonyCatalog.spacetoonGo
        ? '/api/sp/episodes?id=$showId'
        : '/api/episodes?id=$showId';
    final raw = await _request(path, cancelToken: cancelToken);
    if (raw is! List) return const <AnimeEpisode>[];

    final episodes = <AnimeEpisode>[];
    for (final item in raw.whereType<Map>()) {
      final map = item.cast<String, dynamic>();
      final episodeId = map.str('id');
      if (episodeId == null) continue;
      final season = map.str('season');
      final rawTitle = catalog == CartoonyCatalog.spacetoonGo
          ? map.str('pref')
          : map.str('title');
      final title = season != null && rawTitle != null
          ? '$season · $rawTitle'
          : rawTitle;
      final thumbnail = catalog == CartoonyCatalog.spacetoonGo
          ? map.str('cover_full_path')
          : _asset(map.str('thumbnail'), 'thumbnails');
      episodes.add(
        AnimeEpisode(
          id: episodeId,
          number: catalog == CartoonyCatalog.spacetoonGo
              ? (map.integer('number') ?? 0)
              : (map.integer('order_id') ?? 0),
          animeId: anime.id,
          title: title,
          thumbnailUrl: thumbnail,
        ),
      );
    }
    episodes.sort((a, b) {
      final byNumber = a.number.compareTo(b.number);
      if (byNumber != 0) return byNumber;
      return a.id.compareTo(b.id);
    });
    return episodes;
  }

  @override
  Future<List<StreamServer>> servers(
    Anime anime,
    AnimeEpisode episode, {
    CancelToken? cancelToken,
  }) async {
    final showId = _showIdOf(anime.id);
    if (showId == null) return const <StreamServer>[];

    final Object? payload;
    if (catalog == CartoonyCatalog.spacetoonGo) {
      payload = await _request(
        '/api/sp/episode/link',
        body: <String, dynamic>{'episodeId': episode.id},
        cancelToken: cancelToken,
      );
    } else {
      payload = await _request(
        '/api/episode?episodeId=${Uri.encodeComponent(episode.id)}'
        '&showId=$showId',
        cancelToken: cancelToken,
      );
    }
    if (payload is! Map) return const <StreamServer>[];
    final map = payload.cast<String, dynamic>();
    final link = map.str('link') ?? map.str('streamUrl');
    if (link == null || !link.startsWith('http')) {
      return const <StreamServer>[];
    }

    final headers = <String, String>{
      'Referer': '$_lastBase/',
      'Origin': _lastBase,
      'Accept': 'application/vnd.apple.mpegurl, application/x-mpegURL, */*',
    };
    if (link.contains('.m3u8')) {
      final variants = await _playlistVariants(link);
      if (variants.length > 1) {
        return <StreamServer>[
          for (final variant in variants)
            StreamServer(
              name: label,
              url: variant.url,
              quality: variant.quality,
              flavor: ServerFlavor.direct,
              headers: headers,
            ),
        ];
      }
    }

    return <StreamServer>[
      StreamServer(
        name: label,
        url: link,
        quality: _qualityForId(showId),
        flavor: ServerFlavor.direct,
        headers: headers,
      ),
    ];
  }

  /// Reads the quality ladder published by the stream host.
  Future<List<({String quality, String url})>> _playlistVariants(
    String playlistUrl,
  ) async {
    try {
      final response = await _dio.get<String>(
        playlistUrl,
        options: Options(
          responseType: ResponseType.plain,
          headers: <String, String>{'Referer': '$_lastBase/', 'Accept': '*/*'},
        ),
      );
      final text = response.data;
      if (response.statusCode != 200 ||
          text == null ||
          !text.contains('#EXT-X-STREAM-INF')) {
        return const <({String quality, String url})>[];
      }
      final base = Uri.tryParse(playlistUrl);
      if (base == null) return const <({String quality, String url})>[];

      final variants = <({String quality, String url})>[];
      String? pending;
      for (final rawLine in text.split('\n')) {
        final line = rawLine.trim();
        if (line.isEmpty) continue;
        if (line.startsWith('#EXT-X-STREAM-INF')) {
          pending = _qualityLabel(line);
        } else if (!line.startsWith('#') && pending != null) {
          variants.add((quality: pending, url: base.resolve(line).toString()));
          pending = null;
        }
      }
      return variants;
    } on Object {
      return const <({String quality, String url})>[];
    }
  }

  String _qualityLabel(String tag) {
    final name = RegExp(r'NAME="([^"]+)"').firstMatch(tag)?.group(1);
    if (name != null && name.trim().isNotEmpty) return name.trim();
    final height = RegExp(r'RESOLUTION=\d+x(\d+)').firstMatch(tag)?.group(1);
    if (height != null) return '${height}p';
    return 'HD';
  }

  @override
  Future<List<Genre>> genres({CancelToken? cancelToken}) async {
    final shows = await _catalogue();
    final counts = <String, int>{};
    for (final show in shows) {
      for (final genre in _genresOf(show)) {
        counts.update(genre, (value) => value + 1, ifAbsent: () => 1);
      }
    }
    // The catalogue also carries thousands of one-off tags; only genres that
    // recur are useful as browsable categories.
    final genres =
        counts.entries
            .where((entry) => entry.key.trim().isNotEmpty && entry.value >= 3)
            .map((entry) => Genre(name: entry.key, count: entry.value))
            .toList()
          ..sort((a, b) => (b.count ?? 0).compareTo(a.count ?? 0));
    return genres;
  }

  @override
  Future<List<Anime>> related(Anime anime, {CancelToken? cancelToken}) async {
    final shows = await _catalogue();
    final key = seriesGroupKey(anime.title);
    if (key.isEmpty) return const <Anime>[];
    final matches = shows
        .where((show) => seriesGroupKey(_titleOf(show)) == key)
        .map(_mapShow)
        .where((item) => item.id != anime.id)
        .take(10)
        .toList(growable: false);
    return matches;
  }

  // -- data ----------------------------------------------------------------

  Future<List<Map<String, dynamic>>> _catalogue() {
    final cached = _shows;
    if (cached != null) return Future<List<Map<String, dynamic>>>.value(cached);
    final pending = _pending;
    if (pending != null) return pending;

    final future = _loadCatalogue();
    _pending = future;
    return future
        .then((shows) {
          _shows = shows;
          return shows;
        })
        .whenComplete(() => _pending = null);
  }

  Future<List<Map<String, dynamic>>> _loadCatalogue() async {
    final path = catalog == CartoonyCatalog.spacetoonGo
        ? '/api/sp/tvshows'
        : '/api/tvshows';
    final raw = await _request(path);
    if (raw is! List) {
      throw const FormatException('catalogue returned no shows');
    }
    final shows = raw
        .whereType<Map>()
        .map((item) => item.cast<String, dynamic>())
        .where((item) => _titleOf(item).isNotEmpty)
        .toList(growable: false);
    if (shows.isEmpty) {
      throw const FormatException('catalogue returned no shows');
    }
    for (final show in shows) {
      final showId = show.integer('id');
      final quality = show.str('quality');
      if (showId != null && quality != null) {
        _qualities['$showId'] = quality;
      }
    }
    return shows;
  }

  String _qualityForId(int showId) => _qualities['$showId'] ?? '—';

  Future<Object?> _request(
    String path, {
    Map<String, dynamic>? body,
    CancelToken? cancelToken,
  }) async {
    Object? failure;
    for (final base in _bases) {
      for (var attempt = 0; attempt < 2; attempt++) {
        try {
          final response = await _dio.request<String>(
            '$base$path',
            data: body,
            cancelToken: cancelToken,
            options: Options(
              method: body == null ? 'GET' : 'POST',
              responseType: ResponseType.plain,
              contentType: body == null ? null : Headers.jsonContentType,
              headers: <String, String>{
                'Referer': '$base/',
                'Accept': 'application/json, text/plain, */*',
              },
            ),
          );
          final text = response.data;
          if (response.statusCode == 429 && attempt == 0) {
            // The site throttles bursts of link requests; give it a moment.
            await Future<void>.delayed(const Duration(milliseconds: 900));
            continue;
          }
          if (response.statusCode != 200 || text == null || text.isEmpty) {
            failure = const FormatException('catalogue rejected the request');
            break;
          }
          _lastBase = base;
          return CartoonyCrypto.decode(text);
        } on DioException catch (error) {
          if (CancelToken.isCancel(error)) rethrow;
          failure = error;
          break;
        } on FormatException catch (error) {
          failure = error;
          break;
        }
      }
    }
    throw failure ?? const FormatException('catalogue is unavailable');
  }

  /// Builds a page of mapped results from the full local catalogue.
  Paged<Anime> _page(List<Map<String, dynamic>> shows, int page) {
    final start = page * _pageSize;
    if (start >= shows.length) {
      return Paged<Anime>(
        items: const <Anime>[],
        page: page,
        hasMore: false,
        total: shows.length,
      );
    }
    final end = (start + _pageSize).clamp(0, shows.length);
    return Paged<Anime>(
      items: shows.sublist(start, end).map(_mapShow).toList(growable: false),
      page: page,
      hasMore: end < shows.length,
      total: shows.length,
    );
  }

  List<Map<String, dynamic>> _sorted(
    List<Map<String, dynamic>> shows,
    BrowseSort sort,
  ) {
    int compareNewest(Map<String, dynamic> a, Map<String, dynamic> b) {
      final left = DateTime.tryParse(a.str('created_at') ?? '');
      final right = DateTime.tryParse(b.str('created_at') ?? '');
      if (left == null || right == null) return 0;
      return right.compareTo(left);
    }

    final sorted = List<Map<String, dynamic>>.from(shows);
    switch (sort) {
      case BrowseSort.newest:
        sorted.sort(compareNewest);
      case BrowseSort.oldest:
        sorted.sort((a, b) => compareNewest(b, a));
      case BrowseSort.titleAsc:
        sorted.sort((a, b) => _titleOf(a).compareTo(_titleOf(b)));
      case BrowseSort.popular:
        sorted.sort(
          (a, b) =>
              (b.integer('views') ?? 0).compareTo(a.integer('views') ?? 0),
        );
      case BrowseSort.rating:
        sorted.sort(
          (a, b) => (b.dbl('rating') ?? 0).compareTo(a.dbl('rating') ?? 0),
        );
    }
    return sorted;
  }

  String _titleOf(Map<String, dynamic> show) =>
      (catalog == CartoonyCatalog.spacetoonGo
          ? show.str('name')
          : show.str('title')) ??
      '';

  List<String> _genresOf(Map<String, dynamic> show) {
    final values = <String>[
      if (catalog == CartoonyCatalog.spacetoonGo) show.str('planet_name') ?? '',
      show.str(catalog == CartoonyCatalog.spacetoonGo ? 'tags' : 'category') ??
          '',
    ];
    return values
        .expand((value) => value.split(','))
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty)
        .toSet()
        .toList(growable: false);
  }

  String? _asset(String? name, String folder) {
    if (name == null) return null;
    if (name.startsWith('http')) return name;
    return '$baseUrl/assets/img/$folder/$name';
  }

  Anime _mapShow(Map<String, dynamic> show) {
    final showId = show.integer('id');
    final animeId = showId == null ? '' : encodeId(showId);
    final title = _titleOf(show);
    final isMovie = catalog == CartoonyCatalog.spacetoonGo
        ? show.integer('is_movie') == 1
        : (show.str('category') ?? '').contains('فيلم');
    final rating = show.dbl('rating');
    final yearText = show.str('release_year') ?? '';
    final year = yearText.length >= 4
        ? int.tryParse(yearText.substring(0, 4))
        : int.tryParse(yearText);
    final poster = catalog == CartoonyCatalog.spacetoonGo
        ? show.str('cover_full_path')
        : _asset(show.str('poster_cover'), 'posters');
    final category = show.str('category');

    return Anime(
      id: animeId,
      title: title,
      posterUrl: poster,
      backdropUrl:
          (catalog == CartoonyCatalog.spacetoonGo
              ? show.str('trailer_cover_full_path')
              : _asset(show.str('poster_banner'), 'posters')) ??
          poster,
      synopsis: cleanHtml(
        catalog == CartoonyCatalog.spacetoonGo
            ? show.str('pref')
            : show.str('description'),
      ),
      genres: _genresOf(show),
      type: isMovie ? 'فيلم' : 'مسلسل',
      year: year == 0 ? null : year,
      status: catalog == CartoonyCatalog.spacetoonGo
          ? (show.integer('is_completed') == 1 ? 'مكتمل' : 'مستمر')
          : (category != null && category.contains('غير مكتمل')
                ? 'مستمر'
                : 'مكتمل'),
      rating: rating == null ? null : (rating * 2).clamp(0, 10).toDouble(),
      views: show.integer('views'),
      episodeCount: catalog == CartoonyCatalog.spacetoonGo
          ? show.integer('ep_count')
          : show.integer('episodes_count'),
      season: seasonLabelFromTitle(title),
      contentPath: animeId,
      isDubbed: (category ?? '').contains('مدبلج'),
    );
  }
}
