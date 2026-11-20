import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../data/models/admin_models.dart';
import '../../data/models/user_profile.dart';
import '../../data/repositories/admin_repository.dart';

/// Administrative data access. The rules — not this provider — decide whether a
/// write is allowed.
final adminRepositoryProvider = Provider<AdminRepository>(
  (ref) => AdminRepository(
    FirebaseFirestore.instance,
    ref.watch(httpClientProvider),
  ),
);

/// The trusted role of the signed-in account, read from `staff/{uid}`.
///
/// A missing document (or a refused read) resolves to [StaffRole.user], so an
/// ordinary account can never reach the console even by editing its own profile.
final staffRoleProvider = FutureProvider<StaffRole>((ref) async {
  final uid = ref.watch(authProvider)?.id;
  if (uid == null) return StaffRole.user;
  return ref.watch(adminRepositoryProvider).fetchRole(uid);
});

final isOwnerProvider = Provider<bool>((ref) {
  final role = ref.watch(staffRoleProvider).value ?? StaffRole.user;
  return role.isOwner;
});

final isAdminRoleProvider = Provider<bool>((ref) {
  final role = ref.watch(staffRoleProvider).value ?? StaffRole.user;
  return role.isAdmin;
});

/// The administrative record of the signed-in account, used to enforce
/// restrictions in the UI and to explain a suspension or a ban.
final myAccountStatusProvider = FutureProvider<AccountStatusRecord>((
  ref,
) async {
  final uid = ref.watch(authProvider)?.id;
  if (uid == null) return const AccountStatusRecord();
  try {
    final snapshot = await FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('admin')
        .doc('status')
        .get();
    final data = snapshot.data();
    if (!snapshot.exists || data == null) return const AccountStatusRecord();
    return AccountStatusRecord.fromMap(data);
  } on Object {
    return const AccountStatusRecord();
  }
});

/// True when the signed-in account may use [feature]. An empty status document
/// means an unrestricted account.
final canUseFeatureProvider = Provider.family<bool, RestrictionFeature>((
  ref,
  feature,
) {
  final status = ref.watch(myAccountStatusProvider).value;
  if (status == null) return true;
  final now = DateTime.now();
  if (status.isLockedAt(now)) return false;
  return !status.isRestricted(feature, now);
});

// ---------------------------------------------------------------- dashboard

class AdminOverview {
  const AdminOverview({
    required this.stats,
    required this.recentUsers,
    required this.recentActions,
  });

  final AdminStats stats;
  final List<AdminUserSummary> recentUsers;
  final List<AdminLogEntry> recentActions;
}

final adminOverviewProvider = FutureProvider<AdminOverview>((ref) async {
  final repository = ref.watch(adminRepositoryProvider);
  final results = await Future.wait<Object>(<Future<Object>>[
    repository.loadStats(),
    repository.recentUsers(),
    repository.recentActions(),
  ]);
  return AdminOverview(
    stats: results[0] as AdminStats,
    recentUsers: results[1] as List<AdminUserSummary>,
    recentActions: results[2] as List<AdminLogEntry>,
  );
});

// ------------------------------------------------------------- user browser

class AdminUsersState {
  const AdminUsersState({
    this.items = const <AdminUserSummary>[],
    this.loading = false,
    this.loadingMore = false,
    this.error = '',
    this.cursor,
    this.hasMore = false,
    this.query = '',
    this.status,
    this.oldestFirst = false,
  });

  final List<AdminUserSummary> items;
  final bool loading;
  final bool loadingMore;
  final String error;
  final QueryDocumentSnapshot<Map<String, dynamic>>? cursor;
  final bool hasMore;
  final String query;
  final AccountState? status;
  final bool oldestFirst;

  AdminUsersState copyWith({
    List<AdminUserSummary>? items,
    bool? loading,
    bool? loadingMore,
    String? error,
    QueryDocumentSnapshot<Map<String, dynamic>>? cursor,
    bool? hasMore,
    String? query,
    AccountState? status,
    bool clearStatus = false,
    bool? oldestFirst,
  }) => AdminUsersState(
    items: items ?? this.items,
    loading: loading ?? this.loading,
    loadingMore: loadingMore ?? this.loadingMore,
    error: error ?? this.error,
    cursor: cursor ?? this.cursor,
    hasMore: hasMore ?? this.hasMore,
    query: query ?? this.query,
    status: clearStatus ? null : (status ?? this.status),
    oldestFirst: oldestFirst ?? this.oldestFirst,
  );
}

class AdminUsersController extends Notifier<AdminUsersState> {
  @override
  AdminUsersState build() => const AdminUsersState();

  AdminRepository get _repository => ref.read(adminRepositoryProvider);

  Future<void> refresh() async {
    state = state.copyWith(loading: true, error: '');
    try {
      if (state.query.trim().isNotEmpty) {
        final items = await _repository.searchUsers(state.query.trim());
        state = state.copyWith(
          items: items,
          loading: false,
          hasMore: false,
          cursor: null,
        );
        return;
      }
      final page = await _repository.usersPage(
        status: state.status,
        oldestFirst: state.oldestFirst,
      );
      state = state.copyWith(
        items: page.items,
        cursor: page.cursor,
        hasMore: page.hasMore,
        loading: false,
        error: '',
      );
    } on Object {
      // The screen renders a translated message; the raw error never reaches it.
      state = state.copyWith(loading: false, error: 'failed');
    }
  }

  Future<void> loadMore() async {
    if (state.loadingMore || !state.hasMore || state.query.isNotEmpty) return;
    state = state.copyWith(loadingMore: true);
    try {
      final page = await _repository.usersPage(
        cursor: state.cursor,
        status: state.status,
        oldestFirst: state.oldestFirst,
      );
      state = state.copyWith(
        items: <AdminUserSummary>[...state.items, ...page.items],
        cursor: page.cursor,
        hasMore: page.hasMore,
        loadingMore: false,
      );
    } on Object {
      state = state.copyWith(loadingMore: false, error: 'failed');
    }
  }

  Future<void> setStatus(AccountState? status) async {
    state = state.copyWith(status: status, clearStatus: status == null);
    await refresh();
  }

  Future<void> setOrder({required bool oldestFirst}) async {
    state = state.copyWith(oldestFirst: oldestFirst);
    await refresh();
  }

  Future<void> search(String value) async {
    state = state.copyWith(query: value);
    await refresh();
  }
}

final adminUsersProvider =
    NotifierProvider<AdminUsersController, AdminUsersState>(
      AdminUsersController.new,
    );

/// One account's full administrative record.
final adminUserDetailProvider = FutureProvider.autoDispose
    .family<AdminUserDetail, String>((ref, uid) {
      return ref.watch(adminRepositoryProvider).loadUser(uid);
    });

// ------------------------------------------------------------------ reports

class AdminReportsState {
  const AdminReportsState({
    this.items = const <AdminReport>[],
    this.appeals = const <AdminAppeal>[],
    this.reviews = const <IdentityReview>[],
    this.loading = false,
    this.error = '',
    this.status = 'pending',
    this.cursor,
    this.hasMore = false,
  });

  final List<AdminReport> items;
  final List<AdminAppeal> appeals;
  final List<IdentityReview> reviews;
  final bool loading;
  final String error;
  final String status;
  final QueryDocumentSnapshot<Map<String, dynamic>>? cursor;
  final bool hasMore;

  AdminReportsState copyWith({
    List<AdminReport>? items,
    List<AdminAppeal>? appeals,
    List<IdentityReview>? reviews,
    bool? loading,
    String? error,
    String? status,
    QueryDocumentSnapshot<Map<String, dynamic>>? cursor,
    bool? hasMore,
  }) => AdminReportsState(
    items: items ?? this.items,
    appeals: appeals ?? this.appeals,
    reviews: reviews ?? this.reviews,
    loading: loading ?? this.loading,
    error: error ?? this.error,
    status: status ?? this.status,
    cursor: cursor ?? this.cursor,
    hasMore: hasMore ?? this.hasMore,
  );
}

class AdminReportsController extends Notifier<AdminReportsState> {
  @override
  AdminReportsState build() => const AdminReportsState();

  AdminRepository get _repository => ref.read(adminRepositoryProvider);

  Future<void> refresh() async {
    state = state.copyWith(loading: true, error: '');
    // Both lists are fetched independently: a missing index on one query used
    // to empty the other tab as well.
    AdminPage<AdminReport>? page;
    List<AdminAppeal>? appeals;
    List<IdentityReview>? reviews;
    try {
      page = await _repository.reportsPage(status: state.status);
    } on Object {
      page = null;
    }
    try {
      appeals = await _repository.appeals();
    } on Object {
      appeals = null;
    }
    try {
      reviews = await _repository.identityReviews();
    } on Object {
      reviews = null;
    }
    state = state.copyWith(
      items: page?.items ?? state.items,
      cursor: page?.cursor,
      hasMore: page?.hasMore ?? false,
      appeals: appeals ?? state.appeals,
      reviews: reviews ?? state.reviews,
      loading: false,
      error: page == null || appeals == null || reviews == null ? 'failed' : '',
    );
  }

  Future<void> loadMore() async {
    if (!state.hasMore) return;
    try {
      final page = await _repository.reportsPage(
        status: state.status,
        cursor: state.cursor,
      );
      state = state.copyWith(
        items: <AdminReport>[...state.items, ...page.items],
        cursor: page.cursor,
        hasMore: page.hasMore,
      );
    } on Object {
      state = state.copyWith(error: 'failed');
    }
  }

  Future<void> setStatus(String status) async {
    state = state.copyWith(
      status: status,
      items: const <AdminReport>[],
      cursor: null,
    );
    await refresh();
  }

  /// Approving lifts the block immediately; rejecting keeps it in place.
  Future<bool> decideReview(
    IdentityReview review, {
    required bool approve,
    required String note,
    required String actorUid,
    required String actorName,
  }) async {
    try {
      await _repository.decideIdentityReview(
        review: review,
        approve: approve,
        note: note,
        actorUid: actorUid,
        actorName: actorName,
      );
      await refresh();
      return true;
    } on Object {
      state = state.copyWith(error: 'failed');
      return false;
    }
  }
}

final adminReportsProvider =
    NotifierProvider<AdminReportsController, AdminReportsState>(
      AdminReportsController.new,
    );

// -------------------------------------------------------------- owner inbox

final ownerInboxProvider = FutureProvider.autoDispose<List<OwnerMessage>>((
  ref,
) async {
  final uid = ref.watch(authProvider)?.id;
  if (uid == null) return const <OwnerMessage>[];
  return ref.watch(adminRepositoryProvider).inbox(uid);
});

final ownerUnreadProvider = Provider<int>((ref) {
  final items = ref.watch(ownerInboxProvider).value ?? const <OwnerMessage>[];
  return items.where((item) => !item.read).length;
});

final adminSentMessagesProvider =
    FutureProvider.autoDispose<AdminPage<OwnerMessage>>((ref) {
      return ref.watch(adminRepositoryProvider).sentMessages();
    });

// ------------------------------------------------------------------- blocks

final blockedEmailsProvider = FutureProvider.autoDispose<List<BlockedIdentity>>(
  (ref) {
    return ref.watch(adminRepositoryProvider).blockedEmails();
  },
);

final blockedUsernamesProvider =
    FutureProvider.autoDispose<List<BlockedIdentity>>((ref) {
      return ref.watch(adminRepositoryProvider).blockedUsernames();
    });

// ------------------------------------------------------------ announcements

final announcementsProvider =
    FutureProvider.autoDispose<AdminPage<Announcement>>((ref) {
      return ref.watch(adminRepositoryProvider).announcementsPage();
    });

final liveAnnouncementsProvider =
    FutureProvider.autoDispose<List<Announcement>>((ref) {
      return ref.watch(adminRepositoryProvider).liveAnnouncements();
    });

// --------------------------------------------------------------- activity log

class AdminLogState {
  const AdminLogState({
    this.items = const <AdminLogEntry>[],
    this.loading = false,
    this.loadingMore = false,
    this.error = '',
    this.cursor,
    this.hasMore = false,
  });

  final List<AdminLogEntry> items;
  final bool loading;
  final bool loadingMore;
  final String error;
  final QueryDocumentSnapshot<Map<String, dynamic>>? cursor;
  final bool hasMore;

  AdminLogState copyWith({
    List<AdminLogEntry>? items,
    bool? loading,
    bool? loadingMore,
    String? error,
    QueryDocumentSnapshot<Map<String, dynamic>>? cursor,
    bool? hasMore,
  }) => AdminLogState(
    items: items ?? this.items,
    loading: loading ?? this.loading,
    loadingMore: loadingMore ?? this.loadingMore,
    error: error ?? this.error,
    cursor: cursor ?? this.cursor,
    hasMore: hasMore ?? this.hasMore,
  );
}

class AdminLogController extends Notifier<AdminLogState> {
  @override
  AdminLogState build() => const AdminLogState();

  AdminRepository get _repository => ref.read(adminRepositoryProvider);

  Future<void> refresh() async {
    state = state.copyWith(loading: true, error: '');
    try {
      final page = await _repository.logPage();
      state = state.copyWith(
        items: page.items,
        cursor: page.cursor,
        hasMore: page.hasMore,
        loading: false,
      );
    } on Object {
      state = state.copyWith(loading: false, error: 'failed');
    }
  }

  Future<void> loadMore() async {
    if (state.loadingMore || !state.hasMore) return;
    state = state.copyWith(loadingMore: true);
    try {
      final page = await _repository.logPage(cursor: state.cursor);
      state = state.copyWith(
        items: <AdminLogEntry>[...state.items, ...page.items],
        cursor: page.cursor,
        hasMore: page.hasMore,
        loadingMore: false,
      );
    } on Object {
      state = state.copyWith(loadingMore: false, error: 'failed');
    }
  }
}

final adminLogProvider = NotifierProvider<AdminLogController, AdminLogState>(
  AdminLogController.new,
);

// ----------------------------------------------------------------- monitor

final monitorProvider = FutureProvider.autoDispose<List<SourceHealth>>((ref) {
  return ref.watch(adminRepositoryProvider).monitorState();
});

// --------------------------------------------------------- owner signature

/// The Owner's own published signature, used on messages.
final ownerSignatureProvider = FutureProvider<ProfileBadges?>((ref) async {
  final uid = ref.watch(authProvider)?.id;
  if (uid == null) return null;
  try {
    return await ref.watch(userRepositoryProvider).fetchBadges(uid);
  } on Object {
    return null;
  }
});
