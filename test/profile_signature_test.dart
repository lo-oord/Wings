import 'package:flutter_test/flutter_test.dart';
import 'package:wings/data/models/user_profile.dart';

UserProfile _profile({
  ProfileBadges badges = ProfileBadges.none,
  DateTime? usernameChangedAt,
}) => UserProfile(
  uid: 'uid-1',
  username: 'shadow_07',
  displayName: 'Shadow',
  badges: badges,
  usernameChangedAt: usernameChangedAt,
  createdAt: DateTime(2026, 1, 1),
  updatedAt: DateTime(2026, 1, 1),
);

void main() {
  group('username cooldown', () {
    test('a regular account waits 48 hours between changes', () {
      final changed = DateTime(2026, 3, 1, 12);
      final profile = _profile(usernameChangedAt: changed);
      expect(
        profile.canChangeUsernameAt(changed.add(const Duration(hours: 47))),
        isFalse,
      );
      expect(
        profile.canChangeUsernameAt(changed.add(const Duration(hours: 48))),
        isTrue,
      );
      expect(
        profile.nextUsernameChangeAt,
        changed.add(const Duration(hours: 48)),
      );
    });

    test('verified and developer accounts change freely', () {
      final changed = DateTime(2026, 3, 1);
      for (final badges in <ProfileBadges>[
        const ProfileBadges(verified: true),
        const ProfileBadges(developer: true),
        const ProfileBadges(verified: true, developer: true),
      ]) {
        final profile = _profile(badges: badges, usernameChangedAt: changed);
        expect(profile.canChangeUsernameAt(changed), isTrue);
        expect(profile.nextUsernameChangeAt, isNull);
      }
    });

    test('the first change is free and the timestamp round-trips', () {
      final profile = _profile();
      expect(profile.canChangeUsernameAt(DateTime(2026, 3, 1)), isTrue);
      final raw = profile
          .copyWith(usernameChangedAt: DateTime(2026, 3, 2))
          .toMap();
      expect(
        UserProfile.fromMap('uid-1', raw).usernameChangedAt,
        DateTime(2026, 3, 2),
      );
    });
  });

  group('official badges', () {
    test('a badge document wins outright, including when it clears', () {
      // The administrator document is authoritative: an empty map revokes both
      // marks instead of merging a stale copy back in.
      final cleared = ProfileBadges.fromMap(<String, dynamic>{
        'verified': false,
        'developer': false,
      });
      expect(cleared.any, isFalse);
      expect(ProfileBadges.fromMap(null), ProfileBadges.none);
      expect(const ProfileBadges(verified: true).both, isFalse);
      expect(const ProfileBadges(verified: true, developer: true).both, isTrue);
    });

    test('a badge document without the developer key reads as false', () {
      final badges = ProfileBadges.fromMap(<String, dynamic>{'verified': true});
      expect(badges.verified, isTrue);
      expect(badges.developer, isFalse);
    });
  });
}
