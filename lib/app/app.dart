import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/services/notification_actions.dart';
import '../core/storage/local_store.dart';
import '../data/models/social_notification.dart';
import '../core/widgets/wings_feedback.dart';
import '../features/player/mini_player.dart';
import '../features/player/playback_session.dart';
import 'localization/app_localizations.dart';
import 'providers.dart';
import 'router/app_router.dart';
import 'scroll_behavior.dart';
import 'theme/app_palette.dart';
import 'theme/app_theme.dart';

class WingsApp extends ConsumerStatefulWidget {
  const WingsApp({super.key});

  @override
  ConsumerState<WingsApp> createState() => _WingsAppState();
}

class _WingsAppState extends ConsumerState<WingsApp>
    with WidgetsBindingObserver {
  GoRouter? _router;
  ProviderSubscription<AsyncValue<List<SocialNotification>>>? _traySub;
  String? _trayUid;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final notifications = ref.read(notificationServiceProvider);
    notifications.taps.listen(_openPayload);
    final cold = notifications.takeColdPayload();
    if (cold != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _openPayload(cold));
    }
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await ref.read(notificationsProvider.notifier).refresh();
      await _applyTrayActions();
      await _showReplyAlerts();
    });
  }

  /// Raises one tray alert for replies that arrived while the app was closed.
  ///
  /// The reply documents are written by the replier's device, so the receiving
  /// device discovers them when it next runs; showing a single alert for the
  /// newest unread reply keeps that honest without a push service.
  Future<void> _showReplyAlerts() async {
    try {
      final uid = ref.read(authProvider)?.id;
      if (uid == null) return;
      final settings = ref.read(settingsProvider);
      if (!settings.notifyReplies) return;
      final unread = await ref.read(notificationRepositoryProvider).unread(uid);
      if (unread.isEmpty) return;
      final latest = unread.first;
      final store = ref.read(localStoreProvider);
      final key = 'reply_alert_shown_$uid';
      if (store.getString(LocalStore.cacheBox, key) == latest.id) return;
      await store.setString(LocalStore.cacheBox, key, latest.id);
      await ref
          .read(notificationServiceProvider)
          .showReply(
            id: latest.trayId,
            title: latest.actorName.isEmpty
                ? '@${latest.actorUsername}'
                : latest.actorName,
            body: latest.text,
            payload: latest.route,
            enabled: true,
          );
    } on Object {
      // Never block start-up over an alert.
    }
  }

  /// Keeps one tray listener for the signed-in account, so a reply, a report
  /// update or an Owner message that arrives while the app is open reaches the
  /// system bar immediately instead of waiting for the next launch.
  void _bindTrayStream(String? uid) {
    if (uid == _trayUid) return;
    _trayUid = uid;
    _traySub?.close();
    _traySub = null;
    if (uid == null) return;
    _traySub = ref.listenManual<AsyncValue<List<SocialNotification>>>(
      socialNotificationsProvider(uid),
      (previous, next) {
        final items = next.value;
        if (items != null) unawaited(_announce(items, uid));
      },
    );
  }

  /// Raises one tray alert for notifications this device has not announced.
  Future<void> _announce(List<SocialNotification> items, String uid) async {
    if (items.isEmpty) return;
    try {
      final store = ref.read(localStoreProvider);
      final key = 'tray_announced_$uid';
      final last =
          int.tryParse(store.getString(LocalStore.cacheBox, key) ?? '') ?? 0;
      final fresh = items
          .where(
            (item) =>
                !item.read && item.createdAt.millisecondsSinceEpoch > last,
          )
          .toList(growable: false);
      if (fresh.isEmpty) return;
      final latest = fresh.first;
      await store.setString(
        LocalStore.cacheBox,
        key,
        '${latest.createdAt.millisecondsSinceEpoch}',
      );
      final settings = ref.read(settingsProvider);
      final enabled = latest.isAdmin
          ? settings.notifyReplies || settings.notifyGeneral
          : settings.notifyReplies;
      final title = latest.isAdmin
          ? (latest.title.isEmpty ? 'Wings' : latest.title)
          : (latest.actorName.isEmpty
                ? '@${latest.actorUsername}'
                : latest.actorName);
      final body = latest.isAdmin
          ? latest.body
          : (latest.text.isEmpty ? latest.title : latest.text);
      if (body.isEmpty) return;
      await ref
          .read(notificationServiceProvider)
          .showOfficial(
            id: latest.trayId,
            title: title,
            body: body,
            payload: latest.route,
            enabled: enabled,
          );
    } on Object {
      // A tray alert must never disturb the interface.
    }
  }

  /// Applies pause/cancel requests pressed in the notification tray.
  Future<void> _applyTrayActions() async {
    try {
      await ref.read(downloadServiceProvider).consumeTrayActions();
    } on Object {
      // Nothing queued or the service is not ready yet.
    }
  }

  @override
  void dispose() {
    _traySub?.close();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  void _openPayload(String payload) {
    if (payload == NotificationActions.trayPayload) {
      unawaited(_applyTrayActions());
      return;
    }
    final router = _router;
    if (payload.isEmpty || router == null) return;
    // A download notification points at its own transfer; open the list.
    if (NotificationActions.taskIdFrom(payload) != null) {
      router.push('/downloads');
      return;
    }
    router.push(payload);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    // Android drops the video surface while the app is in the background or in
    // picture-in-picture; rebuilding it here keeps the floating window alive.
    ref.read(playbackSessionProvider.notifier).refreshSurface();
    ref.read(notificationsProvider.notifier).refresh();
    unawaited(_applyTrayActions());
    unawaited(_showReplyAlerts());
    // Pull anything the account changed on another device while the app was in
    // the background (throttled inside the controller).
    unawaited(ref.read(authProvider.notifier).syncNow());
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider);
    final router = ref.watch(routerProvider);
    _bindTrayStream(ref.watch(authProvider)?.id);
    // Keeps the background sync timer alive for the whole app session; it is
    // rescheduled whenever the user changes the interval in settings.
    ref.watch(syncSchedulerProvider);
    _router = router;

    return MaterialApp.router(
      title: 'Wings',
      debugShowCheckedModeBanner: false,
      routerConfig: router,
      theme: buildWingsTheme(WingsPalette.light),
      darkTheme: buildWingsTheme(WingsPalette.dark),
      themeMode: settings.themeMode,
      scrollBehavior: const WingsScrollBehavior(),
      locale: settings.locale,
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      builder: (context, child) {
        // The interface is designed for a restrained text scale range so
        // layouts stay intact on devices with large accessibility fonts.
        final media = MediaQuery.of(context);
        final scale = media.textScaler.clamp(
          minScaleFactor: 0.9,
          maxScaleFactor: 1.3,
        );
        return MediaQuery(
          data: media.copyWith(textScaler: scale),
          // The floating player sits above every route so leaving an episode
          // never stops the video.
          child: MiniPlayerHost(child: child ?? const WingsLoading()),
        );
      },
    );
  }
}
