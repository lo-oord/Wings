import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

/// Central account state of a Wings account.
///
/// One field (`accountStatus`) describes the whole account instead of a set of
/// independent booleans, so two administrative decisions can never contradict
/// each other. Expiry is evaluated against the current time on every read, in
/// the client and in the security rules, so an expired suspension stops being
/// enforced even if no scheduled job ever ran.
enum AccountState {
  active('active', 'نشط', 'Active'),
  warned('warned', 'موعوظ', 'Warned'),
  restricted('restricted', 'مُقيَّد', 'Restricted'),
  suspended('suspended', 'موقوف مؤقتًا', 'Suspended'),
  banned('banned', 'محظور دائمًا', 'Permanently banned'),
  underReview('underReview', 'قيد المراجعة', 'Under review'),
  deleted('deleted', 'محذوف', 'Deleted');

  const AccountState(this.storage, this.arabic, this.english);

  /// Value stored in `users/{uid}.accountStatus`.
  final String storage;
  final String arabic;
  final String english;

  static AccountState fromStorage(Object? raw) {
    if (raw is! String) return AccountState.active;
    for (final state in AccountState.values) {
      if (state.storage == raw) return state;
    }
    return AccountState.active;
  }

  /// States that stop the account from using Wings at all.
  bool get blocksAccess =>
      this == AccountState.banned ||
      this == AccountState.deleted ||
      this == AccountState.suspended;
}

/// Feature switches an administrator can turn off without banning the account.
///
/// The keys are read by `firestore.rules`, so they are part of the security
/// contract, not just UI state.
@immutable
class AccountRestrictions {
  const AccountRestrictions({
    this.comment = false,
    this.post = false,
    this.interact = false,
    this.community = false,
    this.report = false,
  });

  static const AccountRestrictions none = AccountRestrictions();

  static const String commentKey = 'comment';
  static const String postKey = 'post';
  static const String interactKey = 'interact';
  static const String communityKey = 'community';
  static const String reportKey = 'report';

  final bool comment;
  final bool post;
  final bool interact;
  final bool community;
  final bool report;

  bool get any => comment || post || interact || community || report;

  bool isOn(String key) => switch (key) {
    commentKey => comment,
    postKey => post,
    interactKey => interact,
    communityKey => community,
    reportKey => report,
    _ => false,
  };

  AccountRestrictions withValue(String key, bool value) => AccountRestrictions(
    comment: key == commentKey ? value : comment,
    post: key == postKey ? value : post,
    interact: key == interactKey ? value : interact,
    community: key == communityKey ? value : community,
    report: key == reportKey ? value : report,
  );

  List<String> get enabledKeys => <String>[
    if (comment) commentKey,
    if (post) postKey,
    if (interact) interactKey,
    if (community) communityKey,
    if (report) reportKey,
  ];

  factory AccountRestrictions.fromMap(Object? raw) {
    if (raw is! Map) return none;
    bool read(String key) => raw[key] == true;
    return AccountRestrictions(
      comment: read(commentKey),
      post: read(postKey),
      interact: read(interactKey),
      community: read(communityKey),
      report: read(reportKey),
    );
  }

  Map<String, dynamic> toMap() => <String, dynamic>{
    commentKey: comment,
    postKey: post,
    interactKey: interact,
    communityKey: community,
    reportKey: report,
  };

  @override
  bool operator ==(Object other) =>
      other is AccountRestrictions &&
      other.comment == comment &&
      other.post == post &&
      other.interact == interact &&
      other.community == community &&
      other.report == report;

  @override
  int get hashCode =>
      Object.hash(comment, post, interact, community, report);
}

/// Administrative standing of one account, read from `users/{uid}`.
@immutable
class AccountStanding {
  const AccountStanding({
    required this.uid,
    this.state = AccountState.active,
    this.reason = '',
    this.updatedAt,
    this.expiresAt,
    this.actorUid = '',
    this.restrictions = AccountRestrictions.none,
    this.restrictionsExpireAt,
    this.warningsCount = 0,
  });

  static const AccountStanding none = AccountStanding(uid: '');

  final String uid;
  final AccountState state;
  final String reason;
  final DateTime? updatedAt;

  /// End of a temporary suspension. `null` means indefinite.
  final DateTime? expiresAt;

  /// The staff account that applied the current state.
  final String actorUid;

  final AccountRestrictions restrictions;

  /// End of the current restrictions. `null` means no expiry.
  final DateTime? restrictionsExpireAt;

  final int warningsCount;

  /// Suspension whose end time has already passed.
  bool get suspensionExpired {
    if (state != AccountState.suspended) return false;
    final end = expiresAt;
    return end != null && !DateTime.now().isBefore(end);
  }

  /// The state that is actually in force right now.
  AccountState get effectiveState =>
      suspensionExpired ? AccountState.active : state;

  bool get blocksAccess => effectiveState.blocksAccess;

  bool get isSuspended => effectiveState == AccountState.suspended;

  bool get isBanned => effectiveState == AccountState.banned;

  bool get isDeleted => effectiveState == AccountState.deleted;

  bool get restrictionsExpired {
    final end = restrictionsExpireAt;
    return end != null && !DateTime.now().isBefore(end);
  }

  AccountRestrictions get activeRestrictions =>
      restrictionsExpired ? AccountRestrictions.none : restrictions;

  /// True when [key] is currently disabled for this account.
  bool isRestricted(String key) => activeRestrictions.isOn(key);

  bool get canComment => !blocksAccess && !isRestricted(AccountRestrictions.commentKey);

  bool get canPost => !blocksAccess && !isRestricted(AccountRestrictions.postKey);

  bool get canInteract =>
      !blocksAccess && !isRestricted(AccountRestrictions.interactKey);

  bool get canUseCommunity =>
      !blocksAccess && !isRestricted(AccountRestrictions.communityKey);

  bool get canReport => !blocksAccess && !isRestricted(AccountRestrictions.reportKey);

  factory AccountStanding.fromMap(String uid, Map<String, dynamic> raw) {
    DateTime? readDate(String key) {
      final value = raw[key];
      if (value is Timestamp) return value.toDate();
      if (value is DateTime) return value;
      return null;
    }

    return AccountStanding(
      uid: uid,
      state: AccountState.fromStorage(raw['accountStatus']),
      reason: raw['statusReason'] as String? ?? '',
      updatedAt: readDate('statusUpdatedAt'),
      expiresAt: readDate('statusExpiresAt'),
      actorUid: raw['statusActorUid'] as String? ?? '',
      restrictions: AccountRestrictions.fromMap(raw['restrictions']),
      restrictionsExpireAt: readDate('restrictionsExpireAt'),
      warningsCount: (raw['warningsCount'] as num?)?.toInt() ?? 0,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is AccountStanding &&
      other.uid == uid &&
      other.state == state &&
      other.reason == reason &&
      other.expiresAt == expiresAt &&
      other.updatedAt == updatedAt &&
      other.actorUid == actorUid &&
      other.restrictions == restrictions &&
      other.restrictionsExpireAt == restrictionsExpireAt &&
      other.warningsCount == warningsCount;

  @override
  int get hashCode => Object.hash(
    uid,
    state,
    reason,
    expiresAt,
    updatedAt,
    actorUid,
    restrictions,
    restrictionsExpireAt,
    warningsCount,
  );
}
