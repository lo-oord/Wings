import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';

import '../core/network/http_client.dart';
import '../core/services/connectivity_service.dart';
import '../core/services/download_service.dart';
import '../core/services/in_app_notifications.dart';
import '../core/services/new_episode_worker.dart';
import '../core/services/notification_service.dart';
import '../core/services/share_service.dart';
import '../core/services/storage_service.dart';
import '../core/storage/local_store.dart';
import '../data/models/anime.dart';
import '../data/models/app_notification.dart';
import '../data/models/library.dart';
import '../data/repositories/anime_repository.dart';
import '../data/repositories/auth_repository.dart';
import '../data/repositories/library_repository.dart';
import '../data/repositories/settings_repository.dart';
import '../data/sources/algolia_client.dart';
import '../data/sources/anime_source.dart';
import '../data/sources/cartoony_source.dart';
import '../data/sources/firestore_client.dart';
import '../data/sources/multi_source_catalogue.dart';
import '../data/sources/server_resolver.dart';
import '../data/sources/wings_catalogue_source.dart';

// ---------------------------------------------------------------------------
// Infrastructure
// ---------------------------------------------------------------------------

/// Overridden in bootstrap with the opened store.
final localStoreProvider = Provider<LocalStore>(
  (ref) => throw UnimplementedError('localStoreProvider must be overridden'),
);

final httpClientProvider = Provider<Dio>((ref) {
  final dio = createHttpClient();
  ref.onDispose(dio.close);
  return dio;
});

final firestoreClientProvider = Provider<FirestoreClient>(
  (ref) => FirestoreClient(ref.watch(httpClientProvider)),
);

final searchClientProvider = Provider<SearchIndexClient>(
  (ref) => SearchIndexClient(
    ref.watch(httpClientProvider),
    ref.watch(firestoreClientProvider),
  ),
);

final wingsSourceProvider = Provider<AnimeSource>(
  (ref) => WingsCatalogueSource(
    index: ref.watch(searchClientProvider),
    firestore: ref.watch(firestoreClientProvider),
  ),
);

/// «سبيستون غو» catalogue from the public Cartoony / Carateen site.
final cartoonySpSourceProvider = Provider<AnimeSource>(
  (ref) => CartoonySource(
    ref.watch(httpClientProvider),
    catalog: CartoonyCatalog.spacetoonGo,
  ),
);

/// «كرتون أيام زمان» catalogue from the same site.
final cartoonyTgSourceProvider = Provider<AnimeSource>(
  (ref) => CartoonySource(
    ref.watch(httpClientProvider),
    catalog: CartoonyCatalog.classic,
  ),
);

/// Every configured catalogue, merged behind one contract.
final animeSourceProvider = Provider<AnimeSource>(
  (ref) => MultiSourceCatalogue(<AnimeSource>[
    ref.watch(wingsSourceProvider),
    ref.watch(cartoonySpSourceProvider),
    ref.watch(cartoonyTgSourceProvider),
  ]),
);

final animeRepositoryProvider = Provider<AnimeRepository>((ref) {
  return AnimeRepository(
    ref.watch(animeSourceProvider),
    ServerResolver(ref.watch(httpClientProvider)),
    ref.watch(localStoreProvider),
  );
});

final libraryRepositoryProvider = Provider<LibraryRepository>(
  (ref) => LibraryRepository(ref.watch(localStoreProvider)),
);

final settingsRepositoryProvider = Provider<SettingsRepository>(
  (ref) => SettingsRepository(ref.watch(localStoreProvider)),
);

final notificationServiceProvider = Provider<NotificationService>(
  (ref) => NotificationService(),
);

final storageServiceProvider = Provider<StorageService>(
  (ref) => StorageService(),
);

final downloadServiceProvider = Provider<DownloadService>((ref) {
  final service = DownloadService(
    ref.watch(httpClientProvider),
    ref.watch(localStoreProvider),
    ref.watch(notificationServiceProvider),
    ref.watch(storageServiceProvider),
  );
  ref.onDispose(service.dispose);
  return service;
});

final inAppNotificationsProvider = Provider<InAppNotificationsService>(
  (ref) => InAppNotificationsService(ref.watch(localStoreProvider)),
);

/// New-episode alerts shown in the notification centre.
class NotificationsController extends Notifier<List<AppNotification>> {
  @override
  List<AppNotification> build() => _service.all();

  InAppNotificationsService get _service =>
      ref.read(inAppNotificationsProvider);

  Future<void> refresh() async {
    await _service.pullPending();
    state = _service.all();
  }

  Future<void> markAllRead() async {
    await _service.markAllRead();
    state = _service.all();
  }

  Future<void> clear() async {
    await _service.clear();
    state = _service.all();
  }
}

final notificationsProvider =
    NotifierProvider<NotificationsController, List<AppNotification>>(
      NotificationsController.new,
    );

final unreadNotificationsProvider = Provider<int>(
  (ref) => ref
      .watch(notificationsProvider)
      .where((item) => !item.read)
      .length
      .clamp(0, 99),
);

final shareServiceProvider = Provider<ShareService>((ref) => ShareService());

final connectivityServiceProvider = Provider<ConnectivityService>(
  (ref) => ConnectivityService(Connectivity()),
);

/// Emits connectivity changes; seeded with the current state by the UI.
final onlineProvider = StreamProvider<bool>(
  (ref) => ref.watch(connectivityServiceProvider).changes,
);

// ---------------------------------------------------------------------------
// Settings
// ---------------------------------------------------------------------------

class SettingsController extends Notifier<AppSettings> {
  @override
  AppSettings build() => ref.read(settingsRepositoryProvider).load();

  Future<void> update(
    AppSettings Function(AppSettings current) transform,
  ) async {
    state = transform(state);
    await ref.read(settingsRepositoryProvider).save(state);
    ref.read(downloadServiceProvider).notificationsEnabled =
        state.notifyDownloads;
    await configureNewEpisodeWorker(state);
  }

  Future<void> setThemeMode(ThemeMode mode) =>
      update((s) => s.copyWith(themeMode: mode));

  Future<void> setLocale(String code) =>
      update((s) => s.copyWith(localeCode: code));

  Future<void> completeOnboarding() =>
      update((s) => s.copyWith(onboardingDone: true));

  Future<void> enterGuestMode() => update((s) => s.copyWith(guestMode: true));

  Future<void> leaveGuestMode() => update((s) => s.copyWith(guestMode: false));
}

final settingsProvider = NotifierProvider<SettingsController, AppSettings>(
  SettingsController.new,
);

// ---------------------------------------------------------------------------
// Library
// ---------------------------------------------------------------------------

class LibraryState {
  const LibraryState({
    required this.entries,
    required this.history,
    required this.searches,
  });

  final List<LibraryEntry> entries;
  final List<WatchHistoryEntry> history;
  final List<String> searches;

  LibraryEntry? entryFor(String animeId) {
    for (final entry in entries) {
      if (entry.anime.id == animeId) return entry;
    }
    return null;
  }

  Set<String> watchedEpisodeIds(String animeId) => history
      .where((h) => h.animeId == animeId)
      .map((h) => h.episodeId)
      .toSet();

  WatchHistoryEntry? lastFor(String animeId) {
    for (final entry in history) {
      if (entry.animeId == animeId) return entry;
    }
    return null;
  }

  List<LibraryEntry> byStatus(LibraryStatus status) =>
      entries.where((e) => e.status == status).toList(growable: false);

  List<LibraryEntry> get favorites =>
      entries.where((e) => e.isFavorite).toList(growable: false);
}

class LibraryController extends Notifier<LibraryState> {
  LibraryRepository get _repo => ref.read(libraryRepositoryProvider);

  @override
  LibraryState build() => _read();

  LibraryState _read() => LibraryState(
    entries: _repo.entries(),
    history: _repo.history(),
    searches: _repo.searchHistory(),
  );

  Future<void> toggleFavorite(Anime anime) async {
    await _repo.toggleFavorite(anime);
    state = _read();
  }

  Future<void> setStatus(Anime anime, LibraryStatus status) async {
    await _repo.setStatus(anime, status);
    state = _read();
  }

  Future<void> removeFromLibrary(String animeId) async {
    await _repo.removeFromLibrary(animeId);
    state = _read();
  }

  Future<void> saveProgress(
    WatchHistoryEntry entry, {
    required bool completed,
  }) async {
    await _repo.saveProgress(entry, completed: completed);
    state = _read();
  }

  Future<void> clearHistory() async {
    await _repo.clearHistory();
    state = _read();
  }

  Future<void> removeHistoryEntry(String key) async {
    await _repo.removeHistoryEntry(key);
    state = _read();
  }

  Future<void> addSearch(String query) async {
    await _repo.addSearchQuery(query);
    state = _read();
  }

  Future<void> removeSearch(String query) async {
    await _repo.removeSearchQuery(query);
    state = _read();
  }

  Future<void> clearSearchHistory() async {
    await _repo.clearSearchHistory();
    state = _read();
  }
}

final libraryProvider = NotifierProvider<LibraryController, LibraryState>(
  LibraryController.new,
);

// ---------------------------------------------------------------------------
// Downloads
// ---------------------------------------------------------------------------

class DownloadTasksController extends Notifier<List<DownloadTask>> {
  @override
  List<DownloadTask> build() {
    final service = ref.watch(downloadServiceProvider);
    final subscription = service.stream.listen((tasks) => state = tasks);
    ref.onDispose(subscription.cancel);
    return service.tasks;
  }

  DownloadService get _service => ref.read(downloadServiceProvider);

  Future<void> pause(String id) => _service.pause(id);

  Future<void> resume(String id) => _service.resume(id);

  Future<void> retry(String id) => _service.retry(id);

  Future<void> cancel(String id) => _service.cancel(id);

  Future<void> deleteFile(String id) => _service.deleteFile(id);

  Future<void> enqueue(DownloadTask task) => _service.enqueue(task);
}

final downloadTasksProvider =
    NotifierProvider<DownloadTasksController, List<DownloadTask>>(
      DownloadTasksController.new,
    );

final storageUsedProvider = Provider<int>((ref) {
  final tasks = ref.watch(downloadTasksProvider);
  return tasks
      .where((task) => task.status == DownloadStatus.completed)
      .fold<int>(0, (sum, task) => sum + task.totalBytes);
});

// ---------------------------------------------------------------------------
// Account
// ---------------------------------------------------------------------------

final authRepositoryProvider = Provider<AuthRepository>(
  (ref) => LocalDevelopmentAuthRepository(),
);

class AuthController extends Notifier<AuthUser?> {
  @override
  AuthUser? build() => ref.read(authRepositoryProvider).currentUser;

  Future<void> signIn({required String email, required String password}) async {
    state = await ref
        .read(authRepositoryProvider)
        .signIn(email: email, password: password);
  }

  Future<void> register({
    required String displayName,
    required String username,
    required String country,
    required String email,
    required String password,
    String? avatarPath,
  }) async {
    state = await ref
        .read(authRepositoryProvider)
        .register(
          displayName: displayName,
          username: username,
          country: country,
          email: email,
          password: password,
          avatarPath: avatarPath,
        );
  }

  Future<void> updateProfile({
    String? displayName,
    String? username,
    String? country,
    String? avatarPath,
    String? bio,
  }) async {
    state = ref
        .read(authRepositoryProvider)
        .updateProfile(
          displayName: displayName,
          username: username,
          country: country,
          avatarPath: avatarPath,
          bio: bio,
        );
  }

  Future<void> signOut() async {
    await ref.read(authRepositoryProvider).signOut();
    state = null;
  }

  Future<void> deleteAccount() async {
    await ref.read(authRepositoryProvider).deleteAccount();
    state = null;
  }
}

final authProvider = NotifierProvider<AuthController, AuthUser?>(
  AuthController.new,
);

// ---------------------------------------------------------------------------
// Playback
// ---------------------------------------------------------------------------

/// A player instance per watch session, disposed with the screen.
final playerProvider = Provider.autoDispose<Player>((ref) {
  final player = Player();
  ref.onDispose(player.dispose);
  return player;
});
