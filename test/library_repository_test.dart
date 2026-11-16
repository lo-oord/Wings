import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:wings/core/storage/local_store.dart';
import 'package:wings/data/models/anime.dart';
import 'package:wings/data/models/library.dart';
import 'package:wings/data/repositories/library_repository.dart';

void main() {
  late Directory directory;
  late LocalStore store;
  late LibraryRepository repository;

  const anime = Anime(
    id: 'Attack on Titan',
    title: 'Attack on Titan',
    posterUrl: 'https://example.com/aot.jpg',
    contentPath: 'anime_list/Attack on Titan',
  );
  const other = Anime(id: 'Bleach', title: 'Bleach');

  setUpAll(() async {
    directory = await Directory.systemTemp.createTemp('wings_test');
    store = await LocalStore.open(directory: directory.path);
  });

  setUp(() async {
    await store.clear(LocalStore.libraryBox);
    await store.clear(LocalStore.historyBox);
    await store.clear(LocalStore.searchBox);
    repository = LibraryRepository(store);
  });

  tearDownAll(() async {
    await directory.delete(recursive: true);
  });

  test('favourites are toggled and persisted', () async {
    final entry = await repository.toggleFavorite(anime);
    expect(entry.isFavorite, isTrue);
    expect(repository.isFavorite(anime.id), isTrue);
    expect(repository.entries().single.anime.title, 'Attack on Titan');

    final removed = await repository.toggleFavorite(anime);
    expect(removed.isFavorite, isFalse);
    expect(repository.isFavorite(anime.id), isFalse);
  });

  test('status changes update an existing entry', () async {
    await repository.setStatus(anime, LibraryStatus.planToWatch);
    final updated = await repository.setStatus(anime, LibraryStatus.watching);
    expect(updated.status, LibraryStatus.watching);
    expect(repository.entries(), hasLength(1));
    expect(repository.stats().watching, 1);
  });

  test('removing from the library deletes the entry', () async {
    await repository.toggleFavorite(other);
    await repository.removeFromLibrary(other.id);
    expect(repository.entryFor(other.id), isNull);
  });

  test('watch history is unique per episode and sorted by recency', () async {
    for (var episode = 1; episode <= 2; episode++) {
      await repository.saveProgress(
        WatchHistoryEntry(
          animeId: anime.id,
          animeTitle: anime.title,
          episodeId: 'ep-$episode',
          episodeNumber: episode,
          position: Duration(seconds: episode * 10),
          duration: const Duration(minutes: 24),
          updatedAt: DateTime.now(),
        ),
        completed: false,
      );
    }
    expect(repository.history(), hasLength(2));
    expect(repository.watchedEpisodeIds(anime.id), <String>{'ep-1', 'ep-2'});
    expect(repository.history().first.episodeNumber, 2);

    // Re-watching an episode must not create a duplicate record.
    await repository.saveProgress(
      WatchHistoryEntry(
        animeId: anime.id,
        animeTitle: anime.title,
        episodeId: 'ep-2',
        episodeNumber: 2,
        position: const Duration(minutes: 23),
        duration: const Duration(minutes: 24),
        updatedAt: DateTime.now(),
      ),
      completed: true,
    );
    expect(repository.history(), hasLength(2));
    expect(repository.history().first.completed, isTrue);
  });

  test('clearing history removes progress but keeps library entries', () async {
    await repository.toggleFavorite(anime);
    await repository.saveProgress(
      WatchHistoryEntry(
        animeId: anime.id,
        animeTitle: anime.title,
        episodeId: '1',
        episodeNumber: 1,
        updatedAt: DateTime.now(),
      ),
      completed: false,
    );
    await repository.clearHistory();
    expect(repository.history(), isEmpty);
    expect(repository.entries(), hasLength(1));
  });

  test('search history is de-duplicated and capped', () async {
    await repository.addSearchQuery('One Piece');
    await repository.addSearchQuery('Naruto');
    await repository.addSearchQuery('one piece');
    expect(repository.searchHistory().first, 'one piece');
    expect(repository.searchHistory(), hasLength(2));

    await repository.removeSearchQuery('Naruto');
    expect(repository.searchHistory(), <String>['one piece']);

    await repository.clearSearchHistory();
    expect(repository.searchHistory(), isEmpty);
  });

  test('library statistics reflect stored entries', () async {
    await repository.setStatus(anime, LibraryStatus.completed);
    await repository.toggleFavorite(other);
    final stats = repository.stats();
    expect(stats.completed, 1);
    expect(stats.favorites, 1);
    expect(stats.watching, 0);
  });
}
