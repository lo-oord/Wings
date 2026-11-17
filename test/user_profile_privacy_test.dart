import 'package:flutter_test/flutter_test.dart';
import 'package:wings/data/models/user_profile.dart';

UserProfile _profile({
  required ProfilePrivacy privacy,
  ProfileBadges badges = ProfileBadges.none,
}) => UserProfile(
  uid: 'uid-1',
  username: 'shadow_07',
  displayName: 'Shadow',
  country: 'SA',
  ageGroup: '18-24',
  bio: 'anime fan',
  privacy: privacy,
  stats: const ProfileStats(
    animeWatched: 12,
    episodesWatched: 240,
    favorites: 5,
    completed: 3,
  ),
  badges: badges,
  createdAt: DateTime(2026, 1, 1),
  updatedAt: DateTime(2026, 2, 1),
);

void main() {
  group('public profile mirror', () {
    test('omits every private field by default', () {
      final mirror = _profile(privacy: ProfilePrivacy.defaults).toMapPublic();
      expect(mirror.containsKey('country'), isFalse);
      expect(mirror.containsKey('ageGroup'), isFalse);
      expect(mirror.containsKey('stats'), isFalse);
      // Never present, whatever the privacy settings are.
      expect(mirror.containsKey('privacy'), isFalse);
      expect(mirror.containsKey('bio'), isFalse);
      expect(mirror['username'], 'shadow_07');
      expect(mirror['displayName'], 'Shadow');
    });

    test('includes only the fields the owner allowed', () {
      final mirror = _profile(
        privacy: const ProfilePrivacy(country: true, stats: true),
      ).toMapPublic();
      expect(mirror['country'], 'SA');
      expect(mirror['stats'], isA<Map<String, dynamic>>());
      expect(mirror.containsKey('ageGroup'), isFalse);
    });

    test('carries badges so usernames render correctly in public', () {
      final mirror = _profile(
        privacy: ProfilePrivacy.defaults,
        badges: const ProfileBadges(verified: true, developer: true),
      ).toMapPublic();
      expect(mirror['badges'], <String, dynamic>{
        'verified': true,
        'developer': true,
      });
    });
  });

  group('reading documents', () {
    test('tolerates missing optional fields', () {
      final profile = UserProfile.fromPublicMap('uid-9', <String, dynamic>{
        'username': 'new_user',
        'displayName': 'New',
      });
      expect(profile.country, '');
      expect(profile.stats.animeWatched, 0);
      expect(profile.badges.any, isFalse);
      expect(profile.privacy.stats, isFalse);
    });
  });
}
