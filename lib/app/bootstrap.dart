import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';

import '../core/network/http_client.dart';
import '../core/services/download_service.dart';
import '../core/services/new_episode_worker.dart';
import '../core/services/notification_service.dart';
import '../core/services/storage_service.dart';
import '../core/storage/local_store.dart';
import '../data/firebase/firebase_bootstrap.dart';
import '../data/repositories/settings_repository.dart';
import 'app.dart';
import 'providers.dart';
import 'splash.dart';
import 'theme/app_tokens.dart';

Future<void> bootstrap() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Cheap platform calls: queued here so the window is already in the right
  // orientation when it appears, but never awaited — waiting on a channel
  // before the first frame is what used to look like a frozen launch.
  unawaited(SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge));
  unawaited(
    SystemChrome.setPreferredOrientations(const <DeviceOrientation>[
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]),
  );

  // The first and only thing drawn up front is the branded splash. Opening the
  // store, Firebase, the notification plugin and the download queue happens
  // behind it, so the launch is smooth no matter how much work is pending.
  runApp(const WingsBootstrap());
}

/// Everything the widget tree needs from a completed start-up.
class ApplicationServices {
  const ApplicationServices({
    required this.store,
    required this.firebaseReady,
    required this.notifications,
    required this.downloads,
  });

  final LocalStore store;
  final bool firebaseReady;
  final NotificationService notifications;
  final DownloadService downloads;
}

/// Opens the local store and the services that depend on it.
///
/// The independent parts run concurrently and report into [progress]; the
/// long-running work that no screen needs (the background scheduler, system
/// chrome, the alert queue) is left to finish on its own so it can never hold
/// up the first usable frame.
Future<ApplicationServices> initializeServices(
  ValueNotifier<double> progress,
) async {
  progress.value = 0.08;

  // Opening eight Hive boxes, initializing Firebase and preparing the
  // notification plugin do not depend on each other, so they overlap instead
  // of adding up to one long serialized wait.
  final storeFuture = LocalStore.open();
  final firebaseFuture = initializeFirebase();
  final notifications = NotificationService();
  final notificationsFuture = notifications.initialize();

  final store = await storeFuture;
  progress.value = 0.4;

  final firebaseReady = await firebaseFuture;
  progress.value = 0.6;

  // Loads the native playback library (libmpv). A player is never created
  // before a screen is open, so the warm-up belongs here — behind the splash —
  // rather than before the first frame.
  MediaKit.ensureInitialized();
  progress.value = 0.72;

  await notificationsFuture;
  final settings = SettingsRepository(store).load();

  final downloads = DownloadService(
    createHttpClient(),
    store,
    notifications,
    StorageService(),
  );
  await downloads.initialize();
  downloads.notificationsEnabled = settings.notifyDownloads;
  progress.value = 0.94;

  // Scheduling a periodic job is several platform round-trips; it must never
  // delay a screen that is already ready.
  unawaited(configureNewEpisodeWorker(settings));

  progress.value = 1;
  return ApplicationServices(
    store: store,
    firebaseReady: firebaseReady,
    notifications: notifications,
    downloads: downloads,
  );
}

/// Holds the splash above the interface until start-up finishes, then fades it
/// out over the first screen.
class WingsBootstrap extends StatefulWidget {
  const WingsBootstrap({super.key});

  @override
  State<WingsBootstrap> createState() => _WingsBootstrapState();
}

class _WingsBootstrapState extends State<WingsBootstrap> {
  final ValueNotifier<double> _progress = ValueNotifier<double>(0);
  ApplicationServices? _services;
  bool _failed = false;
  bool _showSplash = true;

  /// Long enough to read the brand, short enough that it never feels like a
  /// delay; the rest of the wait is whatever the real work takes.
  static const Duration _minimumSplash = Duration(milliseconds: 900);

  @override
  void initState() {
    super.initState();
    unawaited(_start());
  }

  Future<void> _start() async {
    final startedAt = DateTime.now();
    try {
      final services = await initializeServices(_progress);
      final elapsed = DateTime.now().difference(startedAt);
      if (elapsed < _minimumSplash) {
        await Future<void>.delayed(_minimumSplash - elapsed);
      }
      if (!mounted) {
        services.downloads.dispose();
        return;
      }
      setState(() => _services = services);
    } on Object catch (error, stack) {
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: error,
          stack: stack,
          library: 'wings bootstrap',
          context: ErrorDescription('while opening the local store'),
        ),
      );
      if (!mounted) return;
      setState(() => _failed = true);
    }
  }

  void _retry() {
    setState(() {
      _failed = false;
      _progress.value = 0;
    });
    unawaited(_start());
  }

  @override
  void dispose() {
    // [_progress] is deliberately not disposed: start-up may still be running
    // when the tree is torn down (tests, hot restart) and a late write to a
    // disposed notifier would throw. It is one small object for the life of
    // the process.
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final services = _services;
    // The stack is above both MaterialApps, so it needs its own direction for
    // the splash while it is the only child.
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          if (services != null)
            ProviderScope(
              overrides: [
                localStoreProvider.overrideWithValue(services.store),
                firebaseReadyProvider.overrideWithValue(services.firebaseReady),
                notificationServiceProvider.overrideWithValue(
                  services.notifications,
                ),
                downloadServiceProvider.overrideWith((ref) {
                  ref.onDispose(services.downloads.dispose);
                  return services.downloads;
                }),
              ],
              child: const WingsApp(),
            ),
          if (_showSplash)
            IgnorePointer(
              ignoring: services != null,
              child: AnimatedOpacity(
                opacity: services == null ? 1 : 0,
                duration: Motion.slow,
                curve: Motion.standard,
                onEnd: () {
                  if (!mounted || _services == null) return;
                  setState(() => _showSplash = false);
                },
                child: WingsSplashApp(
                  progress: _progress,
                  failed: _failed,
                  onRetry: _retry,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
