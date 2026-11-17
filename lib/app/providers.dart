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

import 'package:cloud_firestore/cloud_firestore.dart';

import '../core/errors/app_failure.dart';
import '../data/auth/account_deletion_service.dart';
import '../data/auth/account_service.dart';
import '../data/auth/firebase_auth_repository.dart';
import '../data/models/user_profile.dart';
import '../data/repositories/avatar_repository.dart';
import '../data/repositories/social_repository.dart';
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

  /// Re-reads the store after a cloud pull.
  void refresh() => state = _read();

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
  }

  Future<void> setStatus(Anime anime, LibraryStatus status) async {
    await _repo.setStatus(anime, status);
    state = _read();
    final entry = _repo.entryFor(anime.id);
    if (entry != null) {
      await _push((sync, uid) => sync.pushEntry(uid, entry));
    }
  }

  Future<void> removeFromLibrary(String animeId) async {
    await _repo.removeFromLibrary(animeId);
    state = _read();
    await _push((sync, uid) => sync.deleteEntry(uid, animeId));
  }

  Future<void> saveProgress(
    WatchHistoryEntry entry, {
    required bool completed,
  }) async {
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
  (ref) => SocialRepository(FirebaseFirestore.instance),
);

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

/// Public profile of another user, read from the privacy-filtered mirror.
final publicProfileProvider = StreamProvider.autoDispose
    .family<UserProfile?, String>(
      (ref, uid) => ref.watch(userRepositoryProvider).watchPublic(uid),
    );

class AuthController extends Notifier<AuthUser?> {
  @override
  AuthUser? build() {
    final repository = ref.watch(authRepositoryProvider);
    final subscription = repository.authChanges.listen(_onAuthChanged);
    ref.onDispose(subscription.cancel);
    final current = repository.currentUser;
    if (current != null) {
      Future<void>.microtask(() => _refresh(current));
    }
    return current;
  }

  Future<void> _onAuthChanged(AuthUser? user) async {
    if (user == null) {
      ref.read(profileProvider.notifier).apply(null);
      state = null;
      return;
    }
    await _refresh(user);
  }

  /// Loads the profile document so screens always read the authoritative
  /// username, display name and country.
  Future<void> _refresh(AuthUser user) async {
    try {
      final profile = await ref.read(userRepositoryProvider).fetch(user.id);
      if (profile != null) {
        ref.read(profileProvider.notifier).apply(profile);
        state = user.copyWith(
          displayName: profile.displayName,
          username: profile.username,
          country: profile.country,
          bio: profile.bio,
        );
        await _afterAccountReady();
        return;
      }
    } on Object {
      // Offline or not permitted; the identity state remains valid.
    }
    state = user;
    await _afterAccountReady();
  }

  /// Applies data that the account sync pulled while signing in.
  Future<void> _afterAccountReady() async {
    try {
      ref.read(libraryProvider.notifier).refresh();
      await ref.read(settingsProvider.notifier).reloadFromStore();
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

  Future<void> publishStats(ProfileStats stats) async {
    final profile = ref.read(profileProvider);
    final service = ref.read(accountServiceProvider);
    if (profile == null || service == null) return;
    await service.publishStats(profile, stats);
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
  }

  Future<void> saveAvatar(String path) async {
    final profile = ref.read(profileProvider);
    final service = ref.read(accountServiceProvider);
    if (profile == null || service == null) return;
    final next = await service.saveAvatar(profile: profile, path: path);
    ref.read(profileProvider.notifier).apply(next);
  }

  Future<void> removeAvatar() async {
    final profile = ref.read(profileProvider);
    final service = ref.read(accountServiceProvider);
    if (profile == null || service == null) return;
    final next = await service.removeAvatar(profile);
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
