import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

DateTime? _date(Object? raw) {
  if (raw is Timestamp) return raw.toDate();
  if (raw is DateTime) return raw;
  return null;
}

/// Trusted administrative role.
///
/// The role is **not** stored on the profile and never comes from a client
/// field: it lives in `staff/{uid}`, a document only the Firebase console (or an
/// Owner acting through the rules) can write, and every administrative write is
/// re-checked server-side against it.
enum StaffRole {
  user('', 0),
  moderator('moderator', 1),
  admin('admin', 2),
  owner('owner', 3);

  const StaffRole(this.id, this.rank);

  final String id;
  final int rank;

  static StaffRole fromId(Object? raw) {
    final value = raw is String ? raw.trim().toLowerCase() : '';
    for (final role in StaffRole.values) {
      if (role.id == value) return role;
    }
    return StaffRole.user;
  }

  bool get isStaff => rank >= StaffRole.moderator.rank;
  bool get isAdmin => rank >= StaffRole.admin.rank;
  bool get isOwner => this == StaffRole.owner;

  bool atLeast(StaffRole other) => rank >= other.rank;
}

/// Lifecycle state of an account, kept in one record instead of a set of
/// independent flags that could contradict each other.
enum AccountState {
  active('active'),
  warned('warned'),
  restricted('restricted'),
  suspended('suspended'),
  banned('banned'),
  underReview('underReview'),
  deleted('deleted');

  const AccountState(this.id);

  final String id;

  static AccountState fromId(Object? raw) {
    final value = raw is String ? raw.trim() : '';
    for (final state in AccountState.values) {
      if (state.id == value) return state;
    }
    return AccountState.active;
  }

  bool get isBlocking =>
      this == AccountState.banned ||
      this == AccountState.suspended ||
      this == AccountState.deleted;

  bool get isPunitive =>
      this == AccountState.banned ||
      this == AccountState.suspended ||
      this == AccountState.restricted;
}

/// A single feature that can be disabled without banning the account.
enum RestrictionFeature {
  comment('restrictComment'),
  post('restrictPost'),
  interact('restrictInteract'),
  community('restrictCommunity'),
  report('restrictReport');

  const RestrictionFeature(this.field);

  /// Flat boolean field on `users/{uid}/admin/status`, so the security rules can
  /// evaluate it with a single document read.
  final String field;

  static RestrictionFeature? fromField(String field) {
    for (final feature in RestrictionFeature.values) {
      if (feature.field == field) return feature;
    }
    return null;
  }
}

/// The authoritative administrative record of an account.
///
/// One document per account (`users/{uid}/admin/status`) keeps the state, the
/// active restrictions and their expiry together, so an expired suspension can
/// never leave a stale flag behind.
@immutable
class AccountStatusRecord {
  const AccountStatusRecord({
    this.state = AccountState.active,
    this.reason = '',
    this.startedAt,
    this.expiresAt,
    this.permanent = false,
    this.actorUid = '',
    this.actionId = '',
    this.previousState = AccountState.active,
    this.restrictions = const <RestrictionFeature>{},
    this.restrictionsPermanent = false,
    this.restrictionsExpireAt,
    this.updatedAt,
  });

  final AccountState state;
  final String reason;
  final DateTime? startedAt;
  final DateTime? expiresAt;

  /// An indefinite suspension or a permanent ban.
  final bool permanent;
  final String actorUid;
  final String actionId;
  final AccountState previousState;
  final Set<RestrictionFeature> restrictions;
  final bool restrictionsPermanent;
  final DateTime? restrictionsExpireAt;
  final DateTime? updatedAt;

  bool get isBanPermanent =>
      state == AccountState.banned ||
      (state == AccountState.suspended && permanent);

  /// The suspension still applies at [now]. A temporary suspension expires by
  /// itself: rules compare the stored timestamp with `request.time`, so no
  /// scheduled job has to run for the account to become usable again.
  bool isSuspensionActive(DateTime now) {
    if (state != AccountState.suspended) return false;
    if (permanent) return true;
    final expiry = expiresAt;
    return expiry != null && expiry.isAfter(now);
  }

  /// The account is fully locked (no reads that require an account, no writes).
  bool isLockedAt(DateTime now) {
    if (state == AccountState.banned || state == AccountState.deleted) {
      return true;
    }
    if (state == AccountState.suspended) return isSuspensionActive(now);
    return false;
  }

  /// The state that actually applies right now: an expired suspension reads as
  /// [AccountState.active] (or [AccountState.restricted] when restrictions are
  /// still in force) instead of claiming a suspension that ended.
  AccountState effectiveState(DateTime now) {
    if (state == AccountState.suspended && !isSuspensionActive(now)) {
      return activeRestrictions(now).isEmpty
          ? AccountState.active
          : AccountState.restricted;
    }
    return state;
  }

  Set<RestrictionFeature> activeRestrictions(DateTime now) {
    if (restrictions.isEmpty) return const <RestrictionFeature>{};
    if (restrictionsPermanent) return restrictions;
    final expiry = restrictionsExpireAt;
    if (expiry != null && expiry.isAfter(now)) return restrictions;
    return const <RestrictionFeature>{};
  }

  bool isRestricted(RestrictionFeature feature, DateTime now) =>
      activeRestrictions(now).contains(feature);

  factory AccountStatusRecord.fromMap(Map<String, dynamic> raw) {
    final features = <RestrictionFeature>{};
    for (final feature in RestrictionFeature.values) {
      if (raw[feature.field] == true) features.add(feature);
    }
    return AccountStatusRecord(
      state: AccountState.fromId(raw['state']),
      reason: raw['reason'] as String? ?? '',
      startedAt: _date(raw['startedAt']),
      expiresAt: _date(raw['expiresAt']),
      permanent: raw['permanent'] == true,
      actorUid: raw['actorUid'] as String? ?? '',
      actionId: raw['actionId'] as String? ?? '',
      previousState: AccountState.fromId(raw['previousState']),
      restrictions: features,
      restrictionsPermanent: raw['restrictionsPermanent'] == true,
      restrictionsExpireAt: _date(raw['restrictionsExpireAt']),
      updatedAt: _date(raw['updatedAt']),
    );
  }

  Map<String, dynamic> toMap() => <String, dynamic>{
    'state': state.id,
    'reason': reason,
    'startedAt': startedAt == null
        ? FieldValue.serverTimestamp()
        : Timestamp.fromDate(startedAt!),
    'expiresAt': expiresAt == null ? null : Timestamp.fromDate(expiresAt!),
    'permanent': permanent,
    'actorUid': actorUid,
    'actionId': actionId,
    'previousState': previousState.id,
    for (final feature in RestrictionFeature.values)
      feature.field: restrictions.contains(feature),
    'restrictionsPermanent': restrictionsPermanent,
    'restrictionsExpireAt': restrictionsExpireAt == null
        ? null
        : Timestamp.fromDate(restrictionsExpireAt!),
    'updatedAt': FieldValue.serverTimestamp(),
  };
}

/// Every administrative action type written to the immutable activity log.
enum AdminAction {
  warn('warn'),
  revokeWarning('revokeWarning'),
  restrict('restrict'),
  unrestrict('unrestrict'),
  suspend('suspend'),
  ban('ban'),
  restore('restore'),
  review('review'),
  deleteAccount('deleteAccount'),
  blockEmail('blockEmail'),
  unblockEmail('unblockEmail'),
  blockUsername('blockUsername'),
  unblockUsername('unblockUsername'),
  ownerMessage('ownerMessage'),
  reportReview('reportReview'),
  reportResolve('reportResolve'),
  appealDecide('appealDecide'),
  announcement('announcement'),
  announcementDelete('announcementDelete'),
  privateProfileAccess('privateProfileAccess'),
  deleteComment('deleteComment'),
  monitorCheck('monitorCheck'),
  roleChange('roleChange');

  const AdminAction(this.id);

  final String id;

  static AdminAction? fromId(Object? raw) {
    for (final action in AdminAction.values) {
      if (action.id == raw) return action;
    }
    return null;
  }
}

/// One immutable line of the administrative activity log.
@immutable
class AdminLogEntry {
  const AdminLogEntry({
    required this.id,
    required this.action,
    required this.actorUid,
    this.actorName = '',
    this.targetUid = '',
    this.targetLabel = '',
    this.reason = '',
    this.details = '',
    this.previousState = '',
    this.nextState = '',
    this.createdAt,
  });

  final String id;
  final AdminAction action;
  final String actorUid;
  final String actorName;
  final String targetUid;
  final String targetLabel;
  final String reason;
  final String details;
  final String previousState;
  final String nextState;
  final DateTime? createdAt;

  factory AdminLogEntry.fromDoc(String id, Map<String, dynamic> data) =>
      AdminLogEntry(
        id: id,
        action: AdminAction.fromId(data['action']) ?? AdminAction.review,
        actorUid: data['actorUid'] as String? ?? '',
        actorName: data['actorName'] as String? ?? '',
        targetUid: data['targetUid'] as String? ?? '',
        targetLabel: data['targetLabel'] as String? ?? '',
        reason: data['reason'] as String? ?? '',
        details: data['details'] as String? ?? '',
        previousState: data['previousState'] as String? ?? '',
        nextState: data['nextState'] as String? ?? '',
        createdAt: _date(data['createdAt']),
      );
}

/// A formal warning issued to an account. It is an audit record: revoking it
/// keeps the document and only marks it inactive.
@immutable
class AdminWarning {
  const AdminWarning({
    required this.id,
    this.category = 'general',
    this.reason = '',
    this.issuedAt,
    this.actorUid = '',
    this.actorName = '',
    this.active = true,
    this.revokedAt,
    this.revokedBy = '',
  });

  final String id;
  final String category;
  final String reason;
  final DateTime? issuedAt;
  final String actorUid;
  final String actorName;
  final bool active;
  final DateTime? revokedAt;
  final String revokedBy;

  factory AdminWarning.fromDoc(String id, Map<String, dynamic> data) =>
      AdminWarning(
        id: id,
        category: data['category'] as String? ?? 'general',
        reason: data['reason'] as String? ?? '',
        issuedAt: _date(data['issuedAt']),
        actorUid: data['actorUid'] as String? ?? '',
        actorName: data['actorName'] as String? ?? '',
        active: data['active'] != false,
        revokedAt: _date(data['revokedAt']),
        revokedBy: data['revokedBy'] as String? ?? '',
      );
}

/// A private personal message from the Wings Owner to one account.
@immutable
class OwnerMessage {
  const OwnerMessage({
    required this.id,
    required this.toUid,
    this.toUsername = '',
    this.fromUid = '',
    this.fromName = '',
    this.fromUsername = '',
    this.fromPhotoVersion = 0,
    this.title = '',
    this.body = '',
    this.createdAt,
    this.read = false,
  });

  final String id;
  final String toUid;
  final String toUsername;
  final String fromUid;
  final String fromName;
  final String fromUsername;
  final int fromPhotoVersion;
  final String title;
  final String body;
  final DateTime? createdAt;
  final bool read;

  factory OwnerMessage.fromDoc(String id, Map<String, dynamic> data) =>
      OwnerMessage(
        id: id,
        toUid: data['toUid'] as String? ?? '',
        toUsername: data['toUsername'] as String? ?? '',
        fromUid: data['fromUid'] as String? ?? '',
        fromName: data['fromName'] as String? ?? '',
        fromUsername: data['fromUsername'] as String? ?? '',
        fromPhotoVersion: (data['fromPhotoVersion'] as num?)?.toInt() ?? 0,
        title: data['title'] as String? ?? '',
        body: data['body'] as String? ?? '',
        createdAt: _date(data['createdAt']),
        read: data['read'] == true,
      );
}

/// A report from a member, handled in the Owner inbox.
@immutable
class AdminReport {
  const AdminReport({
    required this.id,
    this.reporterUid = '',
    this.reporterName = '',
    this.targetType = '',
    this.targetUid = '',
    this.targetLabel = '',
    this.category = '',
    this.details = '',
    this.status = 'pending',
    this.note = '',
    this.decision = '',
    this.createdAt,
    this.updatedAt,
  });

  final String id;
  final String reporterUid;
  final String reporterName;
  final String targetType;
  final String targetUid;
  final String targetLabel;
  final String category;
  final String details;

  /// `pending`, `review`, `resolved` or `rejected`.
  final String status;
  final String note;
  final String decision;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  factory AdminReport.fromDoc(String id, Map<String, dynamic> data) =>
      AdminReport(
        id: id,
        reporterUid: data['reporterUid'] as String? ?? '',
        reporterName: data['reporterName'] as String? ?? '',
        targetType: data['targetType'] as String? ?? '',
        targetUid: data['targetUid'] as String? ?? '',
        targetLabel: data['targetLabel'] as String? ?? '',
        category:
            data['category'] as String? ?? data['reason'] as String? ?? '',
        details: data['details'] as String? ?? data['reason'] as String? ?? '',
        status: _reportStatus(data['status']),
        note: data['note'] as String? ?? '',
        decision: data['decision'] as String? ?? '',
        createdAt: _date(data['createdAt']),
        updatedAt: _date(data['updatedAt']),
      );

  static String _reportStatus(Object? raw) {
    final value = raw is String ? raw : '';
    return switch (value) {
      'under_review' || 'review' => 'review',
      'resolved' => 'resolved',
      'rejected' => 'rejected',
      'dismissed' => 'rejected',
      _ => 'pending',
    };
  }
}

/// A review request an affected account submits against a moderation decision.
@immutable
class AdminAppeal {
  const AdminAppeal({
    required this.id,
    this.uid = '',
    this.username = '',
    this.message = '',
    this.decision = '',
    this.status = 'pending',
    this.createdAt,
    this.decidedAt,
    this.decidedBy = '',
  });

  final String id;
  final String uid;
  final String username;
  final String message;
  final String decision;
  final String status;
  final DateTime? createdAt;
  final DateTime? decidedAt;
  final String decidedBy;

  factory AdminAppeal.fromDoc(String id, Map<String, dynamic> data) =>
      AdminAppeal(
        id: id,
        uid: data['uid'] as String? ?? '',
        username: data['username'] as String? ?? '',
        message: data['message'] as String? ?? '',
        decision: data['decision'] as String? ?? '',
        status: (data['status'] as String?) ?? 'pending',
        createdAt: _date(data['createdAt']),
        decidedAt: _date(data['decidedAt']),
        decidedBy: data['decidedBy'] as String? ?? '',
      );
}

/// A blocked email address or username, independent of any account.
@immutable
class BlockedIdentity {
  const BlockedIdentity({
    required this.key,
    this.reason = '',
    this.actorUid = '',
    this.actorName = '',
    this.createdAt,
  });

  /// Normalized email (lower-case) or normalized username.
  final String key;
  final String reason;
  final String actorUid;
  final String actorName;
  final DateTime? createdAt;

  factory BlockedIdentity.fromDoc(String key, Map<String, dynamic> data) =>
      BlockedIdentity(
        key: key,
        reason: data['reason'] as String? ?? '',
        actorUid: data['actorUid'] as String? ?? '',
        actorName: data['actorName'] as String? ?? '',
        createdAt: _date(data['createdAt']),
      );
}

enum AnnouncementType {
  general('general'),
  important('important'),
  maintenance('maintenance'),
  update('update');

  const AnnouncementType(this.id);

  final String id;

  static AnnouncementType fromId(Object? raw) {
    for (final type in AnnouncementType.values) {
      if (type.id == raw) return type;
    }
    return AnnouncementType.general;
  }
}

@immutable
class Announcement {
  const Announcement({
    required this.id,
    this.title = '',
    this.body = '',
    this.type = AnnouncementType.general,
    this.publishedAt,
    this.expiresAt,
    this.actorUid = '',
  });

  final String id;
  final String title;
  final String body;
  final AnnouncementType type;
  final DateTime? publishedAt;
  final DateTime? expiresAt;
  final String actorUid;

  bool isLiveAt(DateTime now) {
    final expiry = expiresAt;
    return expiry == null || expiry.isAfter(now);
  }

  factory Announcement.fromDoc(String id, Map<String, dynamic> data) =>
      Announcement(
        id: id,
        title: data['title'] as String? ?? '',
        body: data['body'] as String? ?? '',
        type: AnnouncementType.fromId(data['type']),
        publishedAt: _date(data['publishedAt']) ?? _date(data['createdAt']),
        expiresAt: _date(data['expiresAt']),
        actorUid: data['actorUid'] as String? ?? '',
      );
}

/// Result of one lightweight source probe, stored in `systemMonitor/{sourceId}`.
@immutable
class SourceHealth {
  const SourceHealth({
    required this.id,
    required this.label,
    this.url = '',
    this.ok = false,
    this.checkedAt,
    this.lastSuccessAt,
    this.lastFailureAt,
    this.httpStatus = 0,
    this.latencyMs = 0,
    this.error = '',
    this.neverChecked = false,
  });

  final String id;
  final String label;
  final String url;
  final bool ok;
  final DateTime? checkedAt;
  final DateTime? lastSuccessAt;
  final DateTime? lastFailureAt;
  final int httpStatus;
  final int latencyMs;
  final String error;
  final bool neverChecked;

  factory SourceHealth.fromDoc(String id, Map<String, dynamic> data) =>
      SourceHealth(
        id: id,
        label: data['label'] as String? ?? id,
        url: data['url'] as String? ?? '',
        ok: data['ok'] == true,
        checkedAt: _date(data['checkedAt']),
        lastSuccessAt: _date(data['lastSuccessAt']),
        lastFailureAt: _date(data['lastFailureAt']),
        httpStatus: (data['httpStatus'] as num?)?.toInt() ?? 0,
        latencyMs: (data['latencyMs'] as num?)?.toInt() ?? 0,
        error: data['error'] as String? ?? '',
      );
}

/// Aggregate counters for the Owner dashboard. Every number comes from a
/// server-side `count()` aggregation, never from a hardcoded value.
@immutable
class AdminStats {
  const AdminStats({
    this.totalUsers = 0,
    this.registeredToday = 0,
    this.registeredThisWeek = 0,
    this.activeAccounts = 0,
    this.warnedAccounts = 0,
    this.restrictedAccounts = 0,
    this.suspendedAccounts = 0,
    this.bannedAccounts = 0,
    this.underReviewAccounts = 0,
    this.pendingReports = 0,
    this.reviewingReports = 0,
    this.resolvedReports = 0,
    this.rejectedReports = 0,
    this.pendingAppeals = 0,
    this.totalOwnerMessages = 0,
    this.loadedAt,
  });

  final int totalUsers;
  final int registeredToday;
  final int registeredThisWeek;
  final int activeAccounts;
  final int warnedAccounts;
  final int restrictedAccounts;
  final int suspendedAccounts;
  final int bannedAccounts;
  final int underReviewAccounts;
  final int pendingReports;
  final int reviewingReports;
  final int resolvedReports;
  final int rejectedReports;
  final int pendingAppeals;
  final int totalOwnerMessages;
  final DateTime? loadedAt;
}

/// A row in the Owner's user browser.
@immutable
class AdminUserSummary {
  const AdminUserSummary({
    required this.uid,
    required this.username,
    required this.displayName,
    this.photoVersion = 0,
    this.createdAt,
    this.status = AccountState.active,
    this.privateProfile = false,
    this.warningCount = 0,
    this.role = StaffRole.user,
    this.deleted = false,
  });

  final String uid;
  final String username;
  final String displayName;
  final int photoVersion;
  final DateTime? createdAt;
  final AccountState status;
  final bool privateProfile;
  final int warningCount;
  final StaffRole role;
  final bool deleted;

  String get label => displayName.isEmpty ? '@$username' : displayName;

  factory AdminUserSummary.fromDoc(String uid, Map<String, dynamic> data) {
    final privacy = data['privacy'];
    return AdminUserSummary(
      uid: uid,
      username: data['username'] as String? ?? '',
      displayName: data['displayName'] as String? ?? '',
      photoVersion: (data['photoVersion'] as num?)?.toInt() ?? 0,
      createdAt: _date(data['createdAt']),
      status: AccountState.fromId(data['status']),
      privateProfile: privacy is Map && privacy['showProfile'] == false,
      warningCount: (data['warningCount'] as num?)?.toInt() ?? 0,
      role: StaffRole.fromId(data['staffRole']),
      deleted: data['status'] == AccountState.deleted.id,
    );
  }
}

/// Everything the administrative user page shows, loaded in one place.
@immutable
class AdminUserDetail {
  const AdminUserDetail({
    required this.summary,
    this.status = const AccountStatusRecord(),
    this.warnings = const <AdminWarning>[],
    this.history = const <AdminLogEntry>[],
    this.reports = const <AdminReport>[],
    this.ownerMessages = const <OwnerMessage>[],
    this.role = StaffRole.user,
    this.pendingDeletion = false,
  });

  final AdminUserSummary summary;
  final AccountStatusRecord status;
  final List<AdminWarning> warnings;
  final List<AdminLogEntry> history;
  final List<AdminReport> reports;
  final List<OwnerMessage> ownerMessages;
  final StaffRole role;
  final bool pendingDeletion;
}
