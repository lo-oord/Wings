import 'dart:convert';

import 'package:hive_ce_flutter/hive_flutter.dart';

/// Local persistence for settings, library, history, downloads and cache.
///
/// Values are stored as JSON strings so the schema stays flexible and no
/// generated adapters are required.
class LocalStore {
  LocalStore._(this._boxes);

  final Map<String, Box<String>> _boxes;

  static const String settingsBox = 'settings';
  static const String libraryBox = 'library';
  static const String historyBox = 'history';
  static const String cacheBox = 'cache';
  static const String downloadsBox = 'downloads';
  static const String searchBox = 'search';
  static const String notificationsBox = 'notifications';
  static const String myEpisodesBox = 'my_episodes';

  static Future<LocalStore> open({String? directory}) async {
    if (directory == null) {
      await Hive.initFlutter('wings');
    } else {
      Hive.init(directory);
    }
    final boxes = <String, Box<String>>{};
    for (final name in const <String>[
      settingsBox,
      libraryBox,
      historyBox,
      cacheBox,
      downloadsBox,
      searchBox,
      notificationsBox,
      myEpisodesBox,
    ]) {
      boxes[name] = await Hive.openBox<String>(name);
    }
    return LocalStore._(boxes);
  }

  Box<String> _box(String name) =>
      _boxes[name] ?? (throw StateError('box $name not open'));

  String? getString(String box, String key) => _box(box).get(key);

  Future<void> setString(String box, String key, String value) =>
      _box(box).put(key, value);

  Future<void> delete(String box, String key) => _box(box).delete(key);

  Future<void> clear(String box) => _box(box).clear();

  Object? getJson(String box, String key) {
    final raw = _box(box).get(key);
    if (raw == null) return null;
    try {
      return jsonDecode(raw);
    } on FormatException {
      return null;
    }
  }

  Future<void> putJson(String box, String key, Object value) =>
      _box(box).put(key, jsonEncode(value));

  List<Map<String, dynamic>> valuesAsJson(String box) {
    final result = <Map<String, dynamic>>[];
    for (final raw in _box(box).values) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map<String, dynamic>) result.add(decoded);
      } on FormatException {
        continue;
      }
    }
    return result;
  }

  int get lengthOfLibrary => _box(libraryBox).length;

  /// Stores a value with an expiry so stale catalogue data is never served.
  Future<void> putCache(String key, Object value, {required Duration ttl}) {
    final envelope = <String, dynamic>{
      'expiresAt': DateTime.now().add(ttl).millisecondsSinceEpoch,
      'value': value,
    };
    return _box(cacheBox).put(key, jsonEncode(envelope));
  }

  /// Returns cached data, including stale data when [allowStale] is true.
  Object? readCache(String key, {bool allowStale = false}) {
    final raw = _box(cacheBox).get(key);
    if (raw == null) return null;
    try {
      final envelope = jsonDecode(raw);
      if (envelope is! Map) return null;
      final expiresAt = envelope['expiresAt'];
      if (!allowStale &&
          expiresAt is int &&
          DateTime.now().millisecondsSinceEpoch > expiresAt) {
        return null;
      }
      return envelope['value'];
    } on FormatException {
      return null;
    }
  }
}
