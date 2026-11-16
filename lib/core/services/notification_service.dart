import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// Local notification infrastructure.
///
/// Remote push is intentionally not wired: there is no backend to issue tokens,
/// so only real, locally generated events (such as a finished download) are sent.
class NotificationService {
  NotificationService();

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  bool _initialized = false;

  static const AndroidNotificationDetails _downloadDetails =
      AndroidNotificationDetails(
        'wings_downloads',
        'التنزيلات',
        channelDescription: 'إشعارات اكتمال التنزيل أو فشله',
        importance: Importance.defaultImportance,
        priority: Priority.defaultPriority,
      );

  Future<void> initialize() async {
    if (_initialized) return;
    try {
      await _plugin.initialize(
        settings: const InitializationSettings(
          android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        ),
      );
      _initialized = true;
    } on Object catch (error) {
      debugPrint('notifications unavailable: $error');
    }
  }

  AndroidFlutterLocalNotificationsPlugin? get _android => _plugin
      .resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin
      >();

  Future<bool> requestPermission() async {
    await initialize();
    final granted = await _android?.requestNotificationsPermission();
    return granted ?? false;
  }

  Future<bool> isPermissionGranted() async {
    await initialize();
    final enabled = await _android?.areNotificationsEnabled();
    return enabled ?? false;
  }

  Future<void> showDownloadCompleted({
    required String title,
    required String body,
    required bool enabled,
  }) async {
    if (!enabled) return;
    await _show(title, body);
  }

  Future<void> showDownloadFailed({
    required String title,
    required String body,
    required bool enabled,
  }) async {
    if (!enabled) return;
    await _show(title, body);
  }

  Future<void> _show(String title, String body) async {
    await initialize();
    if (!_initialized) return;
    try {
      await _plugin.show(
        id: DateTime.now().millisecondsSinceEpoch.remainder(100000),
        title: title,
        body: body,
        notificationDetails: const NotificationDetails(
          android: _downloadDetails,
        ),
      );
    } on Object catch (error) {
      debugPrint('notification failed: $error');
    }
  }
}
