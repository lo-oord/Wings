import 'package:cloud_firestore/cloud_firestore.dart';

import '../../core/storage/local_store.dart';
import '../models/library.dart';
import '../repositories/library_repository.dart';
import '../repositories/settings_repository.dart';

/// Synchronizes the account-owned slice of the app across devices.
///
/// Synchronized: library entries (favourites, statuses, watched counts), watch
/// history and progress, saved episodes (**حلقاتي**), recent searches and
/// account-level preferences. Device-only data (downloads and their files,
/// notification setup, theme, onboarding state) never leaves the device.
///
/// Conflict rule: last-writer-wins on each record's `updatedAt`, except that a
/// watched episode can never become unwatched and the furthest playback
/// position always wins. Pulls are incremental, so a small change never
/// re-downloads the whole library.
class CloudSyncService {
  CloudSyncService(this._db, this._store, this._library, this._settings);

  final FirebaseFirestore _db;
  final LocalStore _store;
  final LibraryRepository _library;
  final SettingsRepository _settings;

  static const String _accountKey = 'sync_account_uid';

  /// Firestore batches accept 500 writes; keeping chunks smaller leaves room
  /// for the extra documents a migration may add.
  static const int _chunkSize = 400;

  CollectionReference<Map<String, dynamic>> _libraryRef(String uid) =>
      _db.collection('users').doc(uid).collection('library');

  CollectionReference<Map<String, dynamic>> _historyRef(String uid) =>
      _db.collection('users').doc(uid).collection('history');

  CollectionReference<Map<String, dynamic>> _episodesRef(String uid) =>
      _db.collection('users').doc(uid).collection('episodes');

  DocumentReference<Map<String, dynamic>> _searchRef(String uid) =>
      _db.collection('users').doc(uid).collection('search').doc('recent');

  DocumentReference<Map<String, dynamic>> _settingsRef(String uid) =>
      _db.collection('users').doc(uid).collection('settings').doc('account');

  String get _accountUid =>
      _store.getString(LocalStore.settingsBox, _accountKey) ?? '';

  bool _migrated(String uid) =>
      _store.getString(LocalStore.settingsBox, 'sync_migrated_$uid') == '1';

  /// Called whenever an authenticated account becomes active.
  ///
  /// * Same account as last time: pull incremental changes and push anything
  ///   that exists only on this device.
  /// * First link: merge both directions, never discarding local guest data and
  ///   never overwriting a newer record from another device.
  /// * Different account: wipe the previous account's local data first, so one
  ///   user's library can never be shown or pushed to another account.
  Future<void> attach(String uid) async {
    final previous = _accountUid;
    if (previous.isNotEmpty && previous != uid) {
      await _library.clearAccountData();
      await _store.delete(LocalStore.settingsBox, 'sync_last_pull_$previous');
    }
    if (!_migrated(uid)) {
      await pull(uid, full: true);
      await _pushLocalOnly(uid);
      await pullSearch(uid);
      await pushSettings(uid);
      await _store.setString(LocalStore.settingsBox, 'sync_migrated_$uid', '1');
    } else {
      await pull(uid);
    }
    await _store.setString(LocalStore.settingsBox, _accountKey, uid);
    await _store.setString(
      LocalStore.settingsBox,
      'sync_last_at_$uid',
      DateTime.now().toIso8601String(),
    );
  }

  /// Called on sign-out or account removal.
  Future<void> detach({bool clearSettings = false}) async {
    await _library.clearAccountData();
    if (clearSettings) {
      await _store.delete(LocalStore.settingsBox, _accountKey);
    }
  }

  /// The timestamp of the last successful sync, used by the settings screen.
  DateTime? lastSyncAt(String uid) {
    final raw = _store.getString(LocalStore.settingsBox, 'sync_last_at_$uid');
    return raw == null ? null : DateTime.tryParse(raw);
  }

  Future<void> pushEntry(String uid, LibraryEntry entry) =>
      _libraryRef(uid)
          .doc(entry.anime.id)
          .set(_entryMap(entry), SetOptions(merge: true));

  Future<void> pushHistory(String uid, WatchHistoryEntry entry) =>
      _historyRef(uid)
          .doc(_historyId(entry))
          .set(_historyMap(entry), SetOptions(merge: true));

  Future<void> deleteHistory(String uid, String historyId) =>
      _historyRef(uid).doc(historyId).delete();

  Future<void> deleteEntry(String uid, String animeId) =>
      _libraryRef(uid).doc(animeId).delete();

  Future<void> pushSavedEpisode(String uid, SavedEpisode episode) =>
      _episodesRef(uid)
          .doc(episode.key)
          .set(_savedEpisodeMap(episode), SetOptions(merge: true));

  Future<void> deleteSavedEpisode(String uid, String episodeKey) =>
      _episodesRef(uid).doc(episodeKey).delete();

  /// Pushes the recent searches as one small document.
  Future<void> pushSearch(String uid, [List<String>? items]) async {
    final searches = items ?? _library.searchHistory();
    await _searchRef(uid).set(<String, dynamic>{
      'items': searches.take(12).toList(growable: false),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  /// Account-level preferences only.
  Future<void> pushSettings(String uid) async {
    final settings = _settings.load();
    await _settingsRef(uid).set(<String, dynamic>{
      'localeCode': settings.localeCode,
      'autoplayNext': settings.autoplayNext,
      'rememberPosition': settings.rememberPosition,
      'playbackSpeed': settings.playbackSpeed,
      'preferredQuality': settings.preferredQuality,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  /// Applies remote preferences locally without touching device-only values.
  Future<AppSettings?> pullSettings(String uid) async {
    final snapshot = await _settingsRef(uid).get();
    final data = snapshot.data();
    if (!snapshot.exists || data == null) return null;
    final current = _settings.load();
    final merged = current.copyWith(
      localeCode: data['localeCode'] as String?,
      autoplayNext: data['autoplayNext'] as bool?,
      rememberPosition: data['rememberPosition'] as bool?,
      playbackSpeed: (data['playbackSpeed'] as num?)?.toDouble(),
      preferredQuality: data['preferredQuality'] as String?,
    );
    await _settings.save(merged);
    return merged;
  }

  /// Merges the cloud copy of the recent searches with the local list. The
  /// merged order keeps the newest entries of both devices and is written back
  /// so every device converges on the same list.
  Future<void> pullSearch(String uid) async {
    final snapshot = await _searchRef(uid).get();
    final data = snapshot.data();
    if (!snapshot.exists || data == null) {
      await pushSearch(uid);
      return;
    }
    final remote = (data['items'] as List?)
        ?.map((item) => item.toString())
        .where((item) => item.trim().isNotEmpty)
        .toList(growable: false);
    if (remote == null) return;
    final local = _library.searchHistory();
    final merged = <String>[];
    final seen = <String>{};
    for (final item in <String>[...remote, ...local]) {
      if (seen.add(item.toLowerCase())) merged.add(item);
      if (merged.length >= 12) break;
    }
    await _library.replaceSearchHistory(merged);
    if (merged.join('|') != remote.join('|')) {
      await pushSearch(uid, merged);
    }
  }

  /// Pulls only records changed since the previous pull for this account.
  ///
  /// [full] ignores the stored cursor and reconciles every document, which is
  /// what the first link of an account needs.
  Future<void> pull(String uid, {bool full = false}) async {
    final raw = _store.getString(LocalStore.settingsBox, 'sync_last_pull_$uid');
    final since = full ? null : (raw == null ? null : DateTime.tryParse(raw));
    final startedAt = DateTime.now();

    final libraryQuery = since == null
        ? _libraryRef(uid)
        : _libraryRef(uid)
              .where('updatedAt', isGreaterThan: Timestamp.fromDate(since));
    for (final doc in (await libraryQuery.get()).docs) {
      final data = doc.data();
      final entry = _entryFromMap(doc.id, data);
      if (entry == null) continue;
      final local = _library.entryFor(doc.id);
      if (local == null || entry.updatedAt.isAfter(local.updatedAt)) {
        await _library.upsertEntry(entry);
      } else if (local.updatedAt.isAfter(entry.updatedAt)) {
        await pushEntry(uid, local);
      }
    }

    final historyQuery = since == null
        ? _historyRef(uid)
        : _historyRef(uid)
              .where('updatedAt', isGreaterThan: Timestamp.fromDate(since));
    for (final doc in (await historyQuery.get()).docs) {
      final item = _historyFromMap(doc.data());
      if (item == null) continue;
      final local = _library.historyFor(item.animeId, item.episodeId);
      if (local == null || item.updatedAt.isAfter(local.updatedAt)) {
        await _library.upsertHistory(item);
      } else {
        // Watched state is sticky: a newer local record is pushed, and an
        // older remote one still cannot un-watch the episode locally.
        await _library.upsertHistory(item);
        if (local.updatedAt.isAfter(item.updatedAt)) {
          await pushHistory(uid, local);
        }
      }
    }

    // Saved episodes are few, so they are read in full: that is what lets an
    // "unsave" on another device reach this one.
    final previousPull = raw == null ? null : DateTime.tryParse(raw);
    final remoteSavedKeys = <String>{};
    for (final doc in (await _episodesRef(uid).get()).docs) {
      final saved = _savedEpisodeFromMap(doc.data());
      if (saved == null) continue;
      remoteSavedKeys.add(saved.key);
      final local = _library.savedEpisodes().any(
        (item) => item.key == saved.key,
      );
      if (!local) await _library.upsertSavedEpisode(saved);
    }
    if (previousPull != null) {
      for (final local in _library.savedEpisodes()) {
        if (remoteSavedKeys.contains(local.key)) continue;
        // Only records that existed before this pull count as removed; a
        // bookmark made on this device while offline stays.
        if (local.savedAt.isBefore(previousPull)) {
          await _library.removeSavedEpisode(local.animeId, local.episodeId);
        }
      }
    }

    if (since == null) await pullSettings(uid);
    await _store.setString(
      LocalStore.settingsBox,
      'sync_last_pull_$uid',
      startedAt.toIso8601String(),
    );
    await _store.setString(
      LocalStore.settingsBox,
      'sync_last_at_$uid',
      startedAt.toIso8601String(),
    );
  }

  /// Pushes the records that exist only on this device. The first link of an
  /// account uses it so an older device never loses its local library.
  Future<void> _pushLocalOnly(String uid) async {
    final remoteEntries = (await _libraryRef(
      uid,
    ).get()).docs.map((doc) => doc.id).toSet();
    final entries = _library
        .entries()
        .where((entry) => !remoteEntries.contains(entry.anime.id))
        .toList(growable: false);
    for (var index = 0; index < entries.length; index += _chunkSize) {
      final batch = _db.batch();
      for (final entry in entries.skip(index).take(_chunkSize)) {
        batch.set(_libraryRef(uid).doc(entry.anime.id), _entryMap(entry));
      }
      await batch.commit();
    }

    final remoteHistory = (await _historyRef(
      uid,
    ).get()).docs.map((doc) => doc.id).toSet();
    final history = _library
        .history()
        .where((item) => !remoteHistory.contains(_historyId(item)))
        .toList(growable: false);
    for (var index = 0; index < history.length; index += _chunkSize) {
      final batch = _db.batch();
      for (final item in history.skip(index).take(_chunkSize)) {
        batch.set(_historyRef(uid).doc(_historyId(item)), _historyMap(item));
      }
      await batch.commit();
    }

    final remoteSaved = (await _episodesRef(
      uid,
    ).get()).docs.map((doc) => doc.id).toSet();
    final saved = _library
        .savedEpisodes()
        .where((item) => !remoteSaved.contains(item.key))
        .toList(growable: false);
    for (var index = 0; index < saved.length; index += _chunkSize) {
      final batch = _db.batch();
      for (final item in saved.skip(index).take(_chunkSize)) {
        batch.set(_episodesRef(uid).doc(item.key), _savedEpisodeMap(item));
      }
      await batch.commit();
    }
  }

  /// Deletes every history record of the account, used by "clear history" so
  /// the removal reaches the other devices too.
  Future<void> clearHistory(String uid) async {
    final docs = (await _historyRef(uid).get()).docs;
    for (var index = 0; index < docs.length; index += _chunkSize) {
      final batch = _db.batch();
      for (final doc in docs.skip(index).take(_chunkSize)) {
        batch.delete(doc.reference);
      }
      await batch.commit();
    }
  }

  String _historyId(WatchHistoryEntry entry) =>
      '${entry.animeId}__${entry.episodeId}';

  Map<String, dynamic> _entryMap(LibraryEntry entry) => <String, dynamic>{
    'animeId': entry.anime.id,
    'anime': entry.anime.toJson(),
    'status': entry.status.name,
    'isFavorite': entry.isFavorite,
    'addedAt': Timestamp.fromDate(entry.addedAt),
    'updatedAt': Timestamp.fromDate(entry.updatedAt),
    'watchedEpisodes': entry.watchedEpisodes,
  };

  Map<String, dynamic> _historyMap(WatchHistoryEntry entry) =>
      <String, dynamic>{
        'animeId': entry.animeId,
        'animeTitle': entry.animeTitle,
        'posterUrl': entry.posterUrl,
        'contentPath': entry.contentPath,
        'episodeId': entry.episodeId,
        'episodeNumber': entry.episodeNumber,
        'episodeTitle': entry.episodeTitle,
        'positionMs': entry.position.inMilliseconds,
        'durationMs': entry.duration.inMilliseconds,
        'completed': entry.completed,
        'updatedAt': Timestamp.fromDate(entry.updatedAt),
      };

  Map<String, dynamic> _savedEpisodeMap(SavedEpisode episode) =>
      <String, dynamic>{
        'animeId': episode.animeId,
        'animeTitle': episode.animeTitle,
        'episodeId': episode.episodeId,
        'episodeNumber': episode.episodeNumber,
        'savedAt': Timestamp.fromDate(episode.savedAt),
        // Optional values are omitted instead of written as null, because the
        // rules type-check every present field.
        if (episode.posterUrl != null) 'posterUrl': episode.posterUrl,
        if (episode.contentPath != null) 'contentPath': episode.contentPath,
        if (episode.episodeTitle != null) 'episodeTitle': episode.episodeTitle,
      };

  LibraryEntry? _entryFromMap(String id, Map<String, dynamic> data) {
    try {
      final anime = data['anime'];
      if (anime is! Map) return null;
      final addedAt = data['addedAt'];
      final updatedAt = data['updatedAt'];
      return LibraryEntry.fromJson(<String, dynamic>{
        'anime': anime.cast<String, dynamic>(),
        'status': data['status'],
        'isFavorite': data['isFavorite'],
        'addedAt': addedAt is Timestamp
            ? addedAt.toDate().toIso8601String()
            : null,
        'updatedAt': updatedAt is Timestamp
            ? updatedAt.toDate().toIso8601String()
            : null,
        'watchedEpisodes': data['watchedEpisodes'],
      });
    } on Object {
      return null;
    }
  }

  WatchHistoryEntry? _historyFromMap(Map<String, dynamic> data) {
    try {
      final updatedAt = data['updatedAt'];
      return WatchHistoryEntry.fromJson(<String, dynamic>{
        'animeId': data['animeId'],
        'animeTitle': data['animeTitle'],
        'posterUrl': data['posterUrl'],
        'contentPath': data['contentPath'],
        'episodeId': data['episodeId'],
        'episodeNumber': data['episodeNumber'],
        'episodeTitle': data['episodeTitle'],
        'positionMs': data['positionMs'],
        'durationMs': data['durationMs'],
        'completed': data['completed'],
        'updatedAt': updatedAt is Timestamp
            ? updatedAt.toDate().toIso8601String()
            : null,
      });
    } on Object {
      return null;
    }
  }

  SavedEpisode? _savedEpisodeFromMap(Map<String, dynamic> data) {
    try {
      final savedAt = data['savedAt'];
      return SavedEpisode.fromJson(<String, dynamic>{
        'animeId': data['animeId'],
        'animeTitle': data['animeTitle'],
        'posterUrl': data['posterUrl'],
        'contentPath': data['contentPath'],
        'episodeId': data['episodeId'],
        'episodeNumber': data['episodeNumber'],
        'episodeTitle': data['episodeTitle'],
        'savedAt': savedAt is Timestamp
            ? savedAt.toDate().toIso8601String()
            : null,
      });
    } on Object {
      return null;
    }
  }
}
