import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'notification_actions.dart';

/// Local notification infrastructure.
///
/// Everything here is produced on the device: download progress (with pause and
/// cancel buttons in the tray), finished downloads, and new-episode or reply
/// alerts discovered by the app itself.
class NotificationService {
  NotificationService();

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  final StreamController<String> _taps = StreamController<String>.broadcast();

  bool _initialized = false;
  String? _coldPayload;

  static const String downloadChannelId = 'wings_downloads';
  static const String downloadDoneChannelId = 'wings_downloads_done';
  static const String episodeChannelId = 'wings_episodes';
  static const String replyChannelId = 'wings_replies';

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
          android: AndroidInitializationSettings('@drawable/ic_stat_wings'),
        ),
        onDidReceiveNotificationResponse: (response) {
          // An action pressed while the app was in the foreground arrives here,
          // not in the background isolate: queue it and ask the app to apply it.
          final taskId = NotificationActions.taskIdFrom(response.payload);
          final command = NotificationActions.commandFor(
            response.actionId,
            taskId,
          );
          if (command != null) {
            unawaited(NotificationActions.enqueue(command));
            _taps.add(NotificationActions.trayPayload);
            return;
          }
          final payload = response.payload;
          if (payload == null || payload.isEmpty) return;
          _taps.add(payload);
        },
        onDidReceiveBackgroundNotificationResponse: handleNotificationAction,
      );
      final launch = await _plugin.getNotificationAppLaunchDetails();
      if (launch?.didNotificationLaunchApp ?? false) {
        _coldPayload = launch?.notificationResponse?.payload;
      }
      await _createChannels();
      _initialized = true;
    } on Object catch (error) {
      debugPrint('notifications unavailable: $error');
    }
  }

  /// Channels are created explicitly so the download progress channel stays
  /// silent (low importance) while alerts are visible.
  Future<void> _createChannels() async {
    final android = _android;
    if (android == null) return;
    await android.createNotificationChannel(
      const AndroidNotificationChannel(
        downloadChannelId,
        'تقدم التنزيل',
        description: 'شريط تقدم التنزيل مع أزرار الإيقاف والإلغاء',
        importance: Importance.low,
        playSound: false,
        showBadge: false,
      ),
    );
    await android.createNotificationChannel(
      const AndroidNotificationChannel(
        downloadDoneChannelId,
        'اكتمال التنزيل',
        description: 'إشعار عند انتهاء تنزيل حلقة',
        importance: Importance.defaultImportance,
      ),
    );
    await android.createNotificationChannel(
      const AndroidNotificationChannel(
        episodeChannelId,
        'الحلقات الجديدة',
        description: 'تنبيهات الحلقات الجديدة',
        importance: Importance.defaultImportance,
      ),
    );
    await android.createNotificationChannel(
      const AndroidNotificationChannel(
        replyChannelId,
        'الردود والتعليقات',
        description: 'تنبيه عند الرد على تعليقاتك',
        importance: Importance.defaultImportance,
      ),
    );
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
    required String taskId,
    bool paused = false,
  }) async {
    await initialize();
    if (!_initialized) return;
    try {
      await _plugin.show(
        id: id,
        title: title,
        payload: NotificationActions.payloadFor(taskId),
        body: paused
            ? 'تم الإيقاف مؤقتًا · اضغط للاستئناف'
            : (max > 0
                  ? '${((progress / max) * 100).clamp(0, 100).toStringAsFixed(0)}%'
                  : 'جارٍ التنزيل…'),
        notificationDetails: NotificationDetails(
          android: AndroidNotificationDetails(
            downloadChannelId,
            'تقدم التنزيل',
            channelDescription: 'شريط تقدم التنزيل مع أزرار الإيقاف والإلغاء',
            importance: Importance.low,
            priority: Priority.low,
            onlyAlertOnce: true,
            ongoing: !paused,
            autoCancel: false,
            showProgress: !paused && max > 0,
            progress: progress,
            maxProgress: max <= 0 ? 100 : max,
            indeterminate: !paused && max <= 0,
            icon: '@drawable/ic_stat_wings',
            actions: <AndroidNotificationAction>[
              AndroidNotificationAction(
                paused
                    ? NotificationActions.resumeId
                    : NotificationActions.pauseId,
                paused ? 'استئناف' : 'إيقاف مؤقت',
                showsUserInterface: false,
                cancelNotification: false,
              ),
              AndroidNotificationAction(
                NotificationActions.cancelId,
                'إلغاء',
                showsUserInterface: false,
                cancelNotification: true,
              ),
            ],
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
    String payload = '/downloads',
  }) async {
    if (!enabled) return;
    await cancel(id);
    await _show(
      id: id,
      title: title,
      body: body,
      payload: payload,
      channelId: downloadDoneChannelId,
      channelName: 'اكتمال التنزيل',
      channelDescription: 'إشعار عند انتهاء تنزيل حلقة',
    );
  }

  Future<void> showDownloadFailed({
    required int id,
    required String title,
    required String body,
    required bool enabled,
    required String taskId,
  }) async {
    if (!enabled) return;
    await cancel(id);
    await initialize();
    if (!_initialized) return;
    try {
      await _plugin.show(
        id: id,
        title: title,
        body: body,
        payload: NotificationActions.payloadFor(taskId),
        notificationDetails: NotificationDetails(
          android: AndroidNotificationDetails(
            downloadDoneChannelId,
            'اكتمال التنزيل',
            channelDescription: 'إشعار عند انتهاء تنزيل حلقة',
            importance: Importance.defaultImportance,
            priority: Priority.defaultPriority,
            icon: '@drawable/ic_stat_wings',
            autoCancel: true,
            actions: <AndroidNotificationAction>[
              AndroidNotificationAction(
                NotificationActions.retryId,
                'إعادة المحاولة',
                showsUserInterface: false,
                cancelNotification: true,
              ),
            ],
          ),
        ),
      );
    } on Object catch (error) {
      debugPrint('download failure notification failed: $error');
    }
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
            icon: '@drawable/ic_stat_wings',
            autoCancel: true,
          ),
        ),
      );
    } on Object catch (error) {
      debugPrint('episode notification failed: $error');
    }
  }

  /// A reply to one of the viewer's comments, delivered on the device.
  Future<void> showReply({
    required int id,
    required String title,
    required String body,
    required String payload,
    required bool enabled,
  }) async {
    if (!enabled) return;
    await _show(
      id: id,
      title: title,
      body: body,
      payload: payload,
      channelId: replyChannelId,
      channelName: 'الردود والتعليقات',
      channelDescription: 'تنبيه عند الرد على تعليقاتك',
    );
  }

  /// A short summary shown when several downloads finish in one session.
  Future<void> showDownloadSummary({
    required int id,
    required String title,
    required String body,
    required bool enabled,
  }) async {
    if (!enabled) return;
    await _show(
      id: id,
      title: title,
      body: body,
      payload: '/downloads',
      channelId: downloadDoneChannelId,
      channelName: 'اكتمال التنزيل',
      channelDescription: 'إشعار عند انتهاء تنزيل حلقة',
    );
  }

  Future<void> _show({
    required int id,
    required String title,
    required String body,
    required String channelId,
    required String channelName,
    required String channelDescription,
    String? payload,
  }) async {
    await initialize();
    if (!_initialized) return;
    try {
      await _plugin.show(
        id: id,
        title: title,
        body: body,
        payload: payload,
        notificationDetails: NotificationDetails(
          android: AndroidNotificationDetails(
            channelId,
            channelName,
            channelDescription: channelDescription,
            importance: Importance.defaultImportance,
            priority: Priority.defaultPriority,
            icon: '@drawable/ic_stat_wings',
            autoCancel: true,
          ),
        ),
      );
    } on Object catch (error) {
      debugPrint('notification failed: $error');
    }
  }
}
