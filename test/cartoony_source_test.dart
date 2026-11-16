import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wings/data/models/anime.dart';
import 'package:wings/data/sources/cartoony_source.dart';

const String _spShows = '''
[
  {"id": 101, "name": "المحقق كونان (موسم 1)", "planet_name": "أفلام",
   "cover_full_path": "https://cdn.example.com/conan.jpg", "pref": "قصة",
   "ep_count": 2, "is_movie": 0, "is_completed": 1, "tags": "غموض, مغامرات",
   "rating": 4.2, "views": 6400, "created_at": "2026-07-25T15:14:55+00:00"},
  {"id": 102, "name": "Gundam SEED", "planet_name": "أكشن",
   "cover_full_path": "https://cdn.example.com/gundam.jpg", "pref": "روبوتات",
   "ep_count": 1, "is_movie": 1, "is_completed": 0, "tags": "ميكا",
   "rating": 3.5, "views": 120, "created_at": "2026-01-01T00:00:00+00:00"}
]
''';

const String _spEpisodes = '''
[
  {"id": 11, "number": 1, "pref": "البداية", "season": "آرك الأول",
   "cover_full_path": "https://cdn.example.com/e1.jpg"},
  {"id": 12, "number": 2, "pref": "المطاردة", "season": "آرك الأول",
   "cover_full_path": "https://cdn.example.com/e2.jpg"}
]
''';

const String _spRecent = '''
[
  {"id": 900, "tv_series_id": 101, "number": 7, "pref": "الهروب الصامت",
   "cover_full_path": "https://cdn.example.com/e7.jpg", "name": "المحقق كونان"}
]
''';

const String _tgShows = '''
[
  {"id": 5, "title": "المعركة الكبرى", "category": "فيلم مترجم",
   "poster_cover": "6_cover.webp", "poster_banner": "8_banner.webp",
   "description": "<b>وصف</b>", "release_year": "1975",
   "episodes_count": "1", "quality": "FULL HD", "views": 1008,
   "rating": 3.57, "created_at": "2024-08-31T15:39:43+00:00"}
]
''';

const String _tgEpisodes = '''
[
  {"id": 52, "title": "الحلقة الأولى", "order_id": 1,
   "thumbnail": "52_thumbnail.webp"}
]
''';

class _FakeAdapter implements HttpClientAdapter {
  _FakeAdapter(this.routes);

  final Map<String, String> routes;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final body = routes[options.uri.path];
    if (body == null) {
      return ResponseBody.fromString(
        '{"message":"Access denied"}',
        403,
        headers: <String, List<String>>{
          Headers.contentTypeHeader: <String>[Headers.jsonContentType],
        },
      );
    }
    return ResponseBody.fromString(
      body,
      200,
      headers: <String, List<String>>{
        Headers.contentTypeHeader: <String>[Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

Dio _dio(Map<String, String> routes) {
  final dio = Dio(
    BaseOptions(validateStatus: (status) => status != null && status < 500),
  );
  dio.httpClientAdapter = _FakeAdapter(routes);
  return dio;
}

void main() {
  group('CartoonySource (سبيستون غو)', () {
    late CartoonySource source;

    setUp(() {
      source = CartoonySource(
        _dio(<String, String>{
          '/api/sp/tvshows': _spShows,
          '/api/sp/episodes': _spEpisodes,
          '/api/sp/recentEpisodes': _spRecent,
          '/api/sp/episode/link': '{"link":"https://cdn.example.com/s/1.m3u8"}',
        }),
        catalog: CartoonyCatalog.spacetoonGo,
      );
    });

    test('exposes a stable identifier per catalogue', () {
      expect(source.id, 'cartoony-sp');
      expect(source.owns('csp:101'), isTrue);
      expect(source.owns('ctg:101'), isFalse);
    });

    test('search returns real shows', () async {
      final result = await source.search('كونان');
      expect(result.items, hasLength(1));
      expect(result.items.first.id, 'csp:101');
      expect(result.items.first.type, 'مسلسل');
      expect(result.items.first.rating, closeTo(8.4, 0.001));
      expect(result.items.first.posterUrl, 'https://cdn.example.com/conan.jpg');
    });

    test('browse filters by the published genre', () async {
      final result = await source.browse(
        const BrowseQuery(genre: 'أفلام', sort: BrowseSort.popular),
      );
      expect(result.items.map((anime) => anime.id), <String>['csp:101']);
    });

    test('details, episodes and streams come from the endpoints', () async {
      final anime = await source.animeById('csp:101');
      expect(anime.title, contains('كونان'));
      expect(anime.season, isNotNull);

      final episodes = await source.episodes(anime);
      expect(episodes, hasLength(2));
      expect(episodes.first.number, 1);
      expect(episodes.first.title, contains('آرك الأول'));

      final servers = await source.servers(anime, episodes.first);
      expect(servers, hasLength(1));
      expect(servers.first.url, 'https://cdn.example.com/s/1.m3u8');
      expect(servers.first.flavor, ServerFlavor.direct);
      expect(servers.first.requiresBrowser, isFalse);
    });

    test('latest feed carries the anime context', () async {
      final latest = await source.latestEpisodes();
      expect(latest.items, hasLength(1));
      expect(latest.items.first.anime.id, 'csp:101');
      expect(latest.items.first.episode.number, 7);
    });
  });

  group('CartoonySource (كرتون أيام زمان)', () {
    late CartoonySource source;

    setUp(() {
      source = CartoonySource(
        _dio(<String, String>{
          '/api/tvshows': _tgShows,
          '/api/episodes': _tgEpisodes,
          '/api/episode': '{"streamUrl":"https://cdn.example.com/tg/1.m3u8"}',
        }),
        catalog: CartoonyCatalog.classic,
      );
    });

    test('maps poster assets and stream links', () async {
      final result = await source.search('المعركة');
      expect(result.items, hasLength(1));
      final anime = result.items.first;
      expect(anime.id, 'ctg:5');
      expect(
        anime.posterUrl,
        'https://cartoony.net/assets/img/posters/6_cover.webp',
      );

      final episodes = await source.episodes(anime);
      expect(episodes, hasLength(1));
      expect(episodes.first.number, 1);

      final servers = await source.servers(anime, episodes.first);
      expect(servers.first.url, 'https://cdn.example.com/tg/1.m3u8');
      expect(servers.first.quality, 'FULL HD');
    });

    test('has no recent-episode feed', () async {
      final latest = await source.latestEpisodes();
      expect(latest.items, isEmpty);
    });
  });
}
