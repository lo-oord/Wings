// ignore_for_file: avoid_print
import 'package:flutter_test/flutter_test.dart';
import 'package:dio/dio.dart';
import 'package:wings/core/constants/network_constants.dart';
import 'package:wings/data/models/anime.dart';
import 'package:wings/data/sources/algolia_client.dart';
import 'package:wings/data/sources/firestore_client.dart';
import 'package:wings/data/sources/wings_catalogue_source.dart';

void main() {
  test('episode coverage across catalogue', () async {
    final dio = Dio(
      BaseOptions(
        validateStatus: (s) => s != null && s < 500,
        headers: {'User-Agent': kBrowserUserAgent},
      ),
    );
    final fs = FirestoreClient(dio);
    final src = WingsCatalogueSource(
      index: SearchIndexClient(dio, fs),
      firestore: fs,
    );
    final newest = await src.browse(const BrowseQuery(sort: BrowseSort.newest));
    var withEpisodes = 0;
    final missing = <String>[];
    for (final anime in newest.items.take(12)) {
      final eps = await src.episodes(anime);
      if (eps.isEmpty) {
        missing.add(anime.title);
      } else {
        withEpisodes++;
        print('${anime.title}: ${eps.length} eps, first #${eps.first.number}');
      }
    }
    print('covered $withEpisodes/12, missing=$missing');
    expect(withEpisodes, greaterThanOrEqualTo(9));
    dio.close();
  }, timeout: const Timeout(Duration(minutes: 4)));
}
