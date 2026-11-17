// Live check for the Wings catalogue playback path.
//
// Run explicitly (it needs network access):
//   flutter test tool/live_wings_playback_test.dart
//
// It is intentionally outside `test/` so the normal suite stays offline.
// ignore_for_file: avoid_print
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wings/core/constants/network_constants.dart';
import 'package:wings/data/sources/algolia_client.dart';
import 'package:wings/data/sources/firestore_client.dart';
import 'package:wings/data/sources/server_resolver.dart';
import 'package:wings/data/sources/wings_catalogue_source.dart';

void main() {
  test('wings episodes expose playable servers', () async {
    final dio = Dio(
      BaseOptions(
        connectTimeout: const Duration(seconds: 15),
        receiveTimeout: const Duration(seconds: 25),
        headers: <String, String>{'User-Agent': kBrowserUserAgent},
        validateStatus: (status) => status != null && status < 500,
      ),
    );
    addTearDown(dio.close);

    final firestore = FirestoreClient(dio);
    final source = WingsCatalogueSource(
      index: SearchIndexClient(dio, firestore),
      firestore: firestore,
    );
    final resolver = ServerResolver(dio);

    var sampled = 0;
    var withServers = 0;
    var playable = 0;

    for (final query in <String>[
      'Jujutsu Kaisen 2nd Season',
      'One Piece',
      'Black Clover',
    ]) {
      final results = await source.search(query);
      if (results.items.isEmpty) continue;
      final anime = results.items.first;
      final episodes = await source.episodes(anime);
      if (episodes.isEmpty) {
        print('${anime.title}: no episodes');
        continue;
      }
      final episode = episodes[episodes.length ~/ 2];
      final servers = await source.servers(anime, episode);
      sampled++;
      if (servers.isNotEmpty) withServers++;
      var resolvedHere = 0;
      for (final server in servers.where((s) => !s.requiresBrowser).take(4)) {
        if (await resolver.resolve(server) != null) resolvedHere++;
      }
      if (resolvedHere > 0) playable++;
      print(
        '${anime.title} #${episode.number}: servers=${servers.length} '
        'resolved=$resolvedHere path=${anime.contentPath}',
      );
    }

    expect(sampled, greaterThan(0));
    expect(withServers, sampled, reason: 'every sampled episode has servers');
    expect(playable, greaterThan(0), reason: 'at least one link resolves');
  }, timeout: const Timeout(Duration(minutes: 5)));
}
