import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:dio/dio.dart';

import '../models/admin_models.dart';
import '../models/user_profile.dart';
import '../username/username_rules.dart';

/// One page of an administratively browsed collection.
class AdminPage<T> {
  const AdminPage({required this.items, this.cursor, this.hasMore = false});

  final List<T> items;

  /// Pass back to the next call to continue after the last document.
  final QueryDocumentSnapshot<Map<String, dynamic>>? cursor;
  final bool hasMore;
}

/// All administrative reads and writes.
///
/// No Cloud Function runs in this project (the free plan does not include
/// them), so the trust boundary is Firestore itself: every write below is
/// re-checked by `firestore.rules` against `staff/{uid}`, which only the
/// Firebase console can grant. The client never decides whether an action is
/// allowed — it only asks for it.
class AdminRepository {
  AdminRepository(this._db, this._dio);

  final FirebaseFirestore _db;
  final Dio _dio;

  static const String staffCollection = 'staff';
  static const String logCollection = 'adminLog';
  static const String ownerMessagesCollection = 'ownerMessages';
  static const String reportsCollection = 'reports';
  static const String appealsCollection = 'appeals';
  static const String announcementsCollection = 'announcements';
  static const String emailBlocksCollection = 'emailBlocks';
  static const String usernameBlocksCollection = 'blockedUsernames';
  static const String monitorCollection = 'systemMonitor';

  // ------------------------------------------------------------- role

  /// The trusted role of [uid]. `staff/{uid}` is readable only by its owner, and
  /// writable only from the console (or by an Owner for a non-owner role).
  Future<StaffRole> fetchRole(String uid) async {
    try {
      final snapshot = await _db.collection(staffCollection).doc(uid).get();
      return StaffRole.fromId(snapshot.data()?['role']);
    } on Object {
      return StaffRole.user;
    }
  }

  Stream<StaffRole> watchRole(String uid) => _db
      .collection(staffCollection)
      .doc(uid)
      .snapshots()
      .map((snapshot) => StaffRole.fromId(snapshot.data()?['role']))
      .handleError((Object _) => StaffRole.user);

  /// Owner-only: grants `moderator` or `admin`. An Owner role itself can only be
  /// granted from the console, so nobody can promote themselves to Owner.
  Future<void> assignRole({
    required String uid,
    required StaffRole role,
    required String actorUid,
    required String actorName,
    String targetLabel = '',
  }) async {
    if (role == StaffRole.owner) {
      throw StateError('owner-role-console-only');
    }
    final batch = _db.batch();
    batch.set(_db.collection(staffCollection).doc(uid), <String, dynamic>{
      'role': role.id,
      'updatedAt': FieldValue.serverTimestamp(),
      'grantedBy': actorUid,
    }, SetOptions(merge: true));
    batch.set(_db.collection('users').doc(uid), <String, dynamic>{
      'staffRole': role.id,
    }, SetOptions(merge: true));
    _logInto(
      batch,
      action: AdminAction.roleChange,
      actorUid: actorUid,
      actorName: actorName,
      targetUid: uid,
      targetLabel: targetLabel,
      details: role.id,
    );
    await batch.commit();
  }

  // ------------------------------------------------------------ stats

  /// Dashboard counters. Each number is a server-side `count()` aggregation, so
  /// a thousand accounts still cost one read instead of a thousand.
  Future<AdminStats> loadStats() async {
    final now = DateTime.now();
    final startOfDay = DateTime(now.year, now.month, now.day);
    final startOfWeek = startOfDay.subtract(Duration(days: now.weekday - 1));
    final users = _db.collection('users');
    final reports = _db.collection(reportsCollection);

    Future<int> count(Query<Map<String, dynamic>> query) async {
      try {
        final snapshot = await query.count().get();
        return snapshot.count ?? 0;
      } on Object {
        return 0;
      }
    }

    final results = await Future.wait<int>(<Future<int>>[
      count(users),
      count(users.where('createdAt', isGreaterThanOrEqualTo: startOfDay)),
      count(users.where('createdAt', isGreaterThanOrEqualTo: startOfWeek)),
      count(users.where('status', isEqualTo: AccountState.active.id)),
      count(users.where('status', isEqualTo: AccountState.warned.id)),
      count(users.where('status', isEqualTo: AccountState.restricted.id)),
      count(users.where('status', isEqualTo: AccountState.suspended.id)),
      count(users.where('status', isEqualTo: AccountState.banned.id)),
      count(users.where('status', isEqualTo: AccountState.underReview.id)),
      count(reports.where('status', isEqualTo: 'open')),
      count(reports.where('status', isEqualTo: 'review')),
      count(reports.where('status', isEqualTo: 'resolved')),
      count(reports.where('status', isEqualTo: 'rejected')),
      count(
        _db.collection(appealsCollection).where('status', isEqualTo: 'pending'),
      ),
      count(_db.collection(ownerMessagesCollection)),
    ]);

    return AdminStats(
      totalUsers: results[0],
      registeredToday: results[1],
      registeredThisWeek: results[2],
      activeAccounts: results[3],
      warnedAccounts: results[4],
      restrictedAccounts: results[5],
      suspendedAccounts: results[6],
      bannedAccounts: results[7],
      underReviewAccounts: results[8],
      pendingReports: results[9],
      reviewingReports: results[10],
      resolvedReports: results[11],
      rejectedReports: results[12],
      pendingAppeals: results[13],
      totalOwnerMessages: results[14],
      loadedAt: DateTime.now(),
    );
  }

  /// Newest registrations, one page.
  Future<List<AdminUserSummary>> recentUsers({int limit = 8}) async {
    final snapshot = await _db
        .collection('users')
        .orderBy('createdAt', descending: true)
        .limit(limit)
        .get();
    return snapshot.docs
        .map((doc) => AdminUserSummary.fromDoc(doc.id, doc.data()))
        .toList(growable: false);
  }

  Future<List<AdminLogEntry>> recentActions({int limit = 8}) async {
    final snapshot = await _db
        .collection(logCollection)
        .orderBy('createdAt', descending: true)
        .limit(limit)
        .get();
    return snapshot.docs
        .map((doc) => AdminLogEntry.fromDoc(doc.id, doc.data()))
        .toList(growable: false);
  }

  // ------------------------------------------------------- user browser

  /// One page of accounts, newest first. Used with [AdminPage.cursor] so the
  /// whole collection is never loaded.
  Future<AdminPage<AdminUserSummary>> usersPage({
    QueryDocumentSnapshot<Map<String, dynamic>>? cursor,
    AccountState? status,
    int limit = 20,
    bool oldestFirst = false,
  }) async {
    Query<Map<String, dynamic>> query = _db.collection('users');
    final filtered = status != null && status != AccountState.active;
    if (filtered) query = query.where('status', isEqualTo: status.id);
    // `orderBy(createdAt)` needs no extra index; a status filter adds one
    // composite index (documented in firestore.indexes.json).
    query = query.orderBy('createdAt', descending: !oldestFirst);
    if (cursor != null) query = query.startAfterDocument(cursor);
    final snapshot = await query.limit(limit + 1).get();
    final docs = snapshot.docs;
    final hasMore = docs.length > limit;
    final page = hasMore ? docs.take(limit).toList() : docs;
    return AdminPage<AdminUserSummary>(
      items: page
          .map((doc) => AdminUserSummary.fromDoc(doc.id, doc.data()))
          .toList(growable: false),
      cursor: page.isEmpty ? cursor : page.last,
      hasMore: hasMore,
    );
  }

  /// Prefix search on the normalized handle. One range scan, no collection
  /// download, and it respects the same normalization as registration.
  Future<List<AdminUserSummary>> searchUsers(
    String raw, {
    int limit = 20,
  }) async {
    final normalized = UsernameRules.normalize(raw);
    if (normalized.isEmpty) return const <AdminUserSummary>[];

    // Exact handle first: it is a single document lookup.
    final exact = await _db
        .collection('users')
        .where('normalizedUsername', isEqualTo: normalized)
        .limit(1)
        .get();
    if (exact.docs.isNotEmpty) {
      return exact.docs
          .map((doc) => AdminUserSummary.fromDoc(doc.id, doc.data()))
          .toList(growable: false);
    }
    final snapshot = await _db
        .collection('users')
        .where('normalizedUsername', isGreaterThanOrEqualTo: normalized)
        .where('normalizedUsername', isLessThan: '$normalized\uf8ff')
        .orderBy('normalizedUsername')
        .limit(limit)
        .get();
    return snapshot.docs
        .map((doc) => AdminUserSummary.fromDoc(doc.id, doc.data()))
        .toList(growable: false);
  }

  DocumentReference<Map<String, dynamic>> _statusRef(String uid) =>
      _db.collection('users').doc(uid).collection('admin').doc('status');

  /// Reads the full administrative record of one account, its warnings, its
  /// history and the reports filed against it.
  Future<AdminUserDetail> loadUser(
    String uid, {
    StaffRole role = StaffRole.user,
  }) async {
    final userDoc = await _db.collection('users').doc(uid).get();
    if (!userDoc.exists || userDoc.data() == null) {
      throw StateError('user-not-found');
    }
    final data = userDoc.data()!;
    final results = await Future.wait<Object?>(<Future<Object?>>[
      _statusRef(uid).get(),
      _db.collection('users').doc(uid).collection('warnings').limit(50).get(),
      _db
          .collection(logCollection)
          .where('targetUid', isEqualTo: uid)
          .limit(50)
          .get(),
      _db
          .collection(reportsCollection)
          .where('targetUid', isEqualTo: uid)
          .limit(20)
          .get(),
      _db
          .collection('users')
          .doc(uid)
          .collection('ownerMessages')
          .limit(20)
          .get(),
    ]);

    final statusDoc = results[0] as DocumentSnapshot<Map<String, dynamic>>;
    final warnings = (results[1] as QuerySnapshot<Map<String, dynamic>>).docs
        .map((doc) => AdminWarning.fromDoc(doc.id, doc.data()))
        .toList(growable: false);
    warnings.sort(
      (a, b) =>
          (b.issuedAt ?? DateTime(0)).compareTo(a.issuedAt ?? DateTime(0)),
    );
    final history = (results[2] as QuerySnapshot<Map<String, dynamic>>).docs
        .map((doc) => AdminLogEntry.fromDoc(doc.id, doc.data()))
        .toList(growable: false);
    history.sort(
      (a, b) =>
          (b.createdAt ?? DateTime(0)).compareTo(a.createdAt ?? DateTime(0)),
    );
    final reports = (results[3] as QuerySnapshot<Map<String, dynamic>>).docs
        .map((doc) => AdminReport.fromDoc(doc.id, doc.data()))
        .toList(growable: false);
    final messages = (results[4] as QuerySnapshot<Map<String, dynamic>>).docs
        .map((doc) => OwnerMessage.fromDoc(doc.id, doc.data()))
        .toList(growable: false);

    return AdminUserDetail(
      summary: AdminUserSummary.fromDoc(uid, data),
      status: statusDoc.exists && statusDoc.data() != null
          ? AccountStatusRecord.fromMap(statusDoc.data()!)
          : const AccountStatusRecord(),
      warnings: warnings,
      history: history,
      reports: reports,
      ownerMessages: messages,
      role: StaffRole.fromId(data['staffRole']),
      pendingDeletion: data['pendingDeletion'] == true,
    );
  }

  /// Records that an Owner opened a private profile. The write is a log entry
  /// only: privacy, badges and the profile itself are untouched.
  Future<void> logPrivateProfileAccess({
    required String targetUid,
    required String targetLabel,
    required String actorUid,
    required String actorName,
  }) async {
    final batch = _db.batch();
    _logInto(
      batch,
      action: AdminAction.privateProfileAccess,
      actorUid: actorUid,
      actorName: actorName,
      targetUid: targetUid,
      targetLabel: targetLabel,
      reason: 'private-profile',
    );
    await batch.commit();
  }

  // ------------------------------------------------------ status writes

  /// Applies a new account state, its restrictions, the notification and the log
  /// entry in one atomic batch.
  Future<void> applyStatus({
    required AdminUserSummary target,
    required AccountStatusRecord status,
    required String reason,
    required String actorUid,
    required String actorName,
    required AdminAction action,
    required String notificationTitle,
    required String notificationBody,
    String notificationRoute = '/account-status',
    List<AdminWarning>? warnings,
  }) async {
    final batch = _db.batch();
    final actionRef = _db.collection(logCollection).doc();
    final now = DateTime.now();

    final record = AccountStatusRecord(
      state: status.state,
      reason: reason,
      startedAt: status.startedAt ?? now,
      expiresAt: status.expiresAt,
      permanent: status.permanent,
      actorUid: actorUid,
      actionId: actionRef.id,
      previousState: status.previousState,
      restrictions: status.restrictions,
      restrictionsPermanent: status.restrictionsPermanent,
      restrictionsExpireAt: status.restrictionsExpireAt,
      updatedAt: now,
    );

    batch.set(_statusRef(target.uid), record.toMap());
    batch.set(_db.collection('users').doc(target.uid), <String, dynamic>{
      'status': record.state.id,
      'statusUpdatedAt': FieldValue.serverTimestamp(),
      'warningCount':
          warnings?.where((item) => item.active).length ?? target.warningCount,
    }, SetOptions(merge: true));
    batch.set(actionRef, <String, dynamic>{
      'action': action.id,
      'actorUid': actorUid,
      'actorName': actorName,
      'targetUid': target.uid,
      'targetLabel': target.label,
      'reason': reason,
      'details': record.state.id,
      'previousState': record.previousState.id,
      'nextState': record.state.id,
      'createdAt': FieldValue.serverTimestamp(),
    });
    batch.set(
      _db.collection('users').doc(target.uid).collection('notifications').doc(),
      <String, dynamic>{
        'type': 'admin',
        'kind': action.id,
        'toUid': target.uid,
        'actorUid': actorUid,
        'actorName': actorName,
        'title': notificationTitle,
        'body': notificationBody,
        'route': notificationRoute,
        'read': false,
        'createdAt': FieldValue.serverTimestamp(),
      },
    );
    await batch.commit();
  }

  Future<void> issueWarning({
    required AdminUserSummary target,
    required AdminUserDetail detail,
    required String category,
    required String reason,
    required String actorUid,
    required String actorName,
    required String notificationTitle,
    required String notificationBody,
  }) async {
    final batch = _db.batch();
    final actionRef = _db.collection(logCollection).doc();
    final warningRef = _db
        .collection('users')
        .doc(target.uid)
        .collection('warnings')
        .doc();
    batch.set(warningRef, <String, dynamic>{
      'category': category,
      'reason': reason,
      'issuedAt': FieldValue.serverTimestamp(),
      'actorUid': actorUid,
      'actorName': actorName,
      'active': true,
    });
    final now = DateTime.now();
    final next = AccountStatusRecord(
      state: detail.status.effectiveState(now) == AccountState.active
          ? AccountState.warned
          : detail.status.state,
      reason: reason,
      startedAt: now,
      expiresAt: detail.status.expiresAt,
      permanent: detail.status.permanent,
      actorUid: actorUid,
      actionId: actionRef.id,
      previousState: detail.status.state,
      restrictions: detail.status.restrictions,
      restrictionsPermanent: detail.status.restrictionsPermanent,
      restrictionsExpireAt: detail.status.restrictionsExpireAt,
    );
    batch.set(_statusRef(target.uid), next.toMap());
    batch.set(_db.collection('users').doc(target.uid), <String, dynamic>{
      'status': next.state.id,
      'warningCount': detail.warnings.where((item) => item.active).length + 1,
      'statusUpdatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    batch.set(actionRef, <String, dynamic>{
      'action': AdminAction.warn.id,
      'actorUid': actorUid,
      'actorName': actorName,
      'targetUid': target.uid,
      'targetLabel': target.label,
      'reason': reason,
      'details': category,
      'previousState': detail.status.state.id,
      'nextState': next.state.id,
      'createdAt': FieldValue.serverTimestamp(),
    });
    _notifyInto(
      batch,
      toUid: target.uid,
      actorUid: actorUid,
      actorName: actorName,
      kind: AdminAction.warn.id,
      title: notificationTitle,
      body: notificationBody,
      route: '/account-status',
    );
    await batch.commit();
  }

  Future<void> revokeWarning({
    required AdminUserSummary target,
    required String warningId,
    required String reason,
    required String actorUid,
    required String actorName,
  }) async {
    final batch = _db.batch();
    batch.set(
      _db
          .collection('users')
          .doc(target.uid)
          .collection('warnings')
          .doc(warningId),
      <String, dynamic>{
        'active': false,
        'revokedAt': FieldValue.serverTimestamp(),
        'revokedBy': actorUid,
        'revokeReason': reason,
      },
      SetOptions(merge: true),
    );
    _logInto(
      batch,
      action: AdminAction.revokeWarning,
      actorUid: actorUid,
      actorName: actorName,
      targetUid: target.uid,
      targetLabel: target.label,
      reason: reason,
      details: warningId,
    );
    await batch.commit();
  }

  /// Full account deletion from the Owner console.
  ///
  /// The Firebase Authentication account itself cannot be removed from a client
  /// without the Admin SDK (which needs a paid backend), so this removes every
  /// Firestore record, the username reservation, the public mirror and the
  /// comments, and marks the account `deleted`. Security rules then refuse every
  /// write from that account, and the app signs it out on its next start.
  Future<List<String>> deleteAccount({
    required AdminUserSummary target,
    required String reason,
    required String actorUid,
    required String actorName,
    required String notificationTitle,
    required String notificationBody,
  }) async {
    final blocked = <String>[];
    final detail = await loadUser(target.uid);
    // 1. The notice and the status go first, so a failure later still leaves the
    //    account locked and the reason recorded.
    await applyStatus(
      target: target,
      status: AccountStatusRecord(
        state: AccountState.deleted,
        reason: reason,
        startedAt: DateTime.now(),
        permanent: true,
        actorUid: actorUid,
        previousState: detail.status.state,
        restrictions: detail.status.restrictions,
        restrictionsPermanent: true,
      ),
      reason: reason,
      actorUid: actorUid,
      actorName: actorName,
      action: AdminAction.deleteAccount,
      notificationTitle: notificationTitle,
      notificationBody: notificationBody,
      notificationRoute: '/account-status',
    );

    Future<void> guard(Future<void> Function() action, String step) async {
      try {
        await action();
      } on Object {
        blocked.add(step);
      }
    }

    // 2. Comments and replies, found through the account's activity index.
    await guard(() async {
      final activity = await _db
          .collection('users')
          .doc(target.uid)
          .collection('activity')
          .limit(500)
          .get();
      final paths = activity.docs
          .map((doc) => doc.data()['path'])
          .whereType<String>()
          .toList();
      for (var index = 0; index < paths.length; index += 400) {
        final batch = _db.batch();
        for (final path in paths.skip(index).take(400)) {
          batch.delete(_db.doc(path));
        }
        await batch.commit();
      }
    }, 'comments');

    // 3. The username reservation is released, so the handle becomes claimable
    //    again (a blocked handle stays blocked by its own record).
    await guard(() async {
      final username = detail.summary.username;
      if (username.isEmpty) return;
      await _db
          .collection('usernames')
          .doc(UsernameRules.normalize(username))
          .delete();
    }, 'username');

    // 4. Owned subcollections, in chunks.
    for (final name in const <String>[
      'library',
      'history',
      'settings',
      'meta',
      'activity',
      'notifications',
      'episodes',
      'search',
      'warnings',
      'admin',
      'private',
    ]) {
      await guard(() async {
        final collection = _db
            .collection('users')
            .doc(target.uid)
            .collection(name);
        while (true) {
          final snapshot = await collection.limit(100).get();
          if (snapshot.docs.isEmpty) return;
          final batch = _db.batch();
          for (final doc in snapshot.docs) {
            batch.delete(doc.reference);
          }
          await batch.commit();
          if (snapshot.docs.length < 100) return;
        }
      }, name);
    }

    // 5. The public mirror, then the owner document.
    await guard(
      () => _db.collection('profiles').doc(target.uid).delete(),
      'profile',
    );
    await guard(
      () => _db.collection('users').doc(target.uid).delete(),
      'account',
    );
    return blocked;
  }

  // --------------------------------------------------------- owner messages

  Future<void> sendOwnerMessage({
    required AdminUserSummary target,
    required String title,
    required String body,
    required String actorUid,
    required String actorName,
    required String actorUsername,
    required int actorPhotoVersion,
  }) async {
    final batch = _db.batch();
    final ref = _db.collection(ownerMessagesCollection).doc();
    final payload = <String, dynamic>{
      'toUid': target.uid,
      'toUsername': target.username,
      'fromUid': actorUid,
      'fromName': actorName,
      'fromUsername': actorUsername,
      'fromPhotoVersion': actorPhotoVersion,
      'title': title,
      'body': body,
      'read': false,
      'createdAt': FieldValue.serverTimestamp(),
    };
    // Staff-only history index.
    batch.set(ref, payload);
    // The recipient's private copy. Rules let nobody else read this path, which
    // is what keeps an Owner message out of every other inbox.
    batch.set(
      _db
          .collection('users')
          .doc(target.uid)
          .collection('ownerMessages')
          .doc(ref.id),
      payload,
    );
    _notifyInto(
      batch,
      toUid: target.uid,
      actorUid: actorUid,
      actorName: actorName,
      kind: 'ownerMessage',
      title: title.isEmpty ? 'رسالة من مطوّر Wings' : title,
      body: body.length > 180 ? '${body.substring(0, 180)}…' : body,
      route: '/owner-message/${ref.id}',
    );
    _logInto(
      batch,
      action: AdminAction.ownerMessage,
      actorUid: actorUid,
      actorName: actorName,
      targetUid: target.uid,
      targetLabel: target.label,
      details: ref.id,
    );
    await batch.commit();
  }

  Future<AdminPage<OwnerMessage>> sentMessages({
    QueryDocumentSnapshot<Map<String, dynamic>>? cursor,
    int limit = 20,
  }) async {
    Query<Map<String, dynamic>> query = _db
        .collection(ownerMessagesCollection)
        .orderBy('createdAt', descending: true);
    if (cursor != null) query = query.startAfterDocument(cursor);
    final snapshot = await query.limit(limit + 1).get();
    final docs = snapshot.docs;
    final hasMore = docs.length > limit;
    final page = hasMore ? docs.take(limit).toList() : docs;
    return AdminPage<OwnerMessage>(
      items: page
          .map((doc) => OwnerMessage.fromDoc(doc.id, doc.data()))
          .toList(growable: false),
      cursor: page.isEmpty ? cursor : page.last,
      hasMore: hasMore,
    );
  }

  /// Messages addressed to one account, read from its own private copy. A
  /// query without an orderBy only needs the automatic single-field index.
  Future<List<OwnerMessage>> inbox(String uid, {int limit = 30}) async {
    final snapshot = await _db
        .collection('users')
        .doc(uid)
        .collection('ownerMessages')
        .limit(limit)
        .get();
    final items = snapshot.docs
        .map((doc) => OwnerMessage.fromDoc(doc.id, doc.data()))
        .toList(growable: false);
    items.sort(
      (a, b) =>
          (b.createdAt ?? DateTime(0)).compareTo(a.createdAt ?? DateTime(0)),
    );
    return items;
  }

  Future<OwnerMessage?> message(String id, String uid) async {
    final snapshot = await _db
        .collection('users')
        .doc(uid)
        .collection('ownerMessages')
        .doc(id)
        .get();
    if (!snapshot.exists || snapshot.data() == null) return null;
    return OwnerMessage.fromDoc(snapshot.id, snapshot.data()!);
  }

  Future<void> markMessageRead(String id, String uid) => _db
      .collection('users')
      .doc(uid)
      .collection('ownerMessages')
      .doc(id)
      .set(<String, dynamic>{'read': true}, SetOptions(merge: true));

  // -------------------------------------------------------------- blocks

  Future<bool> isEmailBlocked(String email) async {
    final normalized = email.trim().toLowerCase();
    if (normalized.isEmpty) return false;
    try {
      final snapshot = await _db
          .collection(emailBlocksCollection)
          .doc(normalized)
          .get(const GetOptions(source: Source.server));
      return snapshot.exists;
    } on Object {
      return false;
    }
  }

  Future<bool> isUsernameBlocked(String username) async {
    final normalized = UsernameRules.normalize(username);
    if (normalized.isEmpty) return false;
    try {
      final snapshot = await _db
          .collection(usernameBlocksCollection)
          .doc(normalized)
          .get(const GetOptions(source: Source.server));
      return snapshot.exists;
    } on Object {
      return false;
    }
  }

  Future<void> blockEmail({
    required String email,
    required String reason,
    required String actorUid,
    required String actorName,
  }) async {
    final normalized = email.trim().toLowerCase();
    if (normalized.isEmpty) throw StateError('empty-email');
    final batch = _db.batch();
    batch.set(
      _db.collection(emailBlocksCollection).doc(normalized),
      <String, dynamic>{
        'reason': reason,
        'actorUid': actorUid,
        'actorName': actorName,
        'createdAt': FieldValue.serverTimestamp(),
      },
    );
    _logInto(
      batch,
      action: AdminAction.blockEmail,
      actorUid: actorUid,
      actorName: actorName,
      targetLabel: normalized,
      reason: reason,
    );
    await batch.commit();
  }

  Future<void> unblockEmail({
    required String email,
    required String actorUid,
    required String actorName,
  }) async {
    final normalized = email.trim().toLowerCase();
    final batch = _db.batch();
    batch.delete(_db.collection(emailBlocksCollection).doc(normalized));
    _logInto(
      batch,
      action: AdminAction.unblockEmail,
      actorUid: actorUid,
      actorName: actorName,
      targetLabel: normalized,
    );
    await batch.commit();
  }

  Future<void> blockUsername({
    required String username,
    required String reason,
    required String actorUid,
    required String actorName,
  }) async {
    final normalized = UsernameRules.normalize(username);
    if (normalized.isEmpty) throw StateError('empty-username');
    final batch = _db.batch();
    batch.set(
      _db.collection(usernameBlocksCollection).doc(normalized),
      <String, dynamic>{
        'reason': reason,
        'actorUid': actorUid,
        'actorName': actorName,
        'createdAt': FieldValue.serverTimestamp(),
      },
    );
    _logInto(
      batch,
      action: AdminAction.blockUsername,
      actorUid: actorUid,
      actorName: actorName,
      targetLabel: normalized,
      reason: reason,
    );
    await batch.commit();
  }

  Future<void> unblockUsername({
    required String username,
    required String actorUid,
    required String actorName,
  }) async {
    final normalized = UsernameRules.normalize(username);
    final batch = _db.batch();
    batch.delete(_db.collection(usernameBlocksCollection).doc(normalized));
    _logInto(
      batch,
      action: AdminAction.unblockUsername,
      actorUid: actorUid,
      actorName: actorName,
      targetLabel: normalized,
    );
    await batch.commit();
  }

  Future<List<BlockedIdentity>> blockedEmails({int limit = 100}) async {
    final snapshot = await _db
        .collection(emailBlocksCollection)
        .orderBy('createdAt', descending: true)
        .limit(limit)
        .get();
    return snapshot.docs
        .map((doc) => BlockedIdentity.fromDoc(doc.id, doc.data()))
        .toList(growable: false);
  }

  Future<List<BlockedIdentity>> blockedUsernames({int limit = 100}) async {
    final snapshot = await _db
        .collection(usernameBlocksCollection)
        .orderBy('createdAt', descending: true)
        .limit(limit)
        .get();
    return snapshot.docs
        .map((doc) => BlockedIdentity.fromDoc(doc.id, doc.data()))
        .toList(growable: false);
  }

  // ------------------------------------------------------------- reports

  Future<AdminPage<AdminReport>> reportsPage({
    String? status,
    QueryDocumentSnapshot<Map<String, dynamic>>? cursor,
    int limit = 20,
  }) async {
    Query<Map<String, dynamic>> query = _db.collection(reportsCollection);
    if (status != null && status != 'all') {
      query = query.where(
        'status',
        isEqualTo: status == 'pending' ? 'open' : status,
      );
    }
    query = query.orderBy('createdAt', descending: true);
    if (cursor != null) query = query.startAfterDocument(cursor);
    final snapshot = await query.limit(limit + 1).get();
    final docs = snapshot.docs;
    final hasMore = docs.length > limit;
    final page = hasMore ? docs.take(limit).toList() : docs;
    return AdminPage<AdminReport>(
      items: page
          .map((doc) => AdminReport.fromDoc(doc.id, doc.data()))
          .toList(growable: false),
      cursor: page.isEmpty ? cursor : page.last,
      hasMore: hasMore,
    );
  }

  Future<void> updateReport({
    required AdminReport report,
    required String status,
    required String note,
    required String actorUid,
    required String actorName,
    String decision = '',
  }) async {
    final batch = _db.batch();
    batch.set(
      _db.collection(reportsCollection).doc(report.id),
      <String, dynamic>{
        'status': status == 'pending' ? 'open' : status,
        'note': note,
        'decision': decision,
        'reviewedBy': actorUid,
        'updatedAt': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );
    _logInto(
      batch,
      action: status == 'resolved' || status == 'rejected'
          ? AdminAction.reportResolve
          : AdminAction.reportReview,
      actorUid: actorUid,
      actorName: actorName,
      targetUid: report.targetUid,
      targetLabel: report.targetLabel,
      reason: note,
      details: '$status:${report.id}',
    );
    if (report.reporterUid.isNotEmpty) {
      _notifyInto(
        batch,
        toUid: report.reporterUid,
        actorUid: actorUid,
        actorName: actorName,
        kind: 'report',
        title: 'تحديث على بلاغك',
        body: decision.isEmpty ? 'تم تحديث حالة البلاغ: $status' : decision,
        route: '/notifications',
      );
    }
    await batch.commit();
  }

  Future<List<AdminAppeal>> appeals({int limit = 50}) async {
    final snapshot = await _db
        .collection(appealsCollection)
        .orderBy('createdAt', descending: true)
        .limit(limit)
        .get();
    return snapshot.docs
        .map((doc) => AdminAppeal.fromDoc(doc.id, doc.data()))
        .toList(growable: false);
  }

  Future<void> submitAppeal({
    required String uid,
    required String username,
    required String message,
  }) async {
    await _db.collection(appealsCollection).add(<String, dynamic>{
      'uid': uid,
      'username': username,
      'message': message,
      'status': 'pending',
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> decideAppeal({
    required AdminAppeal appeal,
    required String status,
    required String decision,
    required String actorUid,
    required String actorName,
  }) async {
    final batch = _db.batch();
    batch.set(
      _db.collection(appealsCollection).doc(appeal.id),
      <String, dynamic>{
        'status': status,
        'decision': decision,
        'decidedBy': actorUid,
        'decidedAt': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );
    _notifyInto(
      batch,
      toUid: appeal.uid,
      actorUid: actorUid,
      actorName: actorName,
      kind: 'appeal',
      title: 'قرار طلب المراجعة',
      body: decision.isEmpty ? 'تمت مراجعة طلبك.' : decision,
      route: '/account-status',
    );
    _logInto(
      batch,
      action: AdminAction.appealDecide,
      actorUid: actorUid,
      actorName: actorName,
      targetUid: appeal.uid,
      targetLabel: appeal.username,
      details: '$status:${appeal.id}',
    );
    await batch.commit();
  }

  // ------------------------------------------------------- announcements

  Future<AdminPage<Announcement>> announcementsPage({
    QueryDocumentSnapshot<Map<String, dynamic>>? cursor,
    int limit = 20,
  }) async {
    Query<Map<String, dynamic>> query = _db
        .collection(announcementsCollection)
        .orderBy('publishedAt', descending: true);
    if (cursor != null) query = query.startAfterDocument(cursor);
    final snapshot = await query.limit(limit + 1).get();
    final docs = snapshot.docs;
    final hasMore = docs.length > limit;
    final page = hasMore ? docs.take(limit).toList() : docs;
    return AdminPage<Announcement>(
      items: page
          .map((doc) => Announcement.fromDoc(doc.id, doc.data()))
          .toList(growable: false),
      cursor: page.isEmpty ? cursor : page.last,
      hasMore: hasMore,
    );
  }

  /// Latest live announcements for any signed-in member.
  Future<List<Announcement>> liveAnnouncements({int limit = 5}) async {
    final snapshot = await _db
        .collection(announcementsCollection)
        .orderBy('publishedAt', descending: true)
        .limit(limit)
        .get();
    final now = DateTime.now();
    return snapshot.docs
        .map((doc) => Announcement.fromDoc(doc.id, doc.data()))
        .where((item) => item.isLiveAt(now))
        .toList(growable: false);
  }

  Future<DateTime?> announcementReadMark(String uid) async {
    try {
      final snapshot = await _db
          .collection('users')
          .doc(uid)
          .collection('meta')
          .doc('announcements')
          .get();
      final value = snapshot.data()?['lastSeenAt'];
      return value is Timestamp ? value.toDate() : null;
    } on Object {
      return null;
    }
  }

  Future<void> markAnnouncementsSeen(String uid) => _db
      .collection('users')
      .doc(uid)
      .collection('meta')
      .doc('announcements')
      .set(<String, dynamic>{
        'lastSeenAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

  Future<void> publishAnnouncement({
    required Announcement announcement,
    required String actorUid,
    required String actorName,
  }) async {
    final batch = _db.batch();
    final ref = _db.collection(announcementsCollection).doc();
    // The rules bound the stored shape; clamping here keeps a long message from
    // being rejected outright.
    final title = announcement.title.trim();
    final body = announcement.body.trim();
    batch.set(ref, <String, dynamic>{
      'title': title.length > 120 ? title.substring(0, 120) : title,
      'body': body.length > 4000 ? body.substring(0, 4000) : body,
      'type': announcement.type.id,
      'actorUid': actorUid,
      'publishedAt': FieldValue.serverTimestamp(),
      'expiresAt': announcement.expiresAt == null
          ? null
          : Timestamp.fromDate(announcement.expiresAt!),
    });
    _logInto(
      batch,
      action: AdminAction.announcement,
      actorUid: actorUid,
      actorName: actorName,
      targetLabel: title,
      details: announcement.type.id,
    );
    await batch.commit();
  }

  Future<void> deleteAnnouncement({
    required String id,
    required String title,
    required String actorUid,
    required String actorName,
  }) async {
    final batch = _db.batch();
    batch.delete(_db.collection(announcementsCollection).doc(id));
    _logInto(
      batch,
      action: AdminAction.announcementDelete,
      actorUid: actorUid,
      actorName: actorName,
      targetLabel: title,
    );
    await batch.commit();
  }

  // ------------------------------------------------------------- logging

  Future<AdminPage<AdminLogEntry>> logPage({
    QueryDocumentSnapshot<Map<String, dynamic>>? cursor,
    int limit = 30,
  }) async {
    Query<Map<String, dynamic>> query = _db
        .collection(logCollection)
        .orderBy('createdAt', descending: true);
    if (cursor != null) query = query.startAfterDocument(cursor);
    final snapshot = await query.limit(limit + 1).get();
    final docs = snapshot.docs;
    final hasMore = docs.length > limit;
    final page = hasMore ? docs.take(limit).toList() : docs;
    return AdminPage<AdminLogEntry>(
      items: page
          .map((doc) => AdminLogEntry.fromDoc(doc.id, doc.data()))
          .toList(growable: false),
      cursor: page.isEmpty ? cursor : page.last,
      hasMore: hasMore,
    );
  }

  void _logInto(
    WriteBatch batch, {
    required AdminAction action,
    required String actorUid,
    required String actorName,
    String targetUid = '',
    String targetLabel = '',
    String reason = '',
    String details = '',
    String previousState = '',
    String nextState = '',
  }) {
    batch.set(_db.collection(logCollection).doc(), <String, dynamic>{
      'action': action.id,
      'actorUid': actorUid,
      'actorName': actorName,
      'targetUid': targetUid,
      'targetLabel': targetLabel,
      'reason': reason,
      'details': details,
      'previousState': previousState,
      'nextState': nextState,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  void _notifyInto(
    WriteBatch batch, {
    required String toUid,
    required String actorUid,
    required String actorName,
    required String kind,
    required String title,
    required String body,
    String route = '',
  }) {
    if (toUid.isEmpty) return;
    batch.set(
      _db.collection('users').doc(toUid).collection('notifications').doc(),
      <String, dynamic>{
        'type': 'admin',
        'kind': kind,
        'toUid': toUid,
        'actorUid': actorUid,
        'actorName': actorName,
        'title': title,
        'body': body,
        'route': route,
        'read': false,
        'createdAt': FieldValue.serverTimestamp(),
      },
    );
  }

  // -------------------------------------------------------- system monitor

  /// The three public sources the app depends on. A probe is deliberately tiny:
  /// one request per source, only when the Owner asks for it.
  static const List<(String, String, String)> probes =
      <(String, String, String)>[
        ('cartoony', 'كرتوني — سبيستون غو', 'https://cartoony.net'),
        ('carateen', 'كرتوني — كرتون أيام زمان', 'https://carateen.tv'),
        (
          'firestore',
          'Wings — Firestore API',
          'https://firestore.googleapis.com',
        ),
      ];

  Future<List<SourceHealth>> monitorState() async {
    final snapshot = await _db.collection(monitorCollection).limit(20).get();
    final stored = <String, SourceHealth>{
      for (final doc in snapshot.docs)
        doc.id: SourceHealth.fromDoc(doc.id, doc.data()),
    };
    return <SourceHealth>[
      for (final probe in probes)
        stored[probe.$1] ??
            SourceHealth(
              id: probe.$1,
              label: probe.$2,
              url: probe.$3,
              neverChecked: true,
            ),
    ];
  }

  /// Runs one lightweight GET per source and stores the result. No retry storm:
  /// each source is probed once per explicit refresh.
  Future<List<SourceHealth>> runMonitorChecks({
    required String actorUid,
    required String actorName,
  }) async {
    final results = <SourceHealth>[];
    for (final probe in probes) {
      final started = DateTime.now();
      var ok = false;
      var httpStatus = 0;
      var error = '';
      try {
        final response = await _dio.get<Object?>(
          probe.$3,
          options: Options(
            responseType: ResponseType.plain,
            receiveTimeout: const Duration(seconds: 8),
            sendTimeout: const Duration(seconds: 8),
            validateStatus: (_) => true,
            headers: const <String, String>{'Range': 'bytes=0-512'},
          ),
        );
        httpStatus = response.statusCode ?? 0;
        ok = httpStatus >= 200 && httpStatus < 400;
        if (!ok) error = 'HTTP $httpStatus';
      } on Object catch (failure) {
        error = failure.toString().split('\n').first;
      }
      final latency = DateTime.now().difference(started).inMilliseconds;
      final health = SourceHealth(
        id: probe.$1,
        label: probe.$2,
        url: probe.$3,
        ok: ok,
        checkedAt: DateTime.now(),
        lastSuccessAt: ok ? DateTime.now() : null,
        lastFailureAt: ok ? null : DateTime.now(),
        httpStatus: httpStatus,
        latencyMs: latency,
        error: error,
      );
      results.add(health);
      try {
        await _db.collection(monitorCollection).doc(probe.$1).set(
          <String, dynamic>{
            'label': probe.$2,
            'url': probe.$3,
            'ok': ok,
            'checkedAt': FieldValue.serverTimestamp(),
            'httpStatus': httpStatus,
            'latencyMs': latency,
            'error': error,
            if (ok) 'lastSuccessAt': FieldValue.serverTimestamp(),
            if (!ok) 'lastFailureAt': FieldValue.serverTimestamp(),
          },
          SetOptions(merge: true),
        );
      } on Object {
        // A refused write is reported by the UI as "not stored"; the live result
        // is still shown.
      }
    }
    try {
      await _db.collection(logCollection).add(<String, dynamic>{
        'action': AdminAction.monitorCheck.id,
        'actorUid': actorUid,
        'actorName': actorName,
        'targetUid': '',
        'targetLabel': '',
        'reason': '',
        'details': results.map((item) => '${item.id}:${item.ok}').join(','),
        'previousState': '',
        'nextState': '',
        'createdAt': FieldValue.serverTimestamp(),
      });
    } on Object {
      // Logging is best effort here; the monitor result is what matters.
    }
    return results;
  }
}

/// Convenience for building a status record from a UI decision.
AccountStatusRecord buildStatusRecord({
  required AccountState state,
  required String reason,
  required String actorUid,
  required AccountState previousState,
  DateTime? expiresAt,
  bool permanent = false,
  Set<RestrictionFeature> restrictions = const <RestrictionFeature>{},
  bool restrictionsPermanent = false,
  DateTime? restrictionsExpireAt,
}) => AccountStatusRecord(
  state: state,
  reason: reason,
  startedAt: DateTime.now(),
  expiresAt: expiresAt,
  permanent: permanent,
  actorUid: actorUid,
  previousState: previousState,
  restrictions: restrictions,
  restrictionsPermanent: restrictionsPermanent,
  restrictionsExpireAt: restrictionsExpireAt,
);

/// The signed-in Owner's own signature, used on Owner messages.
ProfileBadges ownerBadges(bool verified) =>
    ProfileBadges(verified: verified, developer: true);
