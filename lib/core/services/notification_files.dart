import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../../data/models/app_notification.dart';

/// Small JSON files shared between the UI isolate and the background worker.
///
/// The worker must not open the app's Hive boxes while the main engine holds
/// them, so new-episode alerts travel through these files instead.
class NotificationFiles {
  static const String _stateFile = 'wings_notification_state.json';
  static const String _pendingFile = 'wings_pending_notifications.json';

  static Future<Directory> _directory() async {
    final support = await getApplicationSupportDirectory();
    if (!await support.exists()) await support.create(recursive: true);
    return support;
  }

  static Future<File> _file(String name) async =>
      File('${(await _directory()).path}/$name');

  static Future<NotificationState> readState() async {
    try {
      final file = await _file(_stateFile);
      if (!await file.exists()) return const NotificationState();
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map) return const NotificationState();
      return NotificationState.fromJson(decoded.cast<String, dynamic>());
    } on Object {
      return const NotificationState();
    }
  }

  static Future<void> writeState(NotificationState state) async {
    try {
      final file = await _file(_stateFile);
      await file.writeAsString(jsonEncode(state.toJson()));
    } on FileSystemException {
      // Notifications are best-effort; never break the app over state.
    }
  }

  static Future<void> appendPending(List<AppNotification> items) async {
    if (items.isEmpty) return;
    try {
      final file = await _file(_pendingFile);
      final existing = await _readPending(file);
      final merged = <String, AppNotification>{
        for (final item in existing) item.id: item,
        for (final item in items) item.id: item,
      };
      await file.writeAsString(
        jsonEncode(merged.values.map((item) => item.toJson()).toList()),
      );
    } on FileSystemException {
      // Ignore: the next worker run will try again.
    }
  }

  /// Returns and clears the pending queue.
  static Future<List<AppNotification>> takePending() async {
    try {
      final file = await _file(_pendingFile);
      if (!await file.exists()) return const [];
      final items = await _readPending(file);
      await file.delete();
      return items;
    } on Object {
      return const [];
    }
  }

  static Future<List<AppNotification>> _readPending(File file) async {
    if (!await file.exists()) return const [];
    try {
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! List) return const [];
      return decoded
          .whereType<Map>()
          .map((item) => AppNotification.fromJson(item.cast<String, dynamic>()))
          .where((item) => item.animeId.isNotEmpty)
          .toList();
    } on Object {
      return const [];
    }
  }
}

/// Worker-facing notification state.
class NotificationState {
  const NotificationState({
    this.enabled = true,
    this.locale = 'ar',
    this.seen = const <String>{},
  });

  final bool enabled;
  final String locale;
  final Set<String> seen;

  NotificationState copyWith({
    bool? enabled,
    String? locale,
    Set<String>? seen,
  }) => NotificationState(
    enabled: enabled ?? this.enabled,
    locale: locale ?? this.locale,
    seen: seen ?? this.seen,
  );

  Map<String, dynamic> toJson() => <String, dynamic>{
    'enabled': enabled,
    'locale': locale,
    'seen': seen.take(400).toList(),
  };

  factory NotificationState.fromJson(Map<String, dynamic> json) =>
      NotificationState(
        enabled: json['enabled'] as bool? ?? true,
        locale: json['locale'] as String? ?? 'ar',
        seen:
            (json['seen'] as List?)?.whereType<String>().toSet() ?? <String>{},
      );
}
