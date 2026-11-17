import 'package:cloud_firestore/cloud_firestore.dart';

import '../../core/storage/local_store.dart';
import '../models/library.dart';
import '../repositories/library_repository.dart';
import '../repositories/settings_repository.dart';

/// Synchronizes the account-owned slice of the app across devices.
///
/// Synchronized: library entries (favourites, statuses, watched counts), watch
/// history and progress, and account-level preferences. Device-only data
/// (downloads and their files, notification setup, theme, onboarding state)
/// never leaves the device.
///
/// Conflict rule: last-writer-wins on each record's `updatedAt`. Pulls are
/// incremental, so a small change never re-downloads the whole library.
class CloudSyncService {
  CloudSyncService(this._db, this._store, this._library, this._settings);

  final FirebaseFirestore _db;
  final LocalStore _store;
  final LibraryRepository _library;
  final SettingsRepository _settings;

  static const String _accountKey = 'sync_account_uid';

  CollectionReference<Map<String, dynamic>> _libraryRef(String uid) =>
      _db.collection('users').doc(uid).collection('library');

  CollectionReference<Map<String, dynamic>> _historyRef(String uid) =>
      _db.collection('users').doc(uid).collection('history');

  DocumentReference<Map<String, dynamic>> _settingsRef(String uid) =>
      _db.collection('users').doc(uid).collection('settings').doc('account');

  String get _accountUid =>
      _store.getString(LocalStore.settingsBox, _accountKey) ?? '';

  bool _migrated(String uid) =>
      _store.getString(LocalStore.settingsBox, 'sync_migrated_$uid') == '1';

  /// Called whenever an authenticated account becomes active.
  ///
  /// * Same account as last time: pull incremental changes.
  /// * First link: migrate local guest data into the account, never discarding
  ///   it silently.
  /// * Different account: wipe the previous account's local data first, so one
  ///   user's library can never be shown or pushed to another account.
  Future<void> attach(String uid) async {
    final previous = _accountUid;
    if (previous.isNotEmpty && previous != uid) {
      await _library.clearAccountData();
      await _store.delete(LocalStore.settingsBox, 'sync_last_pull_$previous');
    }
    if (!_migrated(uid)) {
      await _migrate(uid);
    } else {
      await pull(uid);
    }
    await _store.setString(LocalStore.settingsBox, _accountKey, uid);
  }

  /// Called on sign-out or account removal.
  Future<void> detach({bool clearSettings = false}) async {
    await _library.clearAccountData();
    if (clearSettings) {
      await _store.delete(LocalStore.settingsBox, _accountKey);
    }
  }

  /// Pushes every local record once, then records the migration as done.
  Future<void> _migrate(String uid) async {
    final entries = _library.entries();
    final history = _library.history();
    final batch = _db.batch();
    for (final entry in entries) {
      batch.set(_libraryRef(uid).doc(entry.anime.id), _entryMap(entry));
    }
    for (final item in history) {
      batch.set(_historyRef(uid).doc(_historyId(item)), _historyMap(item));
    }
    if (entries.isNotEmpty || history.isNotEmpty) {
      await batch.commit();
    }
    await pushSettings(uid);
    await _store.setString(LocalStore.settingsBox, 'sync_migrated_$uid', '1');
    await _store.setString(
      LocalStore.settingsBox,
      'sync_last_pull_$uid',
      DateTime.now().toIso8601String(),
    );
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

  /// Pulls only records changed since the previous pull for this account.
  Future<void> pull(String uid) async {
    final raw = _store.getString(LocalStore.settingsBox, 'sync_last_pull_$uid');
    final since = raw == null ? null : DateTime.tryParse(raw);
    final startedAt = DateTime.now();

    final libraryQuery = since == null
        ? _libraryRef(uid)
        : _libraryRef(uid)
              .where('updatedAt', isGreaterThan: Timestamp.fromDate(since));
    var changed = false;
    for (final doc in (await libraryQuery.get()).docs) {
      final data = doc.data();
      final entry = _entryFromMap(doc.id, data);
      if (entry == null) continue;
      final local = _library.entryFor(doc.id);
      if (local == null || entry.updatedAt.isAfter(local.updatedAt)) {
        await _library.upsertEntry(entry);
        changed = true;
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
        changed = true;
      } else if (local.updatedAt.isAfter(item.updatedAt)) {
        await pushHistory(uid, local);
      }
    }

    if (since == null) await pullSettings(uid);
    await _store.setString(
      LocalStore.settingsBox,
      'sync_last_pull_$uid',
      startedAt.toIso8601String(),
    );
    if (changed) {
      // Local controllers re-read the store; the sync never mutates UI state
      // directly.
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
}
