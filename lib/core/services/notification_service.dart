import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// Local notification infrastructure.
///
/// Everything here is produced on the device: download progress, finished
/// downloads and new-episode alerts discovered by the background worker.
class NotificationService {
  NotificationService();

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  final StreamController<String> _taps = StreamController<String>.broadcast();

  bool _initialized = false;
  String? _coldPayload;

  static const String downloadChannelId = 'wings_downloads';
  static const String episodeChannelId = 'wings_episodes';

  /// Payload of a notification that launched the app, consumed once.
  String? takeColdPayload() {
    final payload = _coldPayload;
    _coldPayload = null;
    return payload;
  }

  /// Emits the route of every tapped notification while the app is running.
  Stream<String> get taps => _taps.stream;

  Future<void> initialize() async {
    if (_initialized) return;
    try {
      await _plugin.initialize(
        settings: const InitializationSettings(
          android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        ),
        onDidReceiveNotificationResponse: (response) {
          final payload = response.payload;
          if (payload == null || payload.isEmpty) return;
          _taps.add(payload);
        },
        onDidReceiveBackgroundNotificationResponse: _backgroundTap,
      );
      final launch = await _plugin.getNotificationAppLaunchDetails();
      if (launch?.didNotificationLaunchApp ?? false) {
        _coldPayload = launch?.notificationResponse?.payload;
      }
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

  Future<void> showDownloadProgress({
    required int id,
    required String title,
    required int progress,
    required int max,
  }) async {
    await initialize();
    if (!_initialized) return;
    try {
      await _plugin.show(
        id: id,
        title: title,
        body: null,
        notificationDetails: NotificationDetails(
          android: AndroidNotificationDetails(
            downloadChannelId,
            'التنزيلات',
            channelDescription: 'تقدم التنزيل واكتماله',
            importance: Importance.low,
            priority: Priority.low,
            onlyAlertOnce: true,
            ongoing: true,
            autoCancel: false,
            showProgress: true,
            progress: progress,
            maxProgress: max <= 0 ? 100 : max,
            indeterminate: max <= 0,
            icon: '@mipmap/ic_launcher',
          ),
        ),
      );
    } on Object catch (error) {
      debugPrint('progress notification failed: $error');
    }
  }

  Future<void> cancel(int id) async {
    try {
      await _plugin.cancel(id: id);
    } on Object {
      // Ignore: cancellation is cosmetic.
    }
  }

  Future<void> showDownloadCompleted({
    required int id,
    required String title,
    required String body,
    required bool enabled,
  }) async {
    if (!enabled) return;
    await cancel(id);
    await _show(
      id: id,
      title: title,
      body: body,
      channelId: downloadChannelId,
      channelName: 'التنزيلات',
      channelDescription: 'تقدم التنزيل واكتماله',
    );
  }

  Future<void> showDownloadFailed({
    required int id,
    required String title,
    required String body,
    required bool enabled,
  }) async {
    if (!enabled) return;
    await cancel(id);
    await _show(
      id: id,
      title: title,
      body: body,
      channelId: downloadChannelId,
      channelName: 'التنزيلات',
      channelDescription: 'تقدم التنزيل واكتماله',
    );
  }

  /// New-episode alert with the poster as the expanded picture.
  Future<void> showNewEpisode({
    required int id,
    required String title,
    required String body,
    required String payload,
    String? posterPath,
    required bool enabled,
  }) async {
    if (!enabled) return;
    await initialize();
    if (!_initialized) return;
    try {
      final style = posterPath == null
          ? BigTextStyleInformation(body)
          : BigPictureStyleInformation(
              FilePathAndroidBitmap(posterPath),
              contentTitle: title,
              summaryText: body,
              hideExpandedLargeIcon: false,
            );
      await _plugin.show(
        id: id,
        title: title,
        body: body,
        payload: payload,
        notificationDetails: NotificationDetails(
          android: AndroidNotificationDetails(
            episodeChannelId,
            'الحلقات الجديدة',
            channelDescription: 'تنبيهات الحلقات الجديدة',
            importance: Importance.defaultImportance,
            priority: Priority.defaultPriority,
            styleInformation: style,
            largeIcon: posterPath == null
                ? null
                : FilePathAndroidBitmap(posterPath),
            icon: '@mipmap/ic_launcher',
            autoCancel: true,
          ),
        ),
      );
    } on Object catch (error) {
      debugPrint('episode notification failed: $error');
    }
  }

  Future<void> _show({
    required int id,
    required String title,
    required String body,
    required String channelId,
    required String channelName,
    required String channelDescription,
  }) async {
    await initialize();
    if (!_initialized) return;
    try {
      await _plugin.show(
        id: id,
        title: title,
        body: body,
        notificationDetails: NotificationDetails(
          android: AndroidNotificationDetails(
            channelId,
            channelName,
            channelDescription: channelDescription,
            importance: Importance.defaultImportance,
            priority: Priority.defaultPriority,
            icon: '@mipmap/ic_launcher',
          ),
        ),
      );
    } on Object catch (error) {
      debugPrint('notification failed: $error');
    }
  }
}

@pragma('vm:entry-point')
void _backgroundTap(NotificationResponse response) {
  // Background taps are handled when the app comes to the foreground.
}
