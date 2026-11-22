import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wings/core/storage/local_store.dart';
import 'package:wings/data/models/anime.dart';
import 'package:wings/data/repositories/anime_repository.dart';
import 'package:wings/data/sources/anime_source.dart';
import 'package:wings/data/sources/server_resolver.dart';

/// Counts how many real requests reach the source so duplicate work is visible.
class _CountingSource implements AnimeSource {
  int browseCalls = 0;
  int latestCalls = 0;

  @override
  String get id => 'test';

  @override
  Future<Paged<Anime>> browse(
    BrowseQuery query, {
    int page = 0,
    CancelToken? cancelToken,
  }) async {
    browseCalls++;
    await Future<void>.delayed(const Duration(milliseconds: 40));
    return Paged<Anime>(
      items: const <Anime>[Anime(id: 'a1', title: 'One Piece')],
      page: page,
      hasMore: false,
    );
  }

  @override
  Future<Paged<LatestEpisode>> latestEpisodes({
    int page = 0,
    CancelToken? cancelToken,
  }) async {
    latestCalls++;
    await Future<void>.delayed(const Duration(milliseconds: 40));
    return Paged<LatestEpisode>.empty();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late Directory directory;
  late LocalStore store;
  late _CountingSource source;
  late AnimeRepository repository;

  setUpAll(() async {
    directory = await Directory.systemTemp.createTemp('wings_dedupe');
    store = await LocalStore.open(directory: directory.path);
  });

  setUp(() async {
    await store.clear(LocalStore.cacheBox);
    source = _CountingSource();
    repository = AnimeRepository(source, ServerResolver(Dio()), store);
  });

  tearDownAll(() async {
    await directory.delete(recursive: true);
  });

  test('two identical page requests share one network call', () async {
    const query = BrowseQuery(sort: BrowseSort.newest);
    final results = await Future.wait(<Future<Paged<Anime>>>[
      repository.browse(query),
      repository.browse(query),
    ]);
    expect(source.browseCalls, 1);
    expect(results.first.items.single.title, 'One Piece');
    expect(results.last.items.single.title, 'One Piece');
  });

  test('a cancelled caller is never shared with another screen', () async {
    const query = BrowseQuery(sort: BrowseSort.popular);
    await Future.wait(<Future<Paged<Anime>>>[
      repository.browse(query, cancelToken: CancelToken()),
      repository.browse(query, cancelToken: CancelToken()),
    ]);
    expect(source.browseCalls, 2);
  });

  test('the next request after completion reaches the source again', () async {
    const query = BrowseQuery(sort: BrowseSort.rating);
    await repository.browse(query);
    await repository.browse(query);
    expect(source.browseCalls, 2);
  });

  test('different pages are not merged', () async {
    await Future.wait(<Future<Paged<Anime>>>[
      repository.browse(const BrowseQuery(), page: 0),
      repository.browse(const BrowseQuery(), page: 1),
    ]);
    expect(source.browseCalls, 2);
  });
}
