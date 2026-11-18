import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import 'account_status.dart';

/// Role hierarchy of the administration system.
///
/// The role is never read from a field the account can edit: it comes from
/// `config/admins`, a document only the Firebase console (or a trusted server)
/// can write, mirroring Firebase Custom Claims.
enum StaffRole {
  user('0', 'مستخدم', 'User'),
  moderator('1', 'مشرف', 'Moderator'),
  admin('2', 'مدير', 'Admin'),
  owner('3', 'المالك', 'Owner');

  const StaffRole(this.rank, this.arabic, this.english);

  final String rank;
  final String arabic;
  final String english;

  bool atLeast(StaffRole other) =>
      int.parse(rank) >= int.parse(other.rank);

  bool get isStaff => this != StaffRole.user;

  static StaffRole fromStorage(Object? raw) => switch (raw) {
    'owner' => StaffRole.owner,
    'admin' => StaffRole.admin,
    'moderator' => StaffRole.moderator,
    _ => StaffRole.user,
  };
}

/// One account as shown in the administration lists.
@immutable
class AdminUser {
  const AdminUser({
    required this.uid,
    required this.username,
    required this.displayName,
    required this.createdAt,
    this.photoVersion = 0,
    this.standing = AccountStanding.none,
    this.bio = '',
    this.country = '',
    this.ageGroup = '',
    this.showProfile = true,
    this.badges = const <String, bool>{},
    this.favorites = const <String>[],
    this.stats = const <String, int>{},
    this.emailHash = '',
  });

  final String uid;
  final String username;
  final String displayName;
  final DateTime createdAt;
  final int photoVersion;
  final AccountStanding standing;
  final String bio;
  final String country;
  final String ageGroup;

  /// The profile privacy master switch (`privacy.showProfile`).
  final bool showProfile;
  final Map<String, bool> badges;
  final List<String> favorites;
  final Map<String, int> stats;

  /// SHA-256 of the registration address, kept for owner email blocks. The raw
  /// address is never stored in Firestore.
  final String emailHash;

  String get handle => '@$username';

  bool get isAdminVerified => badges['verified'] == true;

  bool get isAdminDeveloper => badges['developer'] == true;

  factory AdminUser.fromDoc(String uid, Map<String, dynamic> raw) {
    DateTime readDate(Object? value) {
      if (value is Timestamp) return value.toDate();
      if (value is DateTime) return value;
      return DateTime.fromMillisecondsSinceEpoch(0);
    }

    int readInt(Object? value) =>
        value is num ? value.toInt() : 0;

    final privacy = raw['privacy'];
    final showProfile = privacy is Map ? privacy['showProfile'] != false : true;
    final badges = raw['badges'];
    final favorites = raw['favorites'];
    final stats = raw['stats'];
    return AdminUser(
      uid: uid,
      username: raw['username'] as String? ?? '',
      displayName: raw['displayName'] as String? ?? '',
      createdAt: readDate(raw['createdAt']),
      photoVersion: readInt(raw['photoVersion']),
      standing: AccountStanding.fromMap(uid, raw),
      bio: raw['bio'] as String? ?? '',
      country: raw['country'] as String? ?? '',
      ageGroup: raw['ageGroup'] as String? ?? '',
      showProfile: showProfile,
      badges: <String, bool>{
        'verified': badges is Map && badges['verified'] == true,
        'developer': badges is Map && badges['developer'] == true,
      },
      favorites: favorites is List
          ? favorites
                .whereType<Map>()
                .map((item) => item['title'] as String? ?? '')
                .where((title) => title.isNotEmpty)
                .toList(growable: false)
          : const <String>[],
      stats: stats is Map
          ? <String, int>{
              'animeWatched': readInt(stats['animeWatched']),
              'episodesWatched': readInt(stats['episodesWatched']),
              'favorites': readInt(stats['favorites']),
              'completed': readInt(stats['completed']),
            }
          : const <String, int>{},
      emailHash: raw['emailHash'] as String? ?? '',
    );
  }
}

/// One page of the user list, with the cursor needed for the next one.
class AdminUserPage {
  const AdminUserPage({
    required this.items,
    required this.cursor,
    required this.hasMore,
  });

  final List<AdminUser> items;
  final DocumentSnapshot<Map<String, dynamic>>? cursor;
  final bool hasMore;
}

/// Counters shown on the developer dashboard.
@immutable
class AdminDashboardStats {
  const AdminDashboardStats({
    required this.totalUsers,
    required this.registeredToday,
    required this.registeredThisWeek,
    required this.activeAccounts,
    required this.suspendedAccounts,
    required this.bannedAccounts,
    required this.restrictedAccounts,
    required this.underReviewAccounts,
    required this.deletedAccounts,
    required this.pendingReports,
    required this.reviewedReports,
    required this.resolvedReports,
    required this.recentUsers,
    required this.recentActions,
    required this.loadedAt,
  });

  final int totalUsers;
  final int registeredToday;
  final int registeredThisWeek;
  final int activeAccounts;
  final int suspendedAccounts;
  final int bannedAccounts;
  final int restrictedAccounts;
  final int underReviewAccounts;
  final int deletedAccounts;
  final int pendingReports;
  final int reviewedReports;
  final int resolvedReports;
  final List<AdminUser> recentUsers;
  final List<AdminActionRecord> recentActions;
  final DateTime loadedAt;
}

/// One entry of the administrative audit log (`adminActions`).
@immutable
class AdminActionRecord {
  const AdminActionRecord({
    required this.id,
    required this.action,
    required this.targetUid,
    required this.targetUsername,
    required this.actorUid,
    required this.actorName,
    required this.reason,
    required this.createdAt,
    this.details = const <String, dynamic>{},
  });

  final String id;
  final String action;
  final String targetUid;
  final String targetUsername;
  final String actorUid;
  final String actorName;
  final String reason;
  final DateTime createdAt;
  final Map<String, dynamic> details;

  factory AdminActionRecord.fromDoc(String id, Map<String, dynamic> raw) {
    final created = raw['createdAt'];
    return AdminActionRecord(
      id: id,
      action: raw['action'] as String? ?? '',
      targetUid: raw['targetUid'] as String? ?? '',
      targetUsername: raw['targetUsername'] as String? ?? '',
      actorUid: raw['actorUid'] as String? ?? '',
      actorName: raw['actorName'] as String? ?? '',
      reason: raw['reason'] as String? ?? '',
      createdAt: created is Timestamp
          ? created.toDate()
          : DateTime.fromMillisecondsSinceEpoch(0),
      details: raw['details'] is Map
          ? Map<String, dynamic>.from(raw['details'] as Map)
          : const <String, dynamic>{},
    );
  }
}

/// A formal warning issued to an account (`users/{uid}/warnings`).
@immutable
class AdminWarning {
  const AdminWarning({
    required this.id,
    required this.category,
    required this.reason,
    required this.createdAt,
    required this.actorUid,
    this.active = true,
    this.revokedAt,
    this.revokedBy = '',
  });

  final String id;
  final String category;
  final String reason;
  final DateTime createdAt;
  final String actorUid;
  final bool active;
  final DateTime? revokedAt;
  final String revokedBy;

  factory AdminWarning.fromDoc(String id, Map<String, dynamic> raw) {
    DateTime? readDate(String key) {
      final value = raw[key];
      return value is Timestamp ? value.toDate() : null;
    }

    return AdminWarning(
      id: id,
      category: raw['category'] as String? ?? 'policy',
      reason: raw['reason'] as String? ?? '',
      createdAt:
          readDate('createdAt') ?? DateTime.fromMillisecondsSinceEpoch(0),
      actorUid: raw['actorUid'] as String? ?? '',
      active: raw['active'] != false,
      revokedAt: readDate('revokedAt'),
      revokedBy: raw['revokedBy'] as String? ?? '',
    );
  }
}

/// A user report (`reports/{id}`), reviewable from Developer Tools.
@immutable
class AdminReport {
  const AdminReport({
    required this.id,
    required this.reporterUid,
    required this.targetType,
    required this.reason,
    required this.status,
    required this.createdAt,
    this.targetUid = '',
    this.episodeId = '',
    this.commentId = '',
    this.reviewNote = '',
  });

  final String id;
  final String reporterUid;
  final String targetType;
  final String reason;
  final String status;
  final DateTime createdAt;
  final String targetUid;
  final String episodeId;
  final String commentId;
  final String reviewNote;

  bool get isOpen => status == 'open';

  factory AdminReport.fromDoc(String id, Map<String, dynamic> raw) {
    final created = raw['createdAt'];
    return AdminReport(
      id: id,
      reporterUid: raw['reporterUid'] as String? ?? '',
      targetType: raw['targetType'] as String? ?? '',
      reason: raw['reason'] as String? ?? '',
      status: raw['status'] as String? ?? 'open',
      createdAt: created is Timestamp
          ? created.toDate()
          : DateTime.fromMillisecondsSinceEpoch(0),
      targetUid: raw['targetUid'] as String? ?? '',
      episodeId: raw['episodeId'] as String? ?? '',
      commentId: raw['commentId'] as String? ?? '',
      reviewNote: raw['reviewNote'] as String? ?? '',
    );
  }
}

/// A blocked email address.
///
/// The document id is the SHA-256 of the normalized address, so the denylist
/// never stores (nor exposes) raw addresses. Members are readable by staff
/// only, and registration probes the collection through rules instead of
/// reading it.
@immutable
class BlockedEmail {
  const BlockedEmail({
    required this.hash,
    required this.reason,
    required this.createdAt,
    this.createdBy = '',
    this.domain = '',
  });

  final String hash;
  final String reason;
  final DateTime createdAt;
  final String createdBy;
  final String domain;

  factory BlockedEmail.fromDoc(String id, Map<String, dynamic> raw) {
    final created = raw['createdAt'];
    return BlockedEmail(
      hash: id,
      reason: raw['reason'] as String? ?? '',
      createdAt: created is Timestamp
          ? created.toDate()
          : DateTime.fromMillisecondsSinceEpoch(0),
      createdBy: raw['createdBy'] as String? ?? '',
      domain: raw['domain'] as String? ?? '',
    );
  }
}

/// A blocked username (`usernameBlocks/{normalized}`).
@immutable
class BlockedUsername {
  const BlockedUsername({
    required this.normalized,
    required this.reason,
    required this.createdAt,
    this.createdBy = '',
  });

  final String normalized;
  final String reason;
  final DateTime createdAt;
  final String createdBy;

  factory BlockedUsername.fromDoc(String id, Map<String, dynamic> raw) {
    final created = raw['createdAt'];
    return BlockedUsername(
      normalized: id,
      reason: raw['reason'] as String? ?? '',
      createdAt: created is Timestamp
          ? created.toDate()
          : DateTime.fromMillisecondsSinceEpoch(0),
      createdBy: raw['createdBy'] as String? ?? '',
    );
  }
}

/// A personal message from the Wings owner (`ownerMessages/{uid}/items`).
@immutable
class OwnerMessage {
  const OwnerMessage({
    required this.id,
    required this.title,
    required this.body,
    required this.senderUid,
    required this.senderName,
    required this.createdAt,
    this.read = false,
  });

  final String id;
  final String title;
  final String body;
  final String senderUid;
  final String senderName;
  final DateTime createdAt;
  final bool read;

  factory OwnerMessage.fromDoc(String id, Map<String, dynamic> raw) {
    final created = raw['createdAt'];
    return OwnerMessage(
      id: id,
      title: raw['title'] as String? ?? '',
      body: raw['body'] as String? ?? '',
      senderUid: raw['senderUid'] as String? ?? '',
      senderName: raw['senderName'] as String? ?? '',
      createdAt: created is Timestamp
          ? created.toDate()
          : DateTime.fromMillisecondsSinceEpoch(0),
      read: raw['read'] == true,
    );
  }
}

/// An administrative notification stored for the affected account
/// (`users/{uid}/adminNotices`). They are kept separate from community replies
/// so they can always be read later, even after the first alert was missed.
@immutable
class AdminNotice {
  const AdminNotice({
    required this.id,
    required this.title,
    required this.body,
    required this.category,
    required this.createdAt,
    this.severity = 'info',
    this.reason = '',
    this.restrictions = const <String>[],
    this.expiresAt,
    this.read = false,
  });

  final String id;
  final String title;
  final String body;
  final String category;
  final DateTime createdAt;
  final String severity;
  final String reason;
  final List<String> restrictions;
  final DateTime? expiresAt;
  final bool read;

  factory AdminNotice.fromDoc(String id, Map<String, dynamic> raw) {
    final created = raw['createdAt'];
    final expires = raw['expiresAt'];
    final restrictions = raw['restrictions'];
    return AdminNotice(
      id: id,
      title: raw['title'] as String? ?? '',
      body: raw['body'] as String? ?? '',
      category: raw['category'] as String? ?? 'info',
      createdAt: created is Timestamp
          ? created.toDate()
          : DateTime.fromMillisecondsSinceEpoch(0),
      severity: raw['severity'] as String? ?? 'info',
      reason: raw['reason'] as String? ?? '',
      restrictions: restrictions is List
          ? restrictions.whereType<String>().toList(growable: false)
          : const <String>[],
      expiresAt: expires is Timestamp ? expires.toDate() : null,
      read: raw['read'] == true,
    );
  }
}
