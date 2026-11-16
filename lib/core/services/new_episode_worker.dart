import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/widgets.dart';
import 'package:path_provider/path_provider.dart';
import 'package:workmanager/workmanager.dart';

import '../../app/router/route_paths.dart';
import '../../data/models/app_notification.dart';
import '../../data/models/library.dart';
import '../../data/sources/algolia_client.dart';
import '../../data/sources/firestore_client.dart';
import '../../data/sources/wings_catalogue_source.dart';
import '../constants/network_constants.dart';
import '../network/http_client.dart';
import 'notification_files.dart';
import 'notification_service.dart';

const String kNewEpisodeTask = 'wings-new-episodes';
const String kNewEpisodeTaskUnique = 'wings-new-episodes-periodic';

/// Registers the 20-minute background job. WorkManager is the only scheduler
/// used, so alerts keep working when the app is closed without any server.
Future<void> configureNewEpisodeWorker(AppSettings settings) async {
  await NotificationFiles.writeState(
    (await NotificationFiles.readState()).copyWith(
      enabled: settings.notifyNewEpisodes,
      locale: settings.localeCode,
    ),
  );
  try {
    await Workmanager().initialize(newEpisodeDispatcher);
    await Workmanager().cancelByUniqueName(kNewEpisodeTaskUnique);
    await Workmanager().registerPeriodicTask(
      kNewEpisodeTaskUnique,
      kNewEpisodeTask,
      frequency: const Duration(minutes: 20),
      constraints: Constraints(networkType: NetworkType.connected),
    );
  } on Object catch (error) {
    debugPrint('worker scheduling failed: $error');
  }
}

@pragma('vm:entry-point')
void newEpisodeDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    WidgetsFlutterBinding.ensureInitialized();
    try {
      await _checkForNewEpisodes();
    } on Object catch (error) {
      debugPrint('new episode check failed: $error');
    }
    return true;
  });
}

Future<void> _checkForNewEpisodes() async {
  final state = await NotificationFiles.readState();
  final dio = createHttpClient();
  final notifications = NotificationService();
  await notifications.initialize();
  final seen = <String>{...state.seen};
  final isFirstRun = seen.isEmpty;
  final fresh = <AppNotification>[];

  try {
    final firestore = FirestoreClient(dio);
    final source = WingsCatalogueSource(
      index: SearchIndexClient(dio, firestore),
      firestore: firestore,
    );
    final latest = await source.latestEpisodes();
    final checked = <String>{};

    for (final item in latest.items.take(30)) {
      final anime = item.anime;
      final episode = item.episode;
      final key = '${anime.id}::${episode.id}';
      checked.add(key);
      if (seen.contains(key)) continue;
      seen.add(key);
      if (isFirstRun) continue;

      final notification = AppNotification(
        animeId: anime.id,
        animeTitle: anime.title,
        episodeId: episode.id,
        episodeNumber: episode.number,
        posterUrl: anime.imageUrl,
        createdAt: item.releasedAt ?? DateTime.now(),
      );
      fresh.add(notification);

      if (!state.enabled) continue;
      final posterPath = await _cachePoster(dio, anime.imageUrl, anime.id);
      await notifications.showNewEpisode(
        id: notification.trayId,
        title: anime.title,
        body: _episodeBody(state.locale, episode.number),
        payload: RoutePaths.watch(animeId: anime.id, episodeId: episode.id),
        posterPath: posterPath,
        enabled: true,
      );
    }

    // Keep the seen list bounded so the file never grows without limit.
    final trimmed = seen.length > 400
        ? seen.toList().sublist(seen.length - 400)
        : seen.toList();
    await NotificationFiles.appendPending(fresh);
    await NotificationFiles.writeState(state.copyWith(seen: trimmed.toSet()));
  } finally {
    dio.close();
  }
}

String _episodeBody(String locale, int number) => locale == 'en'
    ? 'Episode $number is now available 🎉 Tap to watch.'
    : 'الحلقة $number متاحة الآن 🎉 اضغط للمشاهدة';

Future<String?> _cachePoster(Dio dio, String? url, String animeId) async {
  if (url == null || url.isEmpty) return null;
  try {
    final directory = Directory(
      '${(await getTemporaryDirectory()).path}/wings_posters',
    );
    if (!await directory.exists()) await directory.create(recursive: true);
    final safe = animeId.replaceAll(RegExp(r'[^\w\-]+'), '_');
    final file = File('${directory.path}/$safe.jpg');
    if (await file.exists()) return file.path;
    final response = await dio.get<List<int>>(
      url,
      options: Options(
        responseType: ResponseType.bytes,
        headers: <String, String>{'User-Agent': kBrowserUserAgent},
      ),
    );
    final bytes = response.data;
    if (bytes == null || bytes.isEmpty) return null;
    await file.writeAsBytes(bytes, flush: true);
    return file.path;
  } on Object {
    return null;
  }
}
