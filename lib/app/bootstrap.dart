import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';

import '../core/network/http_client.dart';
import '../core/services/download_service.dart';
import '../core/services/in_app_notifications.dart';
import '../core/services/new_episode_worker.dart';
import '../core/services/notification_service.dart';
import '../core/services/storage_service.dart';
import '../core/storage/local_store.dart';
import '../data/firebase/firebase_bootstrap.dart';
import '../data/repositories/settings_repository.dart';
import 'app.dart';
import 'providers.dart';
import 'splash.dart';

Future<void> bootstrap() async {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();

  // Draw the branded splash on the very first frame: opening the store,
  // Firebase and the download queue takes long enough that a blank system
  // window looked like a frozen app.
  final startedAt = DateTime.now();
  runApp(const WingsSplashApp());

  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  SystemChrome.setPreferredOrientations(<DeviceOrientation>[
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  final store = await LocalStore.open();
  final firebaseReady = await initializeFirebase();
  final notifications = NotificationService();
  await notifications.initialize();

  // Fold alerts discovered by the background worker into the app list.
  await InAppNotificationsService(store).pullPending();

  final settings = SettingsRepository(store).load();
  final downloads = DownloadService(
    createHttpClient(),
    store,
    notifications,
    StorageService(),
  );
  await downloads.initialize();
  downloads.notificationsEnabled = settings.notifyDownloads;
  await configureNewEpisodeWorker(settings);

  // Keep the splash on screen just long enough to read instead of flashing.
  const minimumSplash = Duration(milliseconds: 850);
  final elapsed = DateTime.now().difference(startedAt);
  if (elapsed < minimumSplash) {
    await Future<void>.delayed(minimumSplash - elapsed);
  }

  runApp(
    ProviderScope(
      overrides: [
        localStoreProvider.overrideWithValue(store),
        firebaseReadyProvider.overrideWithValue(firebaseReady),
        notificationServiceProvider.overrideWithValue(notifications),
        downloadServiceProvider.overrideWith((ref) {
          ref.onDispose(downloads.dispose);
          return downloads;
        }),
      ],
      child: const WingsApp(),
    ),
  );
}
