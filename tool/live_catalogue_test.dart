// Live end-to-end check of the catalogue pipeline against the public indexes.
//
// Run explicitly (it needs network access):
//   flutter test tool/live_catalogue_test.dart
//
// It is intentionally outside `test/` so the normal suite stays offline.
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wings/core/constants/network_constants.dart';
import 'package:wings/data/models/anime.dart';
import 'package:wings/data/sources/algolia_client.dart';
import 'package:wings/data/sources/firestore_client.dart';
import 'package:wings/data/sources/server_resolver.dart';
import 'package:wings/data/sources/wings_catalogue_source.dart';

void main() {
  test('catalogue pipeline returns real data end to end', () async {
    final dio = Dio(
      BaseOptions(
        connectTimeout: const Duration(seconds: 15),
        receiveTimeout: const Duration(seconds: 30),
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

    final latest = await source.latestEpisodes();
    expect(latest.items, isNotEmpty, reason: 'latest feed');
    // ignore: avoid_print
    print(
      'latest: ${latest.items.take(3).map((e) => '${e.anime.title} #${e.episode.number}').join(' | ')}',
    );

    final newest = await source.browse(
      const BrowseQuery(sort: BrowseSort.newest),
    );
    expect(newest.items, isNotEmpty);
    final anime = newest.items.first;
    // ignore: avoid_print
    print(
      'browse: ${anime.title} (${anime.year}) rating=${anime.rating} genres=${anime.genres}',
    );

    final genres = await source.genres();
    expect(genres.length, greaterThan(20), reason: 'genre facet');
    // ignore: avoid_print
    print('genres: ${genres.length}');

    final search = await source.search('one piece');
    expect(search.items, isNotEmpty, reason: 'search');
    // ignore: avoid_print
    print(
      'search: ${search.items.first.title} / ${search.items.length} results',
    );

    final details = await source.animeById(anime.id);
    expect(details.title, isNotEmpty);
    expect(details.synopsis, isNotNull, reason: 'details synopsis');

    // Very recently added titles occasionally have no episode summary yet;
    // walk the newest page until a title with real episodes is found.
    Anime? populated;
    var episodes = const <AnimeEpisode>[];
    for (final candidate in newest.items.take(6)) {
      final list = await source.episodes(candidate);
      if (list.isNotEmpty) {
        populated = candidate;
        episodes = list;
        break;
      }
    }
    expect(episodes, isNotEmpty, reason: 'episode list');
    // ignore: avoid_print
    print('episodes: ${episodes.length} for ${populated!.title}');

    final servers = await source.servers(populated, episodes.first);
    expect(servers, isNotEmpty, reason: 'server list');
    // ignore: avoid_print
    print(
      'servers: ${servers.map((s) => '${s.name}:${s.quality}').join(', ')}',
    );

    final resolver = ServerResolver(dio);
    ResolvedStream? playable;
    for (final server in servers.where((s) => !s.requiresBrowser)) {
      playable = await resolver.resolve(server);
      if (playable != null) break;
    }
    expect(
      playable,
      isNotNull,
      reason: 'at least one stream resolves to a direct media URL',
    );
    // ignore: avoid_print
    print('resolved: ${Uri.parse(playable!.url).host} ${playable.quality}');
  }, timeout: const Timeout(Duration(minutes: 4)));
}
