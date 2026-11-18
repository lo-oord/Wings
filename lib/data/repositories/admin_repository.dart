import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../../core/utils/email_hash.dart';
import '../models/account_status.dart';
import 'email_block_guard.dart';
import '../models/admin_models.dart';
import '../username/username_rules.dart';

/// The account performing an administrative action.
class AdminActor {
  const AdminActor({
    required this.uid,
    required this.name,
    required this.username,
    this.role = StaffRole.owner,
  });

  final String uid;
  final String name;
  final String username;
  final StaffRole role;
}

/// Everything the administrative profile page shows about one account.
class AdminUserDetails {
  const AdminUserDetails({
    required this.user,
    required this.warnings,
    required this.actions,
    required this.reports,
  });

  final AdminUser user;
  final List<AdminWarning> warnings;
  final List<AdminActionRecord> actions;
  final List<AdminReport> reports;
}

/// Owner administration, backed by Firestore.
///
/// Authorization is enforced twice: the application only calls these methods
/// for a verified owner, and `firestore.rules` independently rejects every
/// write from an account that is not listed in `config/admins`. No privileged
/// secret is stored in the app, so a tampered client gains nothing.
class AdminRepository {
  AdminRepository(this._db);

  final FirebaseFirestore _db;

  static const String usersCollection = 'users';
  static const String actionsCollection = 'adminActions';
  static const String reportsCollection = 'reports';
  static const String emailsCollection = 'emailBlocks';
  static const String usernamesBlockCollection = 'usernameBlocks';
  static const String ownerMessagesCollection = 'ownerMessages';
  static const String configCollection = 'config';
  static const String adminsDoc = 'admins';

  CollectionReference<Map<String, dynamic>> get _users =>
      _db.collection(usersCollection);

  DocumentReference<Map<String, dynamic>> _user(String uid) =>
      _users.doc(uid);

  // ------------------------------------------------------------------- role

  /// Reads the trusted staff document. A non-staff account is refused by the
  /// rules, which is exactly what [StaffRole.user] means here.
  Future<StaffRole> fetchRole(String uid) async {
    if (uid.isEmpty) return StaffRole.user;
    try {
      final snapshot = await _db
          .collection(configCollection)
          .doc(adminsDoc)
          .get(const GetOptions(source: Source.server));
      final data = snapshot.data();
      if (!snapshot.exists || data == null) return StaffRole.user;
      final roles = data['roles'];
      if (roles is Map && roles[uid] is String) {
        return StaffRole.fromStorage(roles[uid]);
      }
      final owners = data['owners'];
      if (owners is List && owners.contains(uid)) return StaffRole.owner;
      final uids = data['uids'];
      // A project initialised before `owners` existed treats its admins as
      // owners, so the bootstrap never locks the real owner out.
      if (uids is List && uids.contains(uid)) {
        return owners is List ? StaffRole.admin : StaffRole.owner;
      }
      return StaffRole.user;
    } on FirebaseException {
      // Permission denied = not staff. Offline keeps the visible role at user
      // rather than trusting a cached flag.
      return StaffRole.user;
    } on Object {
      return StaffRole.user;
    }
  }

  // -------------------------------------------------------------- dashboard

  Future<int> _count(Query<Map<String, dynamic>> query) async {
    final snapshot = await query.count().get();
    return snapshot.count ?? 0;
  }

  Query<Map<String, dynamic>> _byStatus(AccountState state) =>
      _users.where('accountStatus', isEqualTo: state.storage);

  /// Builds every dashboard number from aggregation queries: one document read
  /// per 1000 matches instead of downloading the whole collection. `active` is
  /// derived by subtraction so accounts created before the status field existed
  /// are not silently lost.
  Future<AdminDashboardStats> dashboard() async {
    final now = DateTime.now();
    final startOfDay = DateTime(now.year, now.month, now.day);
    final weekAgo = now.subtract(const Duration(days: 7));

    final results = await Future.wait<int>(<Future<int>>[
      _count(_users),
      _count(
        _users.where(
          'createdAt',
          isGreaterThanOrEqualTo: Timestamp.fromDate(startOfDay),
        ),
      ),
      _count(
        _users.where(
          'createdAt',
          isGreaterThanOrEqualTo: Timestamp.fromDate(weekAgo),
        ),
      ),
      _count(_byStatus(AccountState.suspended)),
      _count(_byStatus(AccountState.banned)),
      _count(_byStatus(AccountState.restricted)),
      _count(_byStatus(AccountState.underReview)),
      _count(_byStatus(AccountState.deleted)),
      _count(
        _db
            .collection(reportsCollection)
            .where('status', isEqualTo: 'open'),
      ),
      _count(
        _db
            .collection(reportsCollection)
            .where('status', isEqualTo: 'reviewed'),
      ),
      _count(
        _db
            .collection(reportsCollection)
            .where('status', isEqualTo: 'resolved'),
      ),
    ]);

    final recentUsers = await _users
        .orderBy('createdAt', descending: true)
        .limit(6)
        .get();
    final recentActions = await _db
        .collection(actionsCollection)
        .orderBy('createdAt', descending: true)
        .limit(8)
        .get();

    final inactive =
        results[3] + results[4] + results[5] + results[6] + results[7];
    return AdminDashboardStats(
      totalUsers: results[0],
      registeredToday: results[1],
      registeredThisWeek: results[2],
      activeAccounts: (results[0] - inactive).clamp(0, results[0]),
      suspendedAccounts: results[3],
      bannedAccounts: results[4],
      restrictedAccounts: results[5],
      underReviewAccounts: results[6],
      deletedAccounts: results[7],
      pendingReports: results[8],
      reviewedReports: results[9],
      resolvedReports: results[10],
      recentUsers: recentUsers.docs
          .map((doc) => AdminUser.fromDoc(doc.id, doc.data()))
          .toList(growable: false),
      recentActions: recentActions.docs
          .map((doc) => AdminActionRecord.fromDoc(doc.id, doc.data()))
          .toList(growable: false),
      loadedAt: now,
    );
  }

  // ------------------------------------------------------------------ users

  /// One page of accounts, newest (or oldest) first.
  ///
  /// Filtering by status needs the composite index declared in
  /// `firestore.indexes.json`; without a filter only the automatic single-field
  /// index on `createdAt` is used.
  Future<AdminUserPage> usersPage({
    AccountState? status,
    bool newestFirst = true,
    DocumentSnapshot<Map<String, dynamic>>? cursor,
    int limit = 20,
  }) async {
    Query<Map<String, dynamic>> query = _users;
    if (status != null) {
      query = query.where('accountStatus', isEqualTo: status.storage);
    }
    query = query.orderBy('createdAt', descending: newestFirst);
    if (cursor != null) query = query.startAfterDocument(cursor);
    query = query.limit(limit);
    final snapshot = await query.get();
    return AdminUserPage(
      items: snapshot.docs
          .map((doc) => AdminUser.fromDoc(doc.id, doc.data()))
          .toList(growable: false),
      cursor: snapshot.docs.isEmpty ? null : snapshot.docs.last,
      hasMore: snapshot.docs.length == limit,
    );
  }

  /// Prefix search over the normalized username. The range query uses the
  /// automatic index on `normalizedUsername` and never scans the collection.
  Future<List<AdminUser>> searchUsers(String raw, {int limit = 12}) async {
    final normalized = UsernameRules.normalize(raw);
    if (normalized.isEmpty) return const <AdminUser>[];
    final snapshot = await _users
        .where('normalizedUsername', isGreaterThanOrEqualTo: normalized)
        .where('normalizedUsername', isLessThan: '$normalized\uf8ff')
        .orderBy('normalizedUsername')
        .limit(limit)
        .get();
    return snapshot.docs
        .map((doc) => AdminUser.fromDoc(doc.id, doc.data()))
        .toList(growable: false);
  }

  Stream<AdminUser?> watchUser(String uid) => _user(uid).snapshots().map((doc) {
    final data = doc.data();
    if (!doc.exists || data == null) return null;
    return AdminUser.fromDoc(uid, data);
  });

  Future<AdminUser?> fetchUser(String uid) async {
    final doc = await _user(uid).get();
    final data = doc.data();
    if (!doc.exists || data == null) return null;
    return AdminUser.fromDoc(uid, data);
  }

  /// Reads everything the administrative profile page needs. The owner
  /// document is readable by staff, including for a private profile.
  Future<AdminUserDetails?> userDetails(String uid) async {
    final user = await fetchUser(uid);
    if (user == null) return null;
    final warnings = await _user(uid)
        .collection('warnings')
        .orderBy('createdAt', descending: true)
        .limit(40)
        .get();
    final actions = await _db
        .collection(actionsCollection)
        .where('targetUid', isEqualTo: uid)
        .limit(40)
        .get();
    final reports = await _db
        .collection(reportsCollection)
        .where('targetUid', isEqualTo: uid)
        .limit(40)
        .get();
    final actionItems = actions.docs
        .map((doc) => AdminActionRecord.fromDoc(doc.id, doc.data()))
        .toList();
    actionItems.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    final reportItems = reports.docs
        .map((doc) => AdminReport.fromDoc(doc.id, doc.data()))
        .toList();
    reportItems.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return AdminUserDetails(
      user: user,
      warnings: warnings.docs
          .map((doc) => AdminWarning.fromDoc(doc.id, doc.data()))
          .toList(growable: false),
      actions: actionItems,
      reports: reportItems,
    );
  }

  Future<AdminUser?> staffByUsername(String raw) async {
    final normalized = UsernameRules.normalize(raw);
    if (normalized.isEmpty) return null;
    final snapshot = await _users
        .where('normalizedUsername', isEqualTo: normalized)
        .limit(1)
        .get();
    if (snapshot.docs.isEmpty) return null;
    final doc = snapshot.docs.first;
    return AdminUser.fromDoc(doc.id, doc.data());
  }

  // --------------------------------------------------------------- actions

  /// Applies a validated account state and records the audit entry, the
  /// user-facing notification and the owner message in one batch.
  ///
  /// Every write is authorized by rules that only accept the owner of the
  /// trusted staff document, so a client cannot reach this state by itself.
  Future<void> applyState({
    required AdminActor actor,
    required AdminUser target,
    required AccountState state,
    required String reason,
    required String action,
    AccountRestrictions? restrictions,
    DateTime? expiresAt,
    DateTime? restrictionsExpireAt,
    String title = '',
    String body = '',
    String category = 'account-status',
    String severity = 'warning',
    List<String> restrictionLabels = const <String>[],
    Map<String, dynamic> details = const <String, dynamic>{},
    int warningsDelta = 0,
  }) async {
    final batch = _db.batch();
    final nextRestrictions =
        restrictions ?? target.standing.restrictions;
    final warnings =
        (target.standing.warningsCount + warningsDelta).clamp(0, 1 << 20);
    batch.update(_user(target.uid), <String, dynamic>{
      'accountStatus': state.storage,
      'statusReason': reason,
      'statusUpdatedAt': FieldValue.serverTimestamp(),
      'statusExpiresAt': expiresAt == null
          ? null
          : Timestamp.fromDate(expiresAt),
      'statusActorUid': actor.uid,
      'restrictions': nextRestrictions.toMap(),
      'restrictionsExpireAt': restrictionsExpireAt == null
          ? null
          : Timestamp.fromDate(restrictionsExpireAt),
      'warningsCount': warnings,
    });
    _addAction(
      batch,
      actor: actor,
      targetUid: target.uid,
      targetUsername: target.username,
      action: action,
      reason: reason,
      details: <String, dynamic>{
        ...details,
        'state': state.storage,
        'restrictions': nextRestrictions.enabledKeys,
        if (expiresAt != null) 'expiresAt': Timestamp.fromDate(expiresAt),
      },
    );
    if (title.isNotEmpty || body.isNotEmpty) {
      _addNotice(
        batch,
        uid: target.uid,
        actor: actor,
        title: title,
        body: body,
        category: category,
        severity: severity,
        reason: reason,
        restrictions: restrictionLabels,
        expiresAt: expiresAt,
      );
    }
    await batch.commit();
  }

  /// Issues one formal warning. A warning never disables a feature by itself:
  /// the account becomes `warned` and keeps every ability.
  Future<void> warn({
    required AdminActor actor,
    required AdminUser target,
    required String category,
    required String reason,
  }) async {
    final warningRef = _user(target.uid).collection('warnings').doc();
    final batch = _db.batch();
    batch.set(warningRef, <String, dynamic>{
      'category': category,
      'reason': reason,
      'actorUid': actor.uid,
      'actorName': actor.name,
      'active': true,
      'createdAt': FieldValue.serverTimestamp(),
    });
    final nextState = target.standing.effectiveState == AccountState.active
        ? AccountState.warned
        : target.standing.state;
    batch.update(_user(target.uid), <String, dynamic>{
      'accountStatus': nextState.storage,
      'statusReason': reason,
      'statusUpdatedAt': FieldValue.serverTimestamp(),
      'statusExpiresAt': target.standing.expiresAt == null
          ? null
          : Timestamp.fromDate(target.standing.expiresAt!),
      'statusActorUid': actor.uid,
      'restrictions': target.standing.restrictions.toMap(),
      'restrictionsExpireAt': target.standing.restrictionsExpireAt == null
          ? null
          : Timestamp.fromDate(target.standing.restrictionsExpireAt!),
      'warningsCount': target.standing.warningsCount + 1,
    });
    _addAction(
      batch,
      actor: actor,
      targetUid: target.uid,
      targetUsername: target.username,
      action: 'warning',
      reason: reason,
      details: <String, dynamic>{
        'category': category,
        'warningId': warningRef.id,
      },
    );
    _addNotice(
      batch,
      uid: target.uid,
      actor: actor,
      title: 'إنذار رسمي من إدارة Wings',
      body:
          'تلقّيت إنذارًا رسميًا من مالك Wings.\n\n'
          'التصنيف: ${_warningCategoryLabel(category)}\n'
          'السبب: $reason\n\n'
          'الإنذار وحده لا يوقف أي ميزة في حسابك، لكن تكرار المخالفات قد '
          'يؤدي إلى إجراءات إضافية.',
      category: 'warning',
      severity: 'warning',
      reason: reason,
    );
    await batch.commit();
  }

  /// Marks a warning invalid while keeping the audit record intact.
  Future<void> revokeWarning({
    required AdminActor actor,
    required AdminUser target,
    required AdminWarning warning,
    required String reason,
  }) async {
    final batch = _db.batch();
    batch.update(_user(target.uid).collection('warnings').doc(warning.id), {
      'active': false,
      'revokedAt': FieldValue.serverTimestamp(),
      'revokedBy': actor.uid,
    });
    batch.update(_user(target.uid), <String, dynamic>{
      'warningsCount': (target.standing.warningsCount - 1).clamp(0, 1 << 20),
    });
    _addAction(
      batch,
      actor: actor,
      targetUid: target.uid,
      targetUsername: target.username,
      action: 'warning-revoked',
      reason: reason,
      details: <String, dynamic>{'warningId': warning.id},
    );
    _addNotice(
      batch,
      uid: target.uid,
      actor: actor,
      title: 'تم إلغاء إنذار سابق',
      body:
          'ألغت إدارة Wings إنذارًا سابقًا على حسابك.\n\n'
          'السبب: $reason',
      category: 'warning',
      severity: 'info',
      reason: reason,
    );
    await batch.commit();
  }

  /// Lifts a ban/suspension and returns the account to the highest state that
  /// still applies: a live restriction makes it `restricted`, otherwise it goes
  /// back to `active` (keeping the warning history).
  Future<void> restore({
    required AdminActor actor,
    required AdminUser target,
    required String reason,
  }) async {
    final warnings = target.standing.warningsCount;
    final restrictions = target.standing.restrictions;
    final state = restrictions.any
        ? AccountState.restricted
        : (warnings > 0 ? AccountState.warned : AccountState.active);
    await applyState(
      actor: actor,
      target: target,
      state: state,
      reason: reason,
      action: 'restore',
      restrictions: restrictions,
      restrictionsExpireAt:
          restrictions.any ? target.standing.restrictionsExpireAt : null,
      title: 'تمت استعادة حسابك في Wings',
      body:
          'استعادت إدارة Wings حسابك.\n\n'
          'السبب: $reason\n'
          'حالة الحساب الآن: ${state.arabic}',
      category: 'account-status',
      severity: 'info',
    );
  }

  /// Reports review.
  Future<List<AdminReport>> reports({String? status, int limit = 60}) async {
    Query<Map<String, dynamic>> query =
        _db.collection(reportsCollection);
    if (status != null) {
      query = query.where('status', isEqualTo: status);
    }
    final snapshot = await query.limit(limit).get();
    final items = snapshot.docs
        .map((doc) => AdminReport.fromDoc(doc.id, doc.data()))
        .toList();
    items.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return items;
  }

  Future<void> reviewReport({
    required AdminActor actor,
    required AdminReport report,
    required String status,
    required String note,
  }) async {
    await _db.collection(reportsCollection).doc(report.id).update(
      <String, dynamic>{
        'status': status,
        'reviewNote': note,
        'reviewedBy': actor.uid,
        'updatedAt': FieldValue.serverTimestamp(),
      },
    );
  }

  Future<List<AdminActionRecord>> recentActions({int limit = 60}) async {
    final snapshot = await _db
        .collection(actionsCollection)
        .orderBy('createdAt', descending: true)
        .limit(limit)
        .get();
    return snapshot.docs
        .map((doc) => AdminActionRecord.fromDoc(doc.id, doc.data()))
        .toList(growable: false);
  }

  // -------------------------------------------------------- email denylist

  /// Normalized SHA-256 of an address. The constant is part of the security
  /// contract: `emailBlocks/{hash}` and the registration rule use the same
  /// value, so the denylist never stores a raw address.
  static String emailHash(String email) => hashEmail(email);

  /// Registration probe. The client never reads the denylist; it asks the rules
  /// to create a throw-away marker, which is only allowed while the address is
  /// **not** blocked.
  Future<bool> isEmailBlocked(String email) =>
      EmailBlockGuard.isBlocked(_db, email);

  Future<void> blockEmail({
    required AdminActor actor,
    required String email,
    required String reason,
  }) async {
    final hash = emailHash(email);
    final address = email.trim().toLowerCase();
    final domain = address.contains('@') ? address.split('@').last : '';
    await _db.collection(emailsCollection).doc(hash).set(<String, dynamic>{
      'hash': hash,
      'reason': reason,
      'domain': domain,
      'createdBy': actor.uid,
      'createdAt': FieldValue.serverTimestamp(),
    });
    await _logOnly(
      actor: actor,
      action: 'email-block',
      targetUid: hash,
      targetUsername: domain,
      reason: reason,
    );
  }

  Future<void> blockEmailHash({
    required AdminActor actor,
    required String hash,
    required String reason,
  }) async {
    if (hash.isEmpty) return;
    await _db.collection(emailsCollection).doc(hash).set(<String, dynamic>{
      'hash': hash,
      'reason': reason,
      'createdBy': actor.uid,
      'createdAt': FieldValue.serverTimestamp(),
    });
    await _logOnly(
      actor: actor,
      action: 'email-block',
      targetUid: hash,
      targetUsername: '',
      reason: reason,
    );
  }

  Future<void> unblockEmail({
    required AdminActor actor,
    required String hash,
    required String reason,
  }) async {
    await _db.collection(emailsCollection).doc(hash).delete();
    await _logOnly(
      actor: actor,
      action: 'email-unblock',
      targetUid: hash,
      targetUsername: '',
      reason: reason,
    );
  }

  Future<List<BlockedEmail>> blockedEmails({int limit = 60}) async {
    final snapshot = await _db
        .collection(emailsCollection)
        .orderBy('createdAt', descending: true)
        .limit(limit)
        .get();
    return snapshot.docs
        .map((doc) => BlockedEmail.fromDoc(doc.id, doc.data()))
        .toList(growable: false);
  }

  // ----------------------------------------------------- username denylist

  Future<void> blockUsername({
    required AdminActor actor,
    required String username,
    required String reason,
  }) async {
    final normalized = UsernameRules.normalize(username);
    if (normalized.isEmpty) return;
    await _db
        .collection(usernamesBlockCollection)
        .doc(normalized)
        .set(<String, dynamic>{
          'username': normalized,
          'reason': reason,
          'createdBy': actor.uid,
          'createdAt': FieldValue.serverTimestamp(),
        });
    await _logOnly(
      actor: actor,
      action: 'username-block',
      targetUid: normalized,
      targetUsername: normalized,
      reason: reason,
    );
  }

  Future<void> unblockUsername({
    required AdminActor actor,
    required String normalized,
    required String reason,
  }) async {
    await _db.collection(usernamesBlockCollection).doc(normalized).delete();
    await _logOnly(
      actor: actor,
      action: 'username-unblock',
      targetUid: normalized,
      targetUsername: normalized,
      reason: reason,
    );
  }

  Future<List<BlockedUsername>> blockedUsernames({int limit = 60}) async {
    final snapshot = await _db
        .collection(usernamesBlockCollection)
        .orderBy('createdAt', descending: true)
        .limit(limit)
        .get();
    return snapshot.docs
        .map((doc) => BlockedUsername.fromDoc(doc.id, doc.data()))
        .toList(growable: false);
  }

  Future<BlockedUsername?> findBlockedUsername(String raw) async {
    final normalized = UsernameRules.normalize(raw);
    if (normalized.isEmpty) return null;
    final doc = await _db
        .collection(usernamesBlockCollection)
        .doc(normalized)
        .get();
    final data = doc.data();
    if (!doc.exists || data == null) return null;
    return BlockedUsername.fromDoc(doc.id, data);
  }

  // --------------------------------------------------------- owner messages

  Future<void> sendOwnerMessage({
    required AdminActor actor,
    required AdminUser target,
    required String title,
    required String body,
  }) async {
    final ref = _db
        .collection(ownerMessagesCollection)
        .doc(target.uid)
        .collection('items')
        .doc();
    final batch = _db.batch();
    batch.set(ref, <String, dynamic>{
      'title': title,
      'body': body,
      'senderUid': actor.uid,
      'senderName': actor.name,
      'senderUsername': actor.username,
      'read': false,
      'createdAt': FieldValue.serverTimestamp(),
    });
    _addNotice(
      batch,
      uid: target.uid,
      actor: actor,
      title: 'رسالة جديدة من مالك Wings',
      body: title.isEmpty ? body : '$title\n\n$body',
      category: 'message',
      severity: 'info',
      reason: '',
    );
    _addAction(
      batch,
      actor: actor,
      targetUid: target.uid,
      targetUsername: target.username,
      action: 'owner-message',
      reason: title.isEmpty ? body : title,
      details: <String, dynamic>{'messageId': ref.id},
    );
    await batch.commit();
  }

  Stream<List<OwnerMessage>> watchOwnerMessages(String uid) => _db
      .collection(ownerMessagesCollection)
      .doc(uid)
      .collection('items')
      .orderBy('createdAt', descending: true)
      .limit(50)
      .snapshots()
      .map(
        (snapshot) => snapshot.docs
            .map((doc) => OwnerMessage.fromDoc(doc.id, doc.data()))
            .toList(growable: false),
      );

  Future<List<OwnerMessage>> ownerMessages(String uid) async {
    final snapshot = await _db
        .collection(ownerMessagesCollection)
        .doc(uid)
        .collection('items')
        .orderBy('createdAt', descending: true)
        .limit(60)
        .get();
    return snapshot.docs
        .map((doc) => OwnerMessage.fromDoc(doc.id, doc.data()))
        .toList(growable: false);
  }

  Future<void> markOwnerMessageRead(String uid, String id) async {
    await _db
        .collection(ownerMessagesCollection)
        .doc(uid)
        .collection('items')
        .doc(id)
        .update(<String, dynamic>{'read': true});
  }

  // ------------------------------------------------------- admin notices

  Stream<List<AdminNotice>> watchAdminNotices(String uid) => _user(uid)
      .collection('adminNotices')
      .orderBy('createdAt', descending: true)
      .limit(50)
      .snapshots()
      .map(
        (snapshot) => snapshot.docs
            .map((doc) => AdminNotice.fromDoc(doc.id, doc.data()))
            .toList(growable: false),
      );

  Future<void> markAdminNoticeRead(String uid, String id) async {
    await _user(uid)
        .collection('adminNotices')
        .doc(id)
        .update(<String, dynamic>{'read': true});
  }

  Future<int> unreadAdminNoticeCount(String uid) async {
    final snapshot = await _user(uid)
        .collection('adminNotices')
        .where('read', isEqualTo: false)
        .count()
        .get();
    return snapshot.count ?? 0;
  }

  // ---------------------------------------------------------------- deletion

  /// Owner-controlled deletion.
  ///
  /// The account is marked `deleted` first (which the rules immediately treat
  /// as unusable), then every account-owned document is swept, the username is
  /// released and the email is added to the denylist so the account cannot be
  /// recreated. The Firebase Authentication record itself can only be removed
  /// with the Admin SDK or the console, because Cloud Functions require a paid
  /// plan; the exact console step is documented in `docs/FIREBASE_SETUP.md`.
  Future<AdminDeletionReport> deleteUser({
    required AdminActor actor,
    required AdminUser target,
    required String reason,
    bool blockEmailAfter = true,
    bool blockUsernameAfter = true,
  }) async {
    final kept = <String>[];
    final doc = await _user(target.uid).get();
    final data = doc.data() ?? const <String, dynamic>{};
    final emailHash = data['emailHash'] as String? ?? '';
    final normalized = target.username.trim().toLowerCase();

    // 1. Close the account before touching anything else.
    await applyState(
      actor: actor,
      target: target,
      state: AccountState.deleted,
      reason: reason,
      action: 'account-deleted',
      restrictions: const AccountRestrictions(
        comment: true,
        post: true,
        interact: true,
        community: true,
        report: true,
      ),
      title: 'تم حذف حسابك في Wings',
      body:
          'حُذف حسابك في Wings بقرار من مالك التطبيق.\n\n'
          'السبب: $reason\n'
          'تاريخ الحذف: ${DateTime.now().toIso8601String().split('T').first}\n\n'
          'لم يعد الحساب قادرًا على استخدام التطبيق، وتمت إزالة محتواه.',
      category: 'deletion',
      severity: 'critical',
    );

    // 2. Comments and replies written by the account, in the replies-last
    //    order that keeps the thread rules happy.
    try {
      final comments = await _db
          .collectionGroup('comments')
          .where('authorUid', isEqualTo: target.uid)
          .limit(2000)
          .get();
      final replies = comments.docs
          .where((doc) => doc.reference.path.contains('/replies/'))
          .toList();
      final parents =
          comments.docs.where((doc) => !replies.contains(doc)).toList();
      await _deleteRefs(<DocumentReference<Map<String, dynamic>>>[
        ...replies.map((doc) => doc.reference),
        ...parents.map((doc) => doc.reference),
      ], kept, 'comments');
    } on FirebaseException catch (error) {
      kept.add('comments:${error.code}');
    }

    // 3. Account-owned subcollections. Firestore never deletes them with the
    //    parent document.
    for (final name in const <String>[
      'library',
      'history',
      'settings',
      'meta',
      'activity',
      'notifications',
      'adminNotices',
      'warnings',
      'episodes',
      'search',
      'private',
    ]) {
      await _deleteCollection(target.uid, name, kept);
    }
    await _deleteSubcollection(
      _db
          .collection(ownerMessagesCollection)
          .doc(target.uid)
          .collection('items'),
      kept,
      'ownerMessages',
    );

    // 4. Public surfaces and reservations.
    await _guardDelete(
      _db.collection('profiles').doc(target.uid),
      kept,
      'profile',
    );
    await _guardDelete(
      _db.collection('badges').doc(target.uid),
      kept,
      'badges',
    );
    if (normalized.isNotEmpty) {
      await _guardDelete(
        _db.collection('usernames').doc(normalized),
        kept,
        'username',
      );
    }

    // 5. Keep a tombstone so the uid can never resolve to an active account
    //    and the Auth session that still exists is refused by the rules.
    try {
      await _user(target.uid).set(<String, dynamic>{
        'username': target.username,
        'normalizedUsername': normalized,
        'displayName': 'حساب محذوف',
        'bio': '',
        'country': '',
        'ageGroup': '',
        'privacy': const <String, dynamic>{
          'showProfile': false,
          'bio': false,
          'country': false,
          'age': false,
          'favorites': false,
          'stats': false,
        },
        'stats': const <String, dynamic>{
          'animeWatched': 0,
          'episodesWatched': 0,
          'favorites': 0,
          'completed': 0,
        },
        'badges': const <String, dynamic>{
          'verified': false,
          'developer': false,
        },
        'pendingDeletion': false,
        'accountStatus': AccountState.deleted.storage,
        'statusReason': reason,
        'statusUpdatedAt': FieldValue.serverTimestamp(),
        'statusExpiresAt': null,
        'statusActorUid': actor.uid,
        'restrictions': const AccountRestrictions(
          comment: true,
          post: true,
          interact: true,
          community: true,
          report: true,
        ).toMap(),
        'restrictionsExpireAt': null,
        'warningsCount': target.standing.warningsCount,
        if (emailHash.isNotEmpty) 'emailHash': emailHash,
        'createdAt': Timestamp.fromDate(target.createdAt),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    } on FirebaseException catch (error) {
      kept.add('tombstone:${error.code}');
    }

    if (blockEmailAfter && emailHash.isNotEmpty) {
      await _guard(
        () => blockEmailHash(actor: actor, hash: emailHash, reason: reason),
        kept,
        'email-block',
      );
    }
    if (blockUsernameAfter && normalized.isNotEmpty) {
      await _guard(
        () => blockUsername(
          actor: actor,
          username: normalized,
          reason: reason,
        ),
        kept,
        'username-block',
      );
    }

    await _logOnly(
      actor: actor,
      action: 'account-deleted',
      targetUid: target.uid,
      targetUsername: target.username,
      reason: reason,
      details: <String, dynamic>{'kept': kept},
    );
    return AdminDeletionReport(
      uid: target.uid,
      authRecordPending: true,
      kept: kept,
    );
  }

  Future<AdminDeletionReport> deleteUserDataOnly({
    required AdminActor actor,
    required AdminUser target,
    required String reason,
  }) => deleteUser(
    actor: actor,
    target: target,
    reason: reason,
    blockEmailAfter: false,
    blockUsernameAfter: false,
  );

  // -------------------------------------------------------------- internals

  void _addAction(
    WriteBatch batch, {
    required AdminActor actor,
    required String action,
    required String targetUid,
    required String targetUsername,
    required String reason,
    Map<String, dynamic> details = const <String, dynamic>{},
  }) {
    batch.set(_db.collection(actionsCollection).doc(), <String, dynamic>{
      'action': action,
      'targetUid': targetUid,
      'targetUsername': targetUsername,
      'actorUid': actor.uid,
      'actorName': actor.name,
      'actorRole': actor.role.name,
      'reason': reason,
      'details': details,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  void _addNotice(
    WriteBatch batch, {
    required String uid,
    required AdminActor actor,
    required String title,
    required String body,
    required String category,
    required String severity,
    required String reason,
    List<String> restrictions = const <String>[],
    DateTime? expiresAt,
  }) {
    batch.set(
      _user(uid).collection('adminNotices').doc(),
      <String, dynamic>{
        'title': title,
        'body': body,
        'category': category,
        'severity': severity,
        'reason': reason,
        'restrictions': restrictions,
        'read': false,
        'actorUid': actor.uid,
        if (expiresAt != null) 'expiresAt': Timestamp.fromDate(expiresAt),
        'createdAt': FieldValue.serverTimestamp(),
      },
    );
  }

  Future<void> _logOnly({
    required AdminActor actor,
    required String action,
    required String targetUid,
    required String targetUsername,
    required String reason,
    Map<String, dynamic> details = const <String, dynamic>{},
  }) async {
    await _db.collection(actionsCollection).add(<String, dynamic>{
      'action': action,
      'targetUid': targetUid,
      'targetUsername': targetUsername,
      'actorUid': actor.uid,
      'actorName': actor.name,
      'actorRole': actor.role.name,
      'reason': reason,
      'details': details,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> _guard(
    Future<void> Function() action,
    List<String> kept,
    String step,
  ) async {
    try {
      await action();
    } on FirebaseException catch (error) {
      kept.add('$step:${error.code}');
    } on Object {
      kept.add(step);
    }
  }

  Future<void> _guardDelete(
    DocumentReference<Map<String, dynamic>> ref,
    List<String> kept,
    String step,
  ) async {
    try {
      await ref.delete();
    } on FirebaseException catch (error) {
      // A missing document is already deleted.
      if (error.code != 'not-found') kept.add('$step:${error.code}');
    } on Object {
      kept.add(step);
    }
  }

  Future<void> _deleteRefs(
    List<DocumentReference<Map<String, dynamic>>> refs,
    List<String> kept,
    String step,
  ) async {
    for (var index = 0; index < refs.length; index += 400) {
      final batch = _db.batch();
      for (final ref in refs.skip(index).take(400)) {
        batch.delete(ref);
      }
      try {
        await batch.commit();
      } on FirebaseException catch (error) {
        kept.add('$step:${error.code}');
        return;
      }
    }
  }

  Future<void> _deleteCollection(
    String uid,
    String name,
    List<String> kept,
  ) =>
      _deleteSubcollection(_user(uid).collection(name), kept, name);

  Future<void> _deleteSubcollection(
    CollectionReference<Map<String, dynamic>> collection,
    List<String> kept,
    String step,
  ) async {
    for (var pass = 0; pass < 50; pass++) {
      QuerySnapshot<Map<String, dynamic>> snapshot;
      try {
        snapshot = await collection.limit(100).get();
      } on FirebaseException catch (error) {
        kept.add('$step:${error.code}');
        return;
      }
      if (snapshot.docs.isEmpty) return;
      final batch = _db.batch();
      for (final doc in snapshot.docs) {
        batch.delete(doc.reference);
      }
      try {
        await batch.commit();
      } on FirebaseException catch (error) {
        kept.add('$step:${error.code}');
        return;
      }
      if (snapshot.docs.length < 100) return;
    }
    kept.add('$step:limit');
  }

  static String _warningCategoryLabel(String category) => switch (category) {
    'spam' => 'إزعاج أو رسائل مكررة',
    'abuse' => 'إساءة أو تحريض',
    'content' => 'محتوى غير لائق',
    'impersonation' => 'انتحال شخصية',
    'copyright' => 'حقوق نشر',
    'report-abuse' => 'إساءة استخدام البلاغات',
    _ => 'سياسة المنصة',
  };
}

/// Result of an owner deletion.
class AdminDeletionReport {
  const AdminDeletionReport({
    required this.uid,
    required this.authRecordPending,
    required this.kept,
  });

  final String uid;

  /// True because removing a Firebase Authentication record needs the Admin
  /// SDK (paid plan) or the console.
  final bool authRecordPending;
  final List<String> kept;
}
