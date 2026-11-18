import 'package:flutter_test/flutter_test.dart';
import 'package:wings/data/models/admin_models.dart';

void main() {
  group('staff roles', () {
    test('only the trusted document id maps to a staff role', () {
      expect(StaffRole.fromId('owner'), StaffRole.owner);
      expect(StaffRole.fromId('admin'), StaffRole.admin);
      expect(StaffRole.fromId('moderator'), StaffRole.moderator);
      expect(StaffRole.fromId('Owner'), StaffRole.owner);
      expect(StaffRole.fromId(null), StaffRole.user);
      expect(StaffRole.fromId('superuser'), StaffRole.user);
    });

    test('owner outranks admin, admin outranks moderator', () {
      expect(StaffRole.owner.atLeast(StaffRole.admin), isTrue);
      expect(StaffRole.admin.atLeast(StaffRole.owner), isFalse);
      expect(StaffRole.moderator.isStaff, isTrue);
      expect(StaffRole.moderator.isAdmin, isFalse);
      expect(StaffRole.user.isStaff, isFalse);
    });
  });

  group('temporary suspension', () {
    final now = DateTime(2026, 11, 18, 12);

    test('an unexpired suspension locks the account', () {
      final record = AccountStatusRecord(
        state: AccountState.suspended,
        startedAt: now.subtract(const Duration(hours: 2)),
        expiresAt: now.add(const Duration(hours: 22)),
      );
      expect(record.isSuspensionActive(now), isTrue);
      expect(record.isLockedAt(now), isTrue);
      expect(record.effectiveState(now), AccountState.suspended);
    });

    test('an expired suspension stops applying without any cleanup run', () {
      final record = AccountStatusRecord(
        state: AccountState.suspended,
        startedAt: now.subtract(const Duration(days: 8)),
        expiresAt: now.subtract(const Duration(days: 1)),
      );
      expect(record.isSuspensionActive(now), isFalse);
      expect(record.isLockedAt(now), isFalse);
      expect(record.effectiveState(now), AccountState.active);
    });

    test(
      'an expired suspension with live restrictions reads as restricted',
      () {
        final record = AccountStatusRecord(
          state: AccountState.suspended,
          expiresAt: now.subtract(const Duration(hours: 1)),
          restrictions: const <RestrictionFeature>{RestrictionFeature.comment},
          restrictionsPermanent: true,
        );
        expect(record.effectiveState(now), AccountState.restricted);
        expect(record.isRestricted(RestrictionFeature.comment, now), isTrue);
        expect(record.isRestricted(RestrictionFeature.post, now), isFalse);
      },
    );

    test('an indefinite suspension never expires on its own', () {
      final record = AccountStatusRecord(
        state: AccountState.suspended,
        permanent: true,
      );
      expect(record.isSuspensionActive(now), isTrue);
      expect(record.isLockedAt(DateTime(2080)), isTrue);
      expect(record.isBanPermanent, isTrue);
    });
  });

  group('permanent ban', () {
    test('a ban stays locked forever and is not a suspension', () {
      final record = AccountStatusRecord(
        state: AccountState.banned,
        permanent: true,
      );
      expect(record.isLockedAt(DateTime(2099)), isTrue);
      expect(record.isSuspensionActive(DateTime(2099)), isFalse);
      expect(record.effectiveState(DateTime(2099)), AccountState.banned);
    });

    test('a lifted ban with a remaining restriction is not silently active', () {
      // Mirrors the restore path: the state becomes active only when nothing is
      // left in force.
      final now = DateTime(2026, 11, 18);
      final record = AccountStatusRecord(
        state: AccountState.restricted,
        restrictions: const <RestrictionFeature>{
          RestrictionFeature.comment,
          RestrictionFeature.report,
        },
        restrictionsExpireAt: now.add(const Duration(days: 3)),
      );
      expect(record.effectiveState(now), AccountState.restricted);
      expect(record.activeRestrictions(now), hasLength(2));
      expect(
        record.activeRestrictions(now.add(const Duration(days: 4))),
        isEmpty,
      );
    });
  });

  group('account status record', () {
    test('round-trips state, reason, expiry and restrictions', () {
      final started = DateTime(2026, 5, 1, 10, 30);
      final expires = started.add(const Duration(days: 7));
      final record = AccountStatusRecord(
        state: AccountState.suspended,
        reason: 'spam',
        startedAt: started,
        expiresAt: expires,
        actorUid: 'owner-uid',
        actionId: 'action-1',
        previousState: AccountState.warned,
        restrictions: const <RestrictionFeature>{
          RestrictionFeature.comment,
          RestrictionFeature.interact,
        },
        restrictionsPermanent: false,
        restrictionsExpireAt: expires,
      );
      final map = record.toMap();
      expect(map['state'], 'suspended');
      expect(map['restrictComment'], isTrue);
      expect(map['restrictInteract'], isTrue);
      expect(map['restrictPost'], isFalse);
      expect(map['permanent'], isFalse);

      final parsed = AccountStatusRecord.fromMap(<String, dynamic>{
        ...map,
        'startedAt': map['startedAt'],
        'expiresAt': map['expiresAt'],
        'restrictionsExpireAt': map['restrictionsExpireAt'],
      });
      expect(parsed.state, AccountState.suspended);
      expect(parsed.reason, 'spam');
      expect(parsed.actorUid, 'owner-uid');
      expect(parsed.previousState, AccountState.warned);
      expect(parsed.restrictions, record.restrictions);
    });

    test('a missing document means an active, unrestricted account', () {
      const record = AccountStatusRecord();
      final now = DateTime(2026, 11, 18);
      expect(record.effectiveState(now), AccountState.active);
      expect(record.isLockedAt(now), isFalse);
      expect(record.activeRestrictions(now), isEmpty);
    });

    test('an unknown stored state falls back to active', () {
      final record = AccountStatusRecord.fromMap(<String, dynamic>{
        'state': 'not-a-state',
      });
      expect(record.state, AccountState.active);
    });
  });

  group('reports and notifications', () {
    test('a legacy open report reads as pending', () {
      final report = AdminReport.fromDoc('r1', <String, dynamic>{
        'status': 'open',
        'reason': 'spam',
      });
      expect(report.status, 'pending');
      expect(report.details, 'spam');
    });

    test('a dismissed report reads as rejected', () {
      final report = AdminReport.fromDoc('r2', <String, dynamic>{
        'status': 'dismissed',
      });
      expect(report.status, 'rejected');
    });
  });

  test('announcement expiry is computed, never assumed', () {
    final now = DateTime(2026, 11, 18);
    final live = Announcement(
      id: 'a',
      publishedAt: now.subtract(const Duration(days: 1)),
      expiresAt: now.add(const Duration(days: 1)),
    );
    final expired = Announcement(
      id: 'b',
      publishedAt: now.subtract(const Duration(days: 9)),
      expiresAt: now.subtract(const Duration(days: 1)),
    );
    expect(live.isLiveAt(now), isTrue);
    expect(expired.isLiveAt(now), isFalse);
  });
}
