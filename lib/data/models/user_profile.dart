import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

/// Official account badges. They are written only by administrators (enforced
/// in Firestore rules), never by the owning client.
@immutable
class ProfileBadges {
  const ProfileBadges({this.verified = false, this.developer = false});

  static const ProfileBadges none = ProfileBadges();

  final bool verified;
  final bool developer;

  bool get any => verified || developer;

  factory ProfileBadges.fromMap(Object? raw) {
    if (raw is! Map) return none;
    return ProfileBadges(
      verified: raw['verified'] == true,
      developer: raw['developer'] == true,
    );
  }

  Map<String, dynamic> toMap() => <String, dynamic>{
    'verified': verified,
    'developer': developer,
  };

  @override
  bool operator ==(Object other) =>
      other is ProfileBadges &&
      other.verified == verified &&
      other.developer == developer;

  @override
  int get hashCode => Object.hash(verified, developer);
}

/// Which profile fields the owner exposes to other users. The values gate both
/// the public mirror document and the UI, and the mirror is the only profile
/// document other users can read.
@immutable
class ProfilePrivacy {
  const ProfilePrivacy({
    this.country = false,
    this.age = false,
    this.favorites = false,
    this.stats = false,
  });

  static const ProfilePrivacy defaults = ProfilePrivacy();

  final bool country;
  final bool age;
  final bool favorites;
  final bool stats;

  factory ProfilePrivacy.fromMap(Object? raw) {
    if (raw is! Map) return defaults;
    return ProfilePrivacy(
      country: raw['country'] == true,
      age: raw['age'] == true,
      favorites: raw['favorites'] == true,
      stats: raw['stats'] == true,
    );
  }

  Map<String, dynamic> toMap() => <String, dynamic>{
    'country': country,
    'age': age,
    'favorites': favorites,
    'stats': stats,
  };

  ProfilePrivacy copyWith({
    bool? country,
    bool? age,
    bool? favorites,
    bool? stats,
  }) => ProfilePrivacy(
    country: country ?? this.country,
    age: age ?? this.age,
    favorites: favorites ?? this.favorites,
    stats: stats ?? this.stats,
  );
}

/// Viewer statistics. Maintained by the owner's client from local library data;
/// they are display-only and are never treated as trusted counters.
@immutable
class ProfileStats {
  const ProfileStats({
    this.animeWatched = 0,
    this.episodesWatched = 0,
    this.favorites = 0,
    this.completed = 0,
  });

  static const ProfileStats zero = ProfileStats();

  final int animeWatched;
  final int episodesWatched;
  final int favorites;
  final int completed;

  factory ProfileStats.fromMap(Object? raw) {
    if (raw is! Map) return zero;
    int read(String key) {
      final value = raw[key];
      return value is num ? value.toInt().clamp(0, 1 << 31) : 0;
    }

    return ProfileStats(
      animeWatched: read('animeWatched'),
      episodesWatched: read('episodesWatched'),
      favorites: read('favorites'),
      completed: read('completed'),
    );
  }

  Map<String, dynamic> toMap() => <String, dynamic>{
    'animeWatched': animeWatched.clamp(0, 1 << 31),
    'episodesWatched': episodesWatched.clamp(0, 1 << 31),
    'favorites': favorites.clamp(0, 1 << 31),
    'completed': completed.clamp(0, 1 << 31),
  };

  ProfileStats copyWith({
    int? animeWatched,
    int? episodesWatched,
    int? favorites,
    int? completed,
  }) => ProfileStats(
    animeWatched: animeWatched ?? this.animeWatched,
    episodesWatched: episodesWatched ?? this.episodesWatched,
    favorites: favorites ?? this.favorites,
    completed: completed ?? this.completed,
  );
}

/// The owner-only profile document (`users/{uid}`).
///
/// Public data is mirrored into `profiles/{uid}` by [publicMap] so privacy is
/// enforced by document structure, not by hiding fields in the UI.
@immutable
class UserProfile {
  const UserProfile({
    required this.uid,
    required this.username,
    required this.displayName,
    required this.createdAt,
    required this.updatedAt,
    this.country = '',
    this.ageGroup = '',
    this.bio = '',
    this.privacy = ProfilePrivacy.defaults,
    this.stats = ProfileStats.zero,
    this.badges = ProfileBadges.none,
    this.photoVersion = 0,
    this.pendingDeletion = false,
  });

  final String uid;
  final String username;
  final String displayName;
  final String country;
  final String ageGroup;
  final String bio;
  final ProfilePrivacy privacy;
  final ProfileStats stats;
  final ProfileBadges badges;
  final int photoVersion;
  final bool pendingDeletion;
  final DateTime createdAt;
  final DateTime updatedAt;

  String get normalizedUsername => username.trim().toLowerCase();

  String get handle => '@$username';

  UserProfile copyWith({
    String? username,
    String? displayName,
    String? country,
    String? ageGroup,
    String? bio,
    ProfilePrivacy? privacy,
    ProfileStats? stats,
    ProfileBadges? badges,
    int? photoVersion,
    bool? pendingDeletion,
    DateTime? updatedAt,
  }) => UserProfile(
    uid: uid,
    username: username ?? this.username,
    displayName: displayName ?? this.displayName,
    country: country ?? this.country,
    ageGroup: ageGroup ?? this.ageGroup,
    bio: bio ?? this.bio,
    privacy: privacy ?? this.privacy,
    stats: stats ?? this.stats,
    badges: badges ?? this.badges,
    photoVersion: photoVersion ?? this.photoVersion,
    pendingDeletion: pendingDeletion ?? this.pendingDeletion,
    createdAt: createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );

  /// Full owner document.
  Map<String, dynamic> toMap() => <String, dynamic>{
    'username': username,
    'normalizedUsername': normalizedUsername,
    'displayName': displayName,
    'country': country,
    'ageGroup': ageGroup,
    'bio': bio,
    'privacy': privacy.toMap(),
    'stats': stats.toMap(),
    'badges': badges.toMap(),
    'photoVersion': photoVersion,
    'pendingDeletion': pendingDeletion,
    'createdAt': Timestamp.fromDate(createdAt),
    'updatedAt': Timestamp.fromDate(updatedAt),
  };

  /// Public mirror document. Only fields the owner allowed are present, so a
  /// reader can never see private values even before the UI filters anything.
  Map<String, dynamic> toMapPublic() => <String, dynamic>{
    'username': username,
    'normalizedUsername': normalizedUsername,
    'displayName': displayName,
    'badges': badges.toMap(),
    'photoVersion': photoVersion,
    'updatedAt': Timestamp.fromDate(updatedAt),
    if (privacy.country) 'country': country,
    if (privacy.age) 'ageGroup': ageGroup,
    if (privacy.stats) 'stats': stats.toMap(),
  };

  factory UserProfile.fromMap(String uid, Map<String, dynamic> raw) {
    DateTime readDate(String key) {
      final value = raw[key];
      if (value is Timestamp) return value.toDate();
      if (value is DateTime) return value;
      return DateTime.now();
    }

    return UserProfile(
      uid: uid,
      username: raw['username'] as String? ?? '',
      displayName: raw['displayName'] as String? ?? '',
      country: raw['country'] as String? ?? '',
      ageGroup: raw['ageGroup'] as String? ?? '',
      bio: raw['bio'] as String? ?? '',
      privacy: ProfilePrivacy.fromMap(raw['privacy']),
      stats: ProfileStats.fromMap(raw['stats']),
      badges: ProfileBadges.fromMap(raw['badges']),
      photoVersion: (raw['photoVersion'] as num?)?.toInt() ?? 0,
      pendingDeletion: raw['pendingDeletion'] == true,
      createdAt: readDate('createdAt'),
      updatedAt: readDate('updatedAt'),
    );
  }

  /// Reads a `profiles/{uid}` mirror. Missing optional fields stay empty and a
  /// missing statistic reads as zero, which the UI shows as "not shared".
  factory UserProfile.fromPublicMap(String uid, Map<String, dynamic> raw) =>
      UserProfile.fromMap(uid, raw);
}
