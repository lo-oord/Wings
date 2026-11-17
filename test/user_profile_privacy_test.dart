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

    test('a hidden profile publishes nothing but the handle and badges', () {
      final mirror = _profile(
        privacy: const ProfilePrivacy(
          showProfile: false,
          bio: true,
          country: true,
          age: true,
          stats: true,
          favorites: true,
        ),
      ).toMapPublic();
      expect(mirror['private'], isTrue);
      expect(mirror['username'], 'shadow_07');
      expect(mirror.containsKey('bio'), isFalse);
      expect(mirror.containsKey('country'), isFalse);
      expect(mirror.containsKey('ageGroup'), isFalse);
      expect(mirror.containsKey('stats'), isFalse);
      expect(mirror.containsKey('favorites'), isFalse);
    });

    test('publishes bio and favourites only when the owner allows them', () {
      final profile =
          _profile(privacy: const ProfilePrivacy(bio: true, favorites: true))
              .copyWith(
                favorites: const <ProfileFavorite>[
                  ProfileFavorite(animeId: 'a1', title: 'Naruto'),
                ],
              );
      final mirror = profile.toMapPublic();
      expect(mirror['bio'], 'anime fan');
      expect(mirror['favorites'], <Map<String, dynamic>>[
        <String, dynamic>{'animeId': 'a1', 'title': 'Naruto', 'imageUrl': ''},
      ]);
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

  group('cover picture', () {
    test('the version is published but never the bytes', () {
      final profile = _profile(privacy: ProfilePrivacy.defaults)
          .copyWith(coverVersion: 4);
      final mirror = profile.toMapPublic();
      expect(mirror['coverVersion'], 4);
      expect(mirror.containsKey('bytes'), isFalse);
      expect(profile.toMap()['coverVersion'], 4);
    });

    test('reads back from the owner and the public documents', () {
      final raw = _profile(privacy: ProfilePrivacy.defaults)
          .copyWith(coverVersion: 7)
          .toMap();
      expect(UserProfile.fromMap('uid-1', raw).coverVersion, 7);
      expect(
        UserProfile.fromPublicMap('uid-1', <String, dynamic>{
          'username': 'shadow_07',
          'displayName': 'Shadow',
          'coverVersion': 2,
        }).coverVersion,
        2,
      );
      // Older documents without the field keep working.
      expect(
        UserProfile.fromPublicMap('uid-1', <String, dynamic>{
          'username': 'shadow_07',
          'displayName': 'Shadow',
        }).coverVersion,
        0,
      );
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
