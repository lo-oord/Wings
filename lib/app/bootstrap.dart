import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';

import '../core/network/http_client.dart';
import '../core/services/download_service.dart';
import '../core/services/notification_service.dart';
import '../core/storage/local_store.dart';
import '../data/repositories/settings_repository.dart';
import 'app.dart';
import 'providers.dart';

Future<void> bootstrap() async {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();

  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  SystemChrome.setPreferredOrientations(<DeviceOrientation>[
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  final store = await LocalStore.open();
  final notifications = NotificationService();
  await notifications.initialize();

  final downloads = DownloadService(
    dio: createHttpClient(),
    store: store,
    notifications: notifications,
  );
  await downloads.initialize();
  downloads.notificationsEnabled = SettingsRepository(store)
      .load()
      .notifyDownloads;

  runApp(
    ProviderScope(
      overrides: [
        localStoreProvider.overrideWithValue(store),
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
