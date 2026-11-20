import '../../core/storage/local_store.dart';

/// Tiny key/value contract so favourites and recents can be tested without a
/// Hive box.
abstract interface class StickerPreferencesStore {
  Object? read(String key);
  Future<void> write(String key, Object value);
}

/// The project's own local storage (Hive, JSON values) behind the sticker
/// preferences contract. Nothing about stickers ever reaches Firestore.
class LocalStickerPreferencesStore implements StickerPreferencesStore {
  LocalStickerPreferencesStore(this._store);

  final LocalStore _store;

  @override
  Object? read(String key) => _store.getJson(LocalStore.settingsBox, key);

  @override
  Future<void> write(String key, Object value) =>
      _store.putJson(LocalStore.settingsBox, key, value);
}

/// Device-local favourites and recently used stickers.
///
/// Identifiers are stored, never the artwork, and the list is bounded so the
/// store stays tiny.
class StickerPreferences {
  StickerPreferences(this._store);

  final StickerPreferencesStore _store;

  static const String favoritesKey = 'stickers_favorites';
  static const String recentsKey = 'stickers_recent';
  static const int recentLimit = 12;

  List<String> get favorites => _read(favoritesKey);
  List<String> get recents => _read(recentsKey);

  Future<List<String>> toggleFavorite(String id) async {
    final next = toggleInList(favorites, id);
    await _store.write(favoritesKey, next);
    return next;
  }

  Future<List<String>> markUsed(String id) async {
    final next = withRecent(recents, id);
    await _store.write(recentsKey, next);
    return next;
  }

  List<String> _read(String key) {
    final value = _store.read(key);
    if (value is! List) return const <String>[];
    return value
        .whereType<String>()
        .where((id) => id.isNotEmpty)
        .toList(growable: false);
  }

  /// Adds an id to the end of a list, or removes it when it is already there.
  static List<String> toggleInList(List<String> ids, String id) {
    final next = <String>[...ids];
    if (!next.remove(id)) next.add(id);
    return next;
  }

  /// Puts [id] at the front of the recent list, never duplicating it, and keeps
  /// at most [limit] entries.
  static List<String> withRecent(
    List<String> ids,
    String id, {
    int limit = recentLimit,
  }) {
    final next = <String>[id];
    for (final value in ids) {
      if (value != id) next.add(value);
    }
    return next.length <= limit ? next : next.sublist(0, limit);
  }
}
