import 'dart:async';

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
import '../core/services/permission_service.dart';
import '../core/services/share_service.dart';
import '../core/services/storage_service.dart';
import '../core/storage/local_store.dart';
import '../features/stickers/sticker_providers.dart';
import '../data/models/anime.dart';
import '../data/models/app_notification.dart';
import '../data/models/library.dart';
import '../data/repositories/anime_repository.dart';
import '../data/repositories/auth_repository.dart';
import '../data/models/social_notification.dart';
import '../data/repositories/identity_repository.dart';
import '../data/repositories/library_repository.dart';
import '../data/repositories/notification_repository.dart';
import '../data/repositories/settings_repository.dart';
import '../data/sources/algolia_client.dart';
import '../data/sources/anime_source.dart';
import '../data/sources/cartoony_source.dart';
import '../data/sources/firestore_client.dart';
import '../data/sources/live_source.dart';
import '../data/sources/multi_source_catalogue.dart';
import '../data/models/live_channel.dart';
import '../data/sources/server_resolver.dart';
import '../data/sources/wings_catalogue_source.dart';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../core/errors/app_failure.dart';
import '../data/auth/account_deletion_service.dart';
import '../data/auth/account_service.dart';
import '../data/auth/firebase_auth_repository.dart';
import '../data/models/user_profile.dart';
import '../core/services/community_media_service.dart';
import '../data/repositories/avatar_repository.dart';
import '../data/repositories/community_repository.dart';
import '../data/repositories/cover_repository.dart';
import '../data/repositories/social_repository.dart';
import '../data/repositories/views_repository.dart';
import '../data/repositories/user_repository.dart';
import '../data/repositories/username_repository.dart';
import '../data/sync/cloud_sync_service.dart';

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

/// Live television channels (Spacetoon, MBC 3, Japanese anime street).
final liveSourceProvider = Provider<LiveSource>(
  (ref) => LiveSource(ref.watch(httpClientProvider)),
);

/// The three pinned channels, refreshed with their live schedule at most every
/// five minutes. The pinned list is returned whenever the endpoint fails, so a
/// live card never disappears from the hero.
final liveChannelsProvider = FutureProvider<List<LiveChannel>>((ref) async {
  try {
    return await ref.watch(liveSourceProvider).channels();
  } on Object {
    return LiveSource.seeds;
  }
});

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

final permissionServiceProvider = Provider<PermissionService>(
  (ref) => PermissionService(),
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
    final before = state;
    state = transform(before);
    await ref.read(settingsRepositoryProvider).save(state);
    ref.read(downloadServiceProvider).notificationsEnabled =
        state.notifyDownloads;
    await configureNewEpisodeWorker(state);
    // The system permission is asked for exactly when a member turns an alert
    // on, never during launch. Without it Android 13+ drops every tray alert.
    final enabledOne =
        (!before.notifyDownloads && state.notifyDownloads) ||
        (!before.notifyNewEpisodes && state.notifyNewEpisodes) ||
        (!before.notifyReplies && state.notifyReplies) ||
        (!before.notifyGeneral && state.notifyGeneral);
    if (enabledOne) {
      try {
        await ref.read(notificationServiceProvider).requestPermission();
      } on Object {
        // The device may not support the prompt; alerts simply stay off.
      }
    }
    await _pushAccountSettings();
  }

  /// Pushes the account-level slice only; device settings stay local.
  Future<void> _pushAccountSettings() async {
    if (!ref.read(firebaseReadyProvider)) return;
    final uid = ref.read(authProvider)?.id;
    if (uid == null) return;
    try {
      await ref.read(cloudSyncProvider).pushSettings(uid);
    } on Object {
      // Offline: the next change retries.
    }
  }

  /// Re-reads preferences after a cloud pull.
  Future<void> reloadFromStore() async {
    state = ref.read(settingsRepositoryProvider).load();
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
    this.savedEpisodes = const <SavedEpisode>[],
  });

  final List<LibraryEntry> entries;
  final List<WatchHistoryEntry> history;
  final List<String> searches;

  /// Episodes bookmarked into **حلقاتي**.
  final List<SavedEpisode> savedEpisodes;

  bool isEpisodeSaved(String animeId, String episodeId) => savedEpisodes.any(
    (item) => item.animeId == animeId && item.episodeId == episodeId,
  );

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

  DateTime? _lastStatsPush;
  String? _lastStatsSignature;

  /// Publishes the counters shown on the public profile.
  ///
  /// The numbers always describe what the viewer actually did: an episode is
  /// counted as soon as it is opened, a title as soon as it has any history or
  /// is marked watching/completed. Publishing is throttled for playback ticks
  /// but bypassed whenever a value really changed, so a favourite or a watched
  /// episode moves the counters immediately on every device.
  void _publishStats({bool force = false}) {
    final current = state;
    final user = ref.read(authProvider);
    if (user == null || !ref.read(firebaseReadyProvider)) return;

    final watchedAnime = <String>{
      ...current.history.map((item) => item.animeId),
      ...current.entries
          .where(
            (entry) =>
                entry.status == LibraryStatus.watching ||
                entry.status == LibraryStatus.completed,
          )
          .map((entry) => entry.anime.id),
    };
    final stats = ProfileStats(
      animeWatched: watchedAnime.length,
      episodesWatched: current.history.length,
      favorites: current.favorites.length,
      completed: current.byStatus(LibraryStatus.completed).length,
    );
    final favorites = <ProfileFavorite>[
      for (final entry in current.favorites.take(12))
        ProfileFavorite(
          animeId: entry.anime.id,
          title: entry.anime.title,
          imageUrl: entry.anime.imageUrl ?? '',
        ),
    ];
    final signature =
        '${stats.animeWatched}/${stats.episodesWatched}/'
        '${stats.favorites}/${stats.completed}/'
        '${favorites.map((item) => item.animeId).join(',')}';
    final last = _lastStatsPush;
    final unchanged = signature == _lastStatsSignature;
    if (!force &&
        unchanged &&
        last != null &&
        DateTime.now().difference(last) < const Duration(minutes: 10)) {
      return;
    }
    if (!force &&
        !unchanged &&
        last != null &&
        DateTime.now().difference(last) < const Duration(seconds: 15)) {
      return;
    }
    _lastStatsSignature = signature;
    _lastStatsPush = DateTime.now();
    unawaited(
      ref.read(authProvider.notifier).publishStats(stats, favorites: favorites),
    );
  }

  @override
  LibraryState build() => _read();

  LibraryState _read() => LibraryState(
    entries: _repo.entries(),
    history: _repo.history(),
    searches: _repo.searchHistory(),
    savedEpisodes: _repo.savedEpisodes(),
  );

  /// Re-reads the store after a cloud pull.
  void refresh() => state = _read();

  /// Pushes the current counters to the account's public profile.
  void publishCurrentStats() => _publishStats(force: true);

  /// Pushes a single record for the signed-in account. Failures stay local and
  /// are reconciled by the next incremental pull.
  Future<void> _push(
    Future<void> Function(CloudSyncService sync, String uid) action,
  ) async {
    if (!ref.read(firebaseReadyProvider)) return;
    final uid = ref.read(authProvider)?.id;
    if (uid == null) return;
    try {
      await action(ref.read(cloudSyncProvider), uid);
    } on Object {
      // Offline or not permitted; the local value wins until the next pull.
    }
  }

  Future<void> toggleFavorite(Anime anime) async {
    await _repo.toggleFavorite(anime);
    state = _read();
    final entry = _repo.entryFor(anime.id);
    if (entry != null) {
      await _push((sync, uid) => sync.pushEntry(uid, entry));
    }
    _publishStats(force: true);
  }

  Future<void> setStatus(Anime anime, LibraryStatus status) async {
    await _repo.setStatus(anime, status);
    state = _read();
    final entry = _repo.entryFor(anime.id);
    if (entry != null) {
      await _push((sync, uid) => sync.pushEntry(uid, entry));
    }
    _publishStats(force: true);
  }

  Future<void> removeFromLibrary(String animeId) async {
    await _repo.removeFromLibrary(animeId);
    state = _read();
    await _push((sync, uid) => sync.deleteEntry(uid, animeId));
    _publishStats(force: true);
  }

  Future<void> saveProgress(
    WatchHistoryEntry entry, {
    required bool completed,
  }) async {
    final wasKnown = _repo.historyFor(entry.animeId, entry.episodeId) != null;
    await _repo.saveProgress(entry, completed: completed);
    state = _read();
    final stored = _repo.historyFor(entry.animeId, entry.episodeId);
    if (stored != null) {
      await _push((sync, uid) => sync.pushHistory(uid, stored));
    }
    final libraryEntry = _repo.entryFor(entry.animeId);
    if (libraryEntry != null) {
      await _push((sync, uid) => sync.pushEntry(uid, libraryEntry));
    }
    // The first save of an episode (and finishing one) is a real event, so the
    // counters move at once instead of waiting for the playback throttle.
    _publishStats(force: completed || !wasKnown);
  }

  Future<void> clearHistory() async {
    await _repo.clearHistory();
    state = _read();
    await _push((sync, uid) => sync.clearHistory(uid));
    _publishStats(force: true);
  }

  Future<void> removeHistoryEntry(String key) async {
    await _repo.removeHistoryEntry(key);
    state = _read();
    // Local keys are `animeId::episodeId`; the cloud document id is
    // `animeId__episodeId`, so a removal reaches the other devices too.
    final parts = key.split('::');
    final cloudId = parts.length == 2 ? '${parts[0]}__${parts[1]}' : key;
    await _push((sync, uid) => sync.deleteHistory(uid, cloudId));
    _publishStats(force: true);
  }

  /// Saves or removes one episode in **حلقاتي**. The entry carries only
  /// display information and is synced as such, not as a library title.
  Future<void> toggleSavedEpisode(Anime anime, AnimeEpisode episode) async {
    final saved = await _repo.toggleSavedEpisode(
      anime: anime,
      episode: episode,
    );
    state = _read();
    final exists = _repo.isEpisodeSaved(anime.id, episode.id);
    await _push(
      (sync, uid) => exists
          ? sync.pushSavedEpisode(uid, saved)
          : sync.deleteSavedEpisode(uid, saved.key),
    );
  }

  Future<void> removeSavedEpisode(String animeId, String episodeId) async {
    await _repo.removeSavedEpisode(animeId, episodeId);
    state = _read();
    await _push(
      (sync, uid) => sync.deleteSavedEpisode(uid, '${animeId}__$episodeId'),
    );
  }

  Future<void> addSearch(String query) async {
    await _repo.addSearchQuery(query);
    state = _read();
    await _push((sync, uid) => sync.pushSearch(uid, state.searches));
  }

  Future<void> removeSearch(String query) async {
    await _repo.removeSearchQuery(query);
    state = _read();
    await _push((sync, uid) => sync.pushSearch(uid, state.searches));
  }

  Future<void> clearSearchHistory() async {
    await _repo.clearSearchHistory();
    state = _read();
    await _push((sync, uid) => sync.pushSearch(uid, const <String>[]));
  }
}

final libraryProvider = NotifierProvider<LibraryController, LibraryState>(
  LibraryController.new,
);

/// Runs the account sync on the cadence picked in settings.
///
/// Every local change is still pushed immediately, so this only controls the
/// periodic pull that brings in changes made on another device.
class SyncScheduler {
  SyncScheduler(this._ref) {
    _ref.listen<AppSettings>(settingsProvider, (previous, next) {
      if (previous?.syncInterval == next.syncInterval) return;
      _schedule(next.syncInterval);
    }, fireImmediately: true);
  }

  final Ref _ref;
  Timer? _timer;

  void _schedule(SyncInterval interval) {
    _timer?.cancel();
    _timer = null;
    final period = interval.period;
    // "فورًا" pushes each change as it happens, "يدويًا" runs only on demand.
    if (period == null || period == Duration.zero) return;
    _timer = Timer.periodic(period, (_) {
      unawaited(_ref.read(authProvider.notifier).syncNow(force: true));
    });
  }

  void dispose() {
    _timer?.cancel();
    _timer = null;
  }
}

final syncSchedulerProvider = Provider<SyncScheduler>((ref) {
  final scheduler = SyncScheduler(ref);
  ref.onDispose(scheduler.dispose);
  return scheduler;
});

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
      .fold<int>(0, (total, task) => total + task.totalBytes);
});

// ---------------------------------------------------------------------------
// Account
// ---------------------------------------------------------------------------

// ---------------------------------------------------------------------------
// Account
// ---------------------------------------------------------------------------

/// False until Firebase is initialized during bootstrap.
final firebaseReadyProvider = Provider<bool>((ref) => false);

final firebaseAuthProvider = Provider<FirebaseAuthRepository?>(
  (ref) => ref.watch(firebaseReadyProvider) ? FirebaseAuthRepository() : null,
);

/// Production identity provider, or the local adapter when this build has no
/// Firebase configuration.
final authRepositoryProvider = Provider<AuthRepository>(
  (ref) => ref.watch(firebaseAuthProvider) ?? LocalDevelopmentAuthRepository(),
);

final usernameRepositoryProvider = Provider<UsernameRepository>(
  (ref) => UsernameRepository(FirebaseFirestore.instance),
);

final userRepositoryProvider = Provider<UserRepository>(
  (ref) => UserRepository(FirebaseFirestore.instance),
);

final avatarRepositoryProvider = Provider<AvatarRepository>(
  (ref) => AvatarRepository(
    FirebaseFirestore.instance,
    ref.watch(localStoreProvider),
  ),
);

final coverRepositoryProvider = Provider<CoverRepository>(
  (ref) => CoverRepository(
    FirebaseFirestore.instance,
    ref.watch(localStoreProvider),
  ),
);

/// View counters with a local throttle so a screen re-open never costs a write.
final viewsRepositoryProvider = Provider<ViewsRepository>(
  (ref) => ViewsRepository(
    FirebaseFirestore.instance,
    ref.watch(localStoreProvider),
  ),
);

final cloudSyncProvider = Provider<CloudSyncService>(
  (ref) => CloudSyncService(
    FirebaseFirestore.instance,
    ref.watch(localStoreProvider),
    ref.watch(libraryRepositoryProvider),
    ref.watch(settingsRepositoryProvider),
  ),
);

final accountServiceProvider = Provider<AccountService?>((ref) {
  final auth = ref.watch(firebaseAuthProvider);
  if (auth == null) return null;
  return AccountService(
    auth,
    ref.watch(usernameRepositoryProvider),
    ref.watch(userRepositoryProvider),
    ref.watch(avatarRepositoryProvider),
    ref.watch(coverRepositoryProvider),
    ref.watch(cloudSyncProvider),
    FirebaseFirestore.instance,
  );
});

final accountDeletionProvider = Provider<AccountDeletionService?>((ref) {
  final auth = ref.watch(firebaseAuthProvider);
  if (auth == null) return null;
  return AccountDeletionService(
    FirebaseFirestore.instance,
    auth,
    ref.watch(userRepositoryProvider),
    ref.watch(usernameRepositoryProvider),
    ref.watch(cloudSyncProvider),
  );
});

final socialRepositoryProvider = Provider<SocialRepository>(
  (ref) => SocialRepository(
    FirebaseFirestore.instance,
    ref.watch(localStoreProvider),
    // Null while the bundled manifest is still loading; the composer only
    // offers ids from the same catalogue, and the rules re-check the shape.
    ref.watch(stickerCatalogProvider).value,
  ),
);

final notificationRepositoryProvider = Provider<NotificationRepository>(
  (ref) => NotificationRepository(FirebaseFirestore.instance),
);

/// Posts, likes, saved posts, follows and blocks. It shares the profile,
/// comment and notification systems rather than duplicating them.
final communityRepositoryProvider = Provider<CommunityRepository>(
  (ref) => CommunityRepository(FirebaseFirestore.instance),
);

/// Signed upload/download URLs from the existing `wings-media-api` Worker.
final communityMediaProvider = Provider<CommunityMediaService>(
  (ref) => CommunityMediaService(ref.watch(httpClientProvider)),
);

/// Blocked emails/usernames and their review requests.
final identityRepositoryProvider = Provider<IdentityRepository>(
  (ref) => IdentityRepository(FirebaseFirestore.instance),
);

/// Replies and future community alerts for one account.
final socialNotificationsProvider = StreamProvider.autoDispose
    .family<List<SocialNotification>, String>(
      (ref, uid) => ref.watch(notificationRepositoryProvider).watch(uid),
    );

final socialUnreadProvider = Provider.family<int, String>((ref, uid) {
  final items = ref.watch(socialNotificationsProvider(uid)).value;
  if (items == null) return 0;
  return items.where((item) => !item.read).length.clamp(0, 99).toInt();
});

/// Unread count shown on the home bell: local episode alerts plus replies.
final unreadEverythingProvider = Provider<int>((ref) {
  final local = ref.watch(unreadNotificationsProvider);
  final uid = ref.watch(authProvider)?.id;
  if (uid == null) return local;
  return (local + ref.watch(socialUnreadProvider(uid))).clamp(0, 99).toInt();
});

/// The full profile document of the signed-in user.
class ProfileController extends Notifier<UserProfile?> {
  @override
  UserProfile? build() => null;

  void apply(UserProfile? profile) => state = profile;

  Future<void> reload() async {
    final user = ref.read(authProvider);
    if (user == null) {
      state = null;
      return;
    }
    state = await ref.read(userRepositoryProvider).fetch(user.id);
  }
}

final profileProvider = NotifierProvider<ProfileController, UserProfile?>(
  ProfileController.new,
);

/// True once the signed-in account's profile has been looked up, so the router
/// does not send a fully registered account to the completion screen while its
/// profile is still loading.
class ProfileResolved extends Notifier<bool> {
  @override
  bool build() => false;

  void update(bool value) => state = value;
}

final profileResolvedProvider = NotifierProvider<ProfileResolved, bool>(
  ProfileResolved.new,
);

/// Public profile of another user, read from the privacy-filtered mirror.
final publicProfileProvider = StreamProvider.autoDispose
    .family<UserProfile?, String>(
      (ref, uid) => ref.watch(userRepositoryProvider).watchPublic(uid),
    );

/// Medal (1–3) per comment id, resolved oldest-first so the first commenters
/// keep their medals when the list is read newest-first.
final topCommentRanksProvider = StreamProvider.autoDispose
    .family<Map<String, int>, String>(
      (ref, episodeId) =>
          ref.watch(socialRepositoryProvider).watchTopRanks(episodeId),
    );

class AuthController extends Notifier<AuthUser?> {
  /// Account whose library has already been linked during this app session.
  String? _syncedUid;
  DateTime? _lastSync;

  /// Watches the administrator-managed badge document of the signed-in
  /// account, so a grant appears without relaunching the app.
  StreamSubscription<ProfileBadges?>? _badgesSubscription;

  /// Links (or re-pulls) the cloud copy of the library.
  ///
  /// Restoring a saved Firebase session never went through `AccountService`, so
  /// nothing was ever pulled and the library stayed device-local. Doing it here
  /// covers cold starts, Google sign-ins and silent token refreshes alike.
  Future<void> _ensureCloudSync(String uid) async {
    final first = _syncedUid != uid;
    if (!first) return;
    try {
      await ref.read(cloudSyncProvider).attach(uid);
      _syncedUid = uid;
      _lastSync = DateTime.now();
      ref.read(libraryProvider.notifier).refresh();
      ref.read(libraryProvider.notifier).publishCurrentStats();
    } on Object {
      // Offline: the next app start or resume retries.
    }
  }

  /// Pulls remote changes while the app runs (resume, timer, manual refresh).
  ///
  /// Returns false when there is nothing to sync or the network refused.
  /// Selecting "أبدًا (يدويًا)" stops the automatic calls; the sync buttons in
  /// the library and settings always pass [force].
  Future<bool> syncNow({bool force = false}) async {
    final user = state;
    if (user == null || !ref.read(firebaseReadyProvider)) return false;
    if (!force &&
        ref.read(settingsProvider).syncInterval == SyncInterval.manual) {
      return false;
    }
    final last = _lastSync;
    if (!force &&
        last != null &&
        DateTime.now().difference(last) < const Duration(minutes: 2)) {
      return true;
    }
    try {
      final sync = ref.read(cloudSyncProvider);
      // `attach` already runs the (incremental or full) pull for this account.
      await sync.attach(user.id);
      await sync.pullSearch(user.id);
      _syncedUid = user.id;
      _lastSync = DateTime.now();
      ref.read(libraryProvider.notifier).refresh();
      ref.read(libraryProvider.notifier).publishCurrentStats();
      return true;
    } on Object {
      // Keep the local library when the network is unavailable.
      return false;
    }
  }

  @override
  AuthUser? build() {
    final repository = ref.watch(authRepositoryProvider);
    final subscription = repository.authChanges.listen(_onAuthChanged);
    ref.onDispose(subscription.cancel);
    ref.onDispose(() {
      _badgesSubscription?.cancel();
    });
    final current = repository.currentUser;
    if (current != null) {
      Future<void>.microtask(() => _refresh(current));
    }
    return current;
  }

  Future<void> _onAuthChanged(AuthUser? user) async {
    if (user == null) {
      await _badgesSubscription?.cancel();
      _badgesSubscription = null;
      ref.read(profileProvider.notifier).apply(null);
      state = null;
      return;
    }
    await _refresh(user);
  }

  /// Keeps the signature of the signed-in account live. An administrator grant
  /// (or a removal) is applied to the profile, copied into both profile
  /// documents and pushed onto every existing comment of the account.
  void _watchBadges(String uid) {
    _badgesSubscription?.cancel();
    _badgesSubscription = ref
        .read(userRepositoryProvider)
        .watchBadges(uid)
        .listen(
          (badges) {
            // `null` means no administrator document: the mark already on the
            // profile stays, so a console grant is never erased.
            if (badges == null) return;
            final current = ref.read(profileProvider);
            if (current == null || current.badges == badges) return;
            final next = current.copyWith(badges: badges);
            ref.read(profileProvider.notifier).apply(next);
            unawaited(ref.read(socialRepositoryProvider).syncAuthor(next));
          },
          onError: (Object _) {
            // Badge rules not published yet: the stored copies keep working.
          },
        );
  }

  /// Loads the profile document so screens always read the authoritative
  /// username, display name and country.
  ///
  /// A signed-in account without a profile document (an interrupted Google or
  /// email sign-up) is repaired here instead of being left in a half state.
  /// Copies the sign-in methods of the live Firebase session onto the state,
  /// so the profile can show «متصل بالبريد/بجوجل» correctly after a link.
  AuthUser _withProviders(AuthUser user) {
    final repository = ref.read(authRepositoryProvider);
    final current = repository.currentUser;
    return user.copyWith(
      // A linked email can replace the address on the Firebase account, so the
      // state follows the live session instead of the value read at sign-in.
      email: current?.email ?? user.email,
      hasPassword: repository.hasPasswordProvider,
      hasGoogle: repository.hasGoogleProvider,
      emailVerified: repository.emailVerified,
    );
  }

  Future<void> _refresh(AuthUser user) async {
    // Only a completed lookup may mark the account as "resolved": an offline
    // start must not be mistaken for an account without a profile.
    var resolved = false;
    try {
      final found = await ref.read(userRepositoryProvider).fetch(user.id);
      resolved = true;
      if (found != null) {
        // Badges are granted by an administrator on the public mirror. The
        // owner document may still hold the old values, so the mirror is the
        // authoritative source for the signature that colours a handle.
        final profile = await _withPublicBadges(found);
        ref.read(profileProvider.notifier).apply(profile);
        _watchBadges(profile.uid);
        state = _withProviders(user).copyWith(
          displayName: profile.displayName,
          username: profile.username,
          country: profile.country,
          bio: profile.bio,
        );
        // A rename or a new badge only shows on comments written from now on
        // unless the existing snapshots are refreshed too.
        unawaited(ref.read(socialRepositoryProvider).syncAuthor(profile));
        await _ensureCloudSync(profile.uid);
        await _afterAccountReady();
        return;
      }
      // Signed in without a profile (a Google sign-up that was not finished):
      // the profile completion screen creates it, so no handle is invented.
      ref.read(profileProvider.notifier).apply(null);
    } on Object {
      // Offline or not permitted; the identity state remains valid.
    } finally {
      if (resolved) ref.read(profileResolvedProvider.notifier).update(true);
    }
    state = _withProviders(user);
    await _afterAccountReady();
  }

  /// Resolves the signature of the account.
  ///
  /// `badges/{uid}` is the authority while it exists: a grant or an explicit
  /// `false` is exactly what the account gets. When the document is absent the
  /// copies already on `users/{uid}` / `profiles/{uid}` are kept, because an
  /// administrator may grant a mark straight from the console — treating a
  /// missing document as “revoked” is what switched such grants off again.
  Future<UserProfile> _withPublicBadges(UserProfile profile) async {
    final repository = ref.read(userRepositoryProvider);
    try {
      final granted = await repository.fetchBadges(profile.uid);
      if (granted == null || granted == profile.badges) return profile;
      return profile.copyWith(badges: granted);
    } on Object {
      // Offline or old rules: keep what the profile already carries until the
      // next read instead of guessing.
      return profile;
    }
  }

  /// Applies data that the account sync pulled while signing in.
  Future<void> _afterAccountReady() async {
    try {
      ref.read(libraryProvider.notifier).refresh();
      await ref.read(settingsProvider.notifier).reloadFromStore();
      // Republish the counters so the public profile matches the library that
      // was just downloaded, even before the profile screen is opened.
      ref.read(libraryProvider.notifier).publishCurrentStats();
    } on Object {
      // Controllers will rebuild on their next mutation.
    }
  }

  Future<void> signIn({required String email, required String password}) async {
    final service = ref.read(accountServiceProvider);
    state = service != null
        ? await service.signIn(email: email, password: password)
        : await ref
              .read(authRepositoryProvider)
              .signIn(email: email, password: password);
    final current = state;
    if (current != null) await _refresh(current);
  }

  Future<void> signInWithGoogle() async {
    final service = ref.read(accountServiceProvider);
    state = service != null
        ? await service.signInWithGoogle()
        : await ref.read(authRepositoryProvider).signInWithGoogle();
    final current = state;
    if (current != null) await _refresh(current);
  }

  /// One Google tap that both signs in and registers.
  ///
  /// An existing Wings account is signed in exactly as before; when the Google
  /// account has never used Wings, the registration starts and the reader is
  /// sent to the profile completion form. Returns true when a new account was
  /// created, so the caller can choose the right destination.
  Future<bool> continueWithGoogle() async {
    final service = ref.read(accountServiceProvider);
    if (service == null) {
      final user = await ref
          .read(authRepositoryProvider)
          .signInWithGoogle(createAccount: true);
      state = _withProviders(user);
      return false;
    }
    try {
      final user = await service.signInWithGoogle();
      state = _withProviders(user);
      await _refresh(state ?? user);
      return false;
    } on AppFailure catch (error) {
      // `google-account-not-found` means Google authenticated a person who has
      // no Wings account yet: create it instead of dead-ending the button.
      if (error.technical != 'google-account-not-found') rethrow;
      await registerWithGoogle();
      return true;
    }
  }

  /// Starts a Google registration and keeps the session open so the profile can
  /// be completed with a real username instead of one generated behind the
  /// reader's back.
  Future<AuthUser> registerWithGoogle() async {
    final service = ref.read(accountServiceProvider);
    final user = service != null
        ? await service.registerWithGoogle()
        : await ref
              .read(authRepositoryProvider)
              .signInWithGoogle(createAccount: true);
    ref.read(profileProvider.notifier).apply(null);
    ref.read(profileResolvedProvider.notifier).update(true);
    state = _withProviders(user);
    return user;
  }

  /// Creates the profile of a Google account after the completion form.
  Future<UserProfile> completeProfile({
    required String displayName,
    required String username,
    required String country,
    required String ageGroup,
    String? avatarPath,
  }) async {
    final user = state;
    final service = ref.read(accountServiceProvider);
    if (user == null || service == null) {
      throw const AppFailure(FailureKind.unknown, technical: 'no-user');
    }
    final profile = await service.completeProfile(
      user: user,
      displayName: displayName,
      username: username,
      country: country,
      ageGroup: ageGroup,
      avatarPath: avatarPath,
    );
    ref.read(profileProvider.notifier).apply(profile);
    state = user.copyWith(
      displayName: profile.displayName,
      username: profile.username,
      country: profile.country,
    );
    unawaited(ref.read(socialRepositoryProvider).syncAuthor(profile));
    return profile;
  }

  /// Links the Google account picked in the system sheet to the signed-in
  /// account. A Google account that already belongs to another Wings user is
  /// refused by Firebase and reported as such.
  Future<void> linkGoogleAccount() async {
    await ref.read(authRepositoryProvider).linkGoogle();
    final current = state;
    if (current != null) state = _withProviders(current);
  }

  /// Starts adding an email + password to a Google-only account. Returns true
  /// when the address needed no verification (it is the Google address) and the
  /// link already completed.
  Future<bool> requestEmailLink({
    required String email,
    required String password,
  }) async {
    final immediate = await ref
        .read(authRepositoryProvider)
        .requestEmailLink(email: email, password: password);
    if (immediate) await completeEmailLink();
    return immediate;
  }

  Future<bool> emailLinkVerified() =>
      ref.read(authRepositoryProvider).emailLinkVerified();

  Future<void> completeEmailLink() async {
    await ref.read(authRepositoryProvider).completeEmailLink();
    final current = state;
    if (current != null) state = _withProviders(current);
  }

  Future<void> register({
    required String displayName,
    required String username,
    required String country,
    required String email,
    required String password,
    String ageGroup = '',
    String? avatarPath,
  }) async {
    final service = ref.read(accountServiceProvider);
    if (service == null) {
      state = await ref
          .read(authRepositoryProvider)
          .createAccount(
            email: email,
            password: password,
            displayName: displayName,
          );
      return;
    }
    state = await service.register(
      displayName: displayName,
      username: username,
      country: country,
      ageGroup: ageGroup,
      email: email,
      password: password,
      avatarPath: avatarPath,
    );
    final current = state;
    if (current != null) await _refresh(current);
  }

  Future<UserProfile> updateProfile({
    String? displayName,
    String? bio,
    String? country,
    String? ageGroup,
  }) async {
    final profile = ref.read(profileProvider);
    final service = ref.read(accountServiceProvider);
    if (profile == null || service == null) {
      throw const AppFailure(FailureKind.unknown, technical: 'no-profile');
    }
    final next = await service.updateProfile(
      profile: profile,
      displayName: displayName,
      bio: bio,
      country: country,
      ageGroup: ageGroup,
    );
    ref.read(profileProvider.notifier).apply(next);
    state = state?.copyWith(
      displayName: next.displayName,
      country: next.country,
      bio: next.bio,
    );
    return next;
  }

  Future<void> publishStats(
    ProfileStats stats, {
    List<ProfileFavorite>? favorites,
  }) async {
    final profile = ref.read(profileProvider);
    final service = ref.read(accountServiceProvider);
    if (profile == null || service == null) return;
    try {
      final next = await service.publishStats(
        profile,
        stats,
        favorites: favorites,
      );
      ref.read(profileProvider.notifier).apply(next);
    } on Object {
      // Offline: the next library change retries the publication.
    }
  }

  Future<UserProfile> updatePrivacy(ProfilePrivacy privacy) async {
    final profile = ref.read(profileProvider);
    final service = ref.read(accountServiceProvider);
    if (profile == null || service == null) {
      throw const AppFailure(FailureKind.unknown, technical: 'no-profile');
    }
    final next = await service.updatePrivacy(
      profile: profile,
      privacy: privacy,
    );
    ref.read(profileProvider.notifier).apply(next);
    return next;
  }

  Future<void> changeUsername(String username) async {
    final profile = ref.read(profileProvider);
    final service = ref.read(accountServiceProvider);
    if (profile == null || service == null) {
      throw const AppFailure(FailureKind.unknown, technical: 'no-profile');
    }
    final next = await service.changeUsername(
      profile: profile,
      username: username,
    );
    ref.read(profileProvider.notifier).apply(next);
    state = state?.copyWith(username: next.username);
    unawaited(ref.read(socialRepositoryProvider).syncAuthor(next));
  }

  Future<void> saveAvatar(String path) async {
    final profile = ref.read(profileProvider);
    final service = ref.read(accountServiceProvider);
    if (profile == null || service == null) return;
    final next = await service.saveAvatar(profile: profile, path: path);
    ref.read(profileProvider.notifier).apply(next);
    unawaited(ref.read(socialRepositoryProvider).syncAuthor(next));
  }

  Future<void> removeAvatar() async {
    final profile = ref.read(profileProvider);
    final service = ref.read(accountServiceProvider);
    if (profile == null || service == null) return;
    final next = await service.removeAvatar(profile);
    ref.read(profileProvider.notifier).apply(next);
    unawaited(ref.read(socialRepositoryProvider).syncAuthor(next));
  }

  Future<void> saveCover(String path) async {
    final profile = ref.read(profileProvider);
    final service = ref.read(accountServiceProvider);
    if (profile == null || service == null) {
      throw const AppFailure(FailureKind.unknown, technical: 'no-profile');
    }
    final next = await service.saveCover(profile: profile, path: path);
    ref.read(profileProvider.notifier).apply(next);
  }

  Future<void> removeCover() async {
    final profile = ref.read(profileProvider);
    final service = ref.read(accountServiceProvider);
    if (profile == null || service == null) return;
    final next = await service.removeCover(profile);
    ref.read(profileProvider.notifier).apply(next);
  }

  Future<void> refreshProfile() => ref.read(profileProvider.notifier).reload();

  Future<bool> refreshEmailVerification() async {
    final verified = await ref
        .read(authRepositoryProvider)
        .refreshEmailVerification();
    final current = state;
    if (current != null) state = current.copyWith(emailVerified: verified);
    return verified;
  }

  Future<void> sendEmailVerification() =>
      ref.read(authRepositoryProvider).sendEmailVerification();

  Future<void> linkGoogle() async {
    await ref.read(authRepositoryProvider).linkGoogle();
    final current = state;
    if (current != null) await _refresh(current);
  }

  Future<void> signOut() async {
    _syncedUid = null;
    _lastSync = null;
    ref.read(profileResolvedProvider.notifier).update(false);
    await _badgesSubscription?.cancel();
    _badgesSubscription = null;
    final service = ref.read(accountServiceProvider);
    if (service != null) {
      await service.signOut();
    } else {
      await ref.read(authRepositoryProvider).signOut();
    }
    ref.read(profileProvider.notifier).apply(null);
    state = null;
  }

  Future<void> deleteAccount({String? password}) async {
    final current = state;
    if (current == null) return;
    final deletion = ref.read(accountDeletionProvider);
    if (deletion != null) {
      await deletion.deleteAccount(uid: current.id, password: password);
    } else {
      await ref.read(authRepositoryProvider).deleteCurrentUser();
    }
    ref.read(profileProvider.notifier).apply(null);
    ref.read(profileResolvedProvider.notifier).update(false);
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
