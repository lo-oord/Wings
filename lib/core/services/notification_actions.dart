import 'dart:convert';
import 'dart:io';
import 'dart:ui' show DartPluginRegistrant;

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:path_provider/path_provider.dart';

/// Tray action identifiers and the queue that carries them to the running app.
///
/// A notification action runs in its own short-lived isolate, which may not
/// touch the in-memory download queue. The action is therefore written to a
/// small JSON file and the app applies it as soon as it is resumed (a tap also
/// brings the app forward), so pause/cancel work from the tray.
abstract final class NotificationActions {
  static const String pauseId = 'wings.pause';
  static const String resumeId = 'wings.resume';
  static const String cancelId = 'wings.cancel';
  static const String retryId = 'wings.retry';

  static const String _file = 'wings_notification_actions.json';

  /// Payload that asks the running app to apply queued tray actions.
  static const String trayPayload = 'wings://tray';

  /// Stable payload shape for a download notification.
  static String payloadFor(String taskId) => 'wings://download/$taskId';

  /// Maps an action id plus its notification payload to a queued command.
  static String? commandFor(String? actionId, String? taskId) {
    if (actionId == null || taskId == null || !actionId.startsWith('wings.')) {
      return null;
    }
    final command = switch (actionId) {
      pauseId => 'pause',
      resumeId => 'resume',
      cancelId => 'cancel',
      retryId => 'retry',
      _ => null,
    };
    return command == null ? null : '$command:$taskId';
  }

  static String? taskIdFrom(String? payload) {
    if (payload == null) return null;
    const prefix = 'wings://download/';
    if (!payload.startsWith(prefix)) return null;
    final id = payload.substring(prefix.length);
    return id.isEmpty ? null : id;
  }

  static Future<File> _actionsFile() async {
    final directory = await getApplicationSupportDirectory();
    if (!await directory.exists()) await directory.create(recursive: true);
    return File('${directory.path}/$_file');
  }

  static Future<void> enqueue(String command) async {
    try {
      final file = await _actionsFile();
      final current = await read();
      current.add(command);
      await file.writeAsString(jsonEncode(current.take(50).toList()));
    } on Object catch (error) {
      debugPrint('notification action queue failed: $error');
    }
  }

  /// Reads the queue without clearing it.
  static Future<List<String>> read() async {
    try {
      final file = await _actionsFile();
      if (!await file.exists()) return <String>[];
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! List) return <String>[];
      return decoded.whereType<String>().toList();
    } on Object {
      return <String>[];
    }
  }

  /// Returns and clears the queue.
  static Future<List<String>> take() async {
    try {
      final file = await _actionsFile();
      if (!await file.exists()) return <String>[];
      final items = await read();
      await file.delete();
      return items;
    } on Object {
      return <String>[];
    }
  }
}

/// Entry point for a notification action pressed while the app is in the
/// background. It only records the intent and returns; the app applies it.
@pragma('vm:entry-point')
void handleNotificationAction(NotificationResponse response) {
  // Plugins (path_provider) need the registrant in a background isolate.
  DartPluginRegistrant.ensureInitialized();
  final action = response.actionId;
  final taskId = NotificationActions.taskIdFrom(response.payload);
  if (action == null || taskId == null) return;
  switch (action) {
    case NotificationActions.pauseId:
      NotificationActions.enqueue('pause:$taskId');
    case NotificationActions.resumeId:
      NotificationActions.enqueue('resume:$taskId');
    case NotificationActions.cancelId:
      NotificationActions.enqueue('cancel:$taskId');
    case NotificationActions.retryId:
      NotificationActions.enqueue('retry:$taskId');
  }
}
