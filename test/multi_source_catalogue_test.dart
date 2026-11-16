import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wings/data/models/anime.dart';
import 'package:wings/data/sources/anime_source.dart';
import 'package:wings/data/sources/cartoony_source.dart';
import 'package:wings/data/sources/multi_source_catalogue.dart';

class _StubSource implements AnimeSource {
  _StubSource({
    required this.id,
    this.items = const <Anime>[],
    this.latest = const <LatestEpisode>[],
    this.failing = false,
  });

  @override
  final String id;
  final List<Anime> items;
  final List<LatestEpisode> latest;
  final bool failing;

  Never _failure() => throw StateError('$id is unavailable');

  @override
  Future<Paged<Anime>> search(
    String text, {
    int page = 0,
    CancelToken? cancelToken,
  }) async {
    if (failing) _failure();
    return Paged<Anime>(items: items, page: page, hasMore: false);
  }

  @override
  Future<Paged<Anime>> browse(
    BrowseQuery query, {
    int page = 0,
    CancelToken? cancelToken,
  }) async {
    if (failing) _failure();
    return Paged<Anime>(items: items, page: page, hasMore: false);
  }

  @override
  Future<Paged<LatestEpisode>> latestEpisodes({
    int page = 0,
    CancelToken? cancelToken,
  }) async {
    if (failing) _failure();
    return Paged<LatestEpisode>(items: latest, page: page, hasMore: false);
  }

  @override
  Future<List<Genre>> genres({CancelToken? cancelToken}) async {
    if (failing) _failure();
    return const <Genre>[Genre(name: 'أكشن', count: 2)];
  }

  @override
  Future<Anime> animeById(String animeId, {CancelToken? cancelToken}) async =>
      Anime(id: animeId, title: '$id:$animeId');

  @override
  Future<List<AnimeEpisode>> episodes(
    Anime anime, {
    CancelToken? cancelToken,
  }) async => <AnimeEpisode>[
    AnimeEpisode(id: '1', number: 1, animeId: anime.id),
  ];

  @override
  Future<List<StreamServer>> servers(
    Anime anime,
    AnimeEpisode episode, {
    CancelToken? cancelToken,
  }) async => <StreamServer>[
    StreamServer(
      name: id,
      url: 'https://example.com/$id.m3u8',
      quality: 'HD',
      flavor: ServerFlavor.direct,
    ),
  ];

  @override
  Future<List<Anime>> related(Anime anime, {CancelToken? cancelToken}) async =>
      const <Anime>[];
}

const String _cartoonyShows =
    '[{"id": 101, "name": "المحقق كونان", "cover_full_path": '
    '"https://cdn.example.com/conan.jpg", "pref": "قصة", "ep_count": 3, '
    '"is_movie": 0, "tags": "غموض"}]';

class _FakeAdapter implements HttpClientAdapter {
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async => ResponseBody.fromString(_cartoonyShows, 200);

  @override
  void close({bool force = false}) {}
}

void main() {
  final partTwo = const Anime(id: 'a2', title: 'كابتن ماجد - الجزء الثاني');
  final partOne = const Anime(id: 'b1', title: 'كابتن ماجد - الجزء الأول');
  final other = const Anime(id: 'c1', title: 'عدنان ولينا');

  group('MultiSourceCatalogue', () {
    test('merges search results and keeps seasons adjacent', () async {
      final catalogue = MultiSourceCatalogue(<AnimeSource>[
        _StubSource(id: 'main', items: <Anime>[partTwo, other]),
        _StubSource(id: 'extra', items: <Anime>[partOne]),
      ]);

      final result = await catalogue.search('كابتن');
      expect(result.items.map((anime) => anime.id), <String>['b1', 'a2', 'c1']);
    });

    test('a failing source does not hide the others', () async {
      final catalogue = MultiSourceCatalogue(<AnimeSource>[
        _StubSource(id: 'broken', failing: true),
        _StubSource(id: 'extra', items: <Anime>[other]),
      ]);

      final search = await catalogue.search('ولينا');
      expect(search.items.single.id, 'c1');

      final browse = await catalogue.browse(const BrowseQuery());
      expect(browse.items.single.id, 'c1');

      final genres = await catalogue.genres();
      expect(genres.single.name, 'أكشن');
    });

    test('merges the latest feed and drops duplicates', () async {
      const anime = Anime(id: 'x', title: 'عمل');
      const episode = AnimeEpisode(id: '1', number: 1, animeId: 'x');
      const item = LatestEpisode(anime: anime, episode: episode);
      final catalogue = MultiSourceCatalogue(<AnimeSource>[
        _StubSource(id: 'main', latest: const <LatestEpisode>[item]),
        _StubSource(id: 'extra', latest: const <LatestEpisode>[item]),
      ]);

      final latest = await catalogue.latestEpisodes();
      expect(latest.items, hasLength(1));
    });

    test('routes identifiers back to the source that owns them', () async {
      final dio = Dio(BaseOptions(validateStatus: (status) => status != null));
      dio.httpClientAdapter = _FakeAdapter();
      final cartoony = CartoonySource(
        dio,
        catalog: CartoonyCatalog.spacetoonGo,
      );
      final catalogue = MultiSourceCatalogue(<AnimeSource>[
        _StubSource(id: 'main'),
        cartoony,
      ]);

      final anime = await catalogue.animeById('csp:101');
      expect(anime.title, 'المحقق كونان');

      final other = await catalogue.animeById('wings-id');
      expect(other.title, 'main:wings-id');
    });
  });
}
