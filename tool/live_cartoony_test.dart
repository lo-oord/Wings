// Live end-to-end check of the Cartoony / Carateen source.
//
// Run explicitly (it needs network access):
//   flutter test tool/live_cartoony_test.dart
//
// It is intentionally outside `test/` so the normal suite stays offline.
// ignore_for_file: avoid_print
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wings/core/constants/network_constants.dart';
import 'package:wings/data/models/anime.dart';
import 'package:wings/data/sources/cartoony_source.dart';

void main() {
  test(
    'cartoony catalogues return searchable shows and playable streams',
    () async {
      final dio = Dio(
        BaseOptions(
          connectTimeout: const Duration(seconds: 15),
          receiveTimeout: const Duration(seconds: 40),
          headers: <String, String>{'User-Agent': kBrowserUserAgent},
          validateStatus: (status) => status != null && status < 500,
        ),
      );
      addTearDown(dio.close);

      for (final catalog in CartoonyCatalog.values) {
        final source = CartoonySource(dio, catalog: catalog);

        final browse = await source.browse(const BrowseQuery());
        expect(browse.items, isNotEmpty, reason: '${source.id} browse');
        print('${source.id}: browse ${browse.items.length}/${browse.total}');

        final query = catalog == CartoonyCatalog.classic ? 'كونان' : 'كونان';
        final search = await source.search(query);
        expect(search.items, isNotEmpty, reason: '${source.id} search');
        print('${source.id}: search "$query" -> ${search.items.first.title}');

        final anime = search.items.first;
        final episodes = await source.episodes(anime);
        expect(episodes, isNotEmpty, reason: '${source.id} episodes');
        print('${source.id}: episodes ${episodes.length}');

        final servers = await source.servers(anime, episodes.first);
        expect(servers, isNotEmpty, reason: '${source.id} servers');
        expect(servers.first.url, startsWith('http'));
        print('${source.id}: stream ${servers.first.url}');

        final genres = await source.genres();
        expect(genres, isNotEmpty, reason: '${source.id} genres');
        print('${source.id}: genres ${genres.length}');
      }
    },
    timeout: const Timeout(Duration(minutes: 4)),
  );
}
