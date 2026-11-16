import '../../core/storage/local_store.dart';
import '../models/anime.dart';
import '../models/library.dart';

class LibraryStats {
  const LibraryStats({
    required this.favorites,
    required this.completed,
    required this.watching,
    required this.planToWatch,
    required this.downloads,
    required this.historyCount,
  });

  final int favorites;
  final int completed;
  final int watching;
  final int planToWatch;
  final int downloads;
  final int historyCount;
}

/// Local-first library: favourites, statuses, watch history and search history.
class LibraryRepository {
  LibraryRepository(this._store);

  final LocalStore _store;

  static const int _historyLimit = 80;
  static const int _searchLimit = 12;

  List<LibraryEntry> entries() {
    final list = _store
        .valuesAsJson(LocalStore.libraryBox)
        .map(LibraryEntry.fromJson)
        .toList(growable: false);
    return list.toList()..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
  }

  LibraryEntry? entryFor(String animeId) {
    final raw = _store.getJson(LocalStore.libraryBox, animeId);
    if (raw is! Map) return null;
    return LibraryEntry.fromJson(raw.cast<String, dynamic>());
  }

  bool isFavorite(String animeId) => entryFor(animeId)?.isFavorite ?? false;

  Future<LibraryEntry> toggleFavorite(Anime anime) async {
    final existing = entryFor(anime.id);
    final now = DateTime.now();
    final entry = existing != null
        ? existing.copyWith(isFavorite: !existing.isFavorite, updatedAt: now)
        : LibraryEntry(
            anime: anime,
            status: LibraryStatus.planToWatch,
            isFavorite: true,
            addedAt: now,
            updatedAt: now,
          );
    await _save(entry);
    return entry;
  }

  Future<LibraryEntry> setStatus(Anime anime, LibraryStatus status) async {
    final existing = entryFor(anime.id);
    final now = DateTime.now();
    final entry = existing != null
        ? existing.copyWith(status: status, updatedAt: now)
        : LibraryEntry(
            anime: anime,
            status: status,
            isFavorite: false,
            addedAt: now,
            updatedAt: now,
          );
    await _save(entry);
    return entry;
  }

  Future<void> _save(LibraryEntry entry) =>
      _store.putJson(LocalStore.libraryBox, entry.anime.id, entry.toJson());

  Future<void> removeFromLibrary(String animeId) =>
      _store.delete(LocalStore.libraryBox, animeId);

  List<WatchHistoryEntry> history() {
    final list = _store
        .valuesAsJson(LocalStore.historyBox)
        .map(WatchHistoryEntry.fromJson)
        .toList(growable: false);
    return list.toList()..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
  }

  WatchHistoryEntry? historyFor(String animeId, String episodeId) {
    final raw = _store.getJson(LocalStore.historyBox, '$animeId::$episodeId');
    if (raw is! Map) return null;
    return WatchHistoryEntry.fromJson(raw.cast<String, dynamic>());
  }

  Set<String> watchedEpisodeIds(String animeId) {
    final ids = <String>{};
    for (final entry in history()) {
      if (entry.animeId == animeId) ids.add(entry.episodeId);
    }
    return ids;
  }

  /// Stores playback progress, pruning the oldest entries beyond the limit.
  Future<void> saveProgress(
    WatchHistoryEntry entry, {
    required bool completed,
  }) async {
    final updated = entry.copyWith(
      completed: completed,
      updatedAt: DateTime.now(),
    );
    await _store.putJson(LocalStore.historyBox, updated.key, updated.toJson());

    final all = history();
    if (all.length > _historyLimit) {
      for (final stale in all.sublist(_historyLimit)) {
        await _store.delete(LocalStore.historyBox, stale.key);
      }
    }
  }

  Future<void> clearHistory() => _store.clear(LocalStore.historyBox);

  Future<void> removeHistoryEntry(String key) =>
      _store.delete(LocalStore.historyBox, key);

  List<String> searchHistory() {
    final raw = _store.getJson(LocalStore.searchBox, 'recent');
    if (raw is! List) return const [];
    return raw
        .map((e) => e.toString())
        .where((e) => e.trim().isNotEmpty)
        .toList(growable: false);
  }

  Future<void> addSearchQuery(String query) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return;
    final current = searchHistory().toList()
      ..removeWhere((item) => item.toLowerCase() == trimmed.toLowerCase());
    current.insert(0, trimmed);
    await _store.putJson(
      LocalStore.searchBox,
      'recent',
      current.take(_searchLimit).toList(growable: false),
    );
  }

  Future<void> removeSearchQuery(String query) async {
    final current = searchHistory().toList()..remove(query);
    await _store.putJson(LocalStore.searchBox, 'recent', current);
  }

  Future<void> clearSearchHistory() =>
      _store.putJson(LocalStore.searchBox, 'recent', const <String>[]);

  LibraryStats stats({int downloads = 0}) {
    final all = entries();
    final historyEntries = history();
    return LibraryStats(
      favorites: all.where((e) => e.isFavorite).length,
      completed: all.where((e) => e.status == LibraryStatus.completed).length,
      watching: all.where((e) => e.status == LibraryStatus.watching).length,
      planToWatch: all
          .where((e) => e.status == LibraryStatus.planToWatch)
          .length,
      downloads: downloads,
      historyCount: historyEntries.length,
    );
  }
}
