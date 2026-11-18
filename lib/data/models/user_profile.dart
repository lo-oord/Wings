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

  /// A handle that carries both marks is drawn with the royal gradient.
  bool get both => verified && developer;

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
///
/// [showProfile] is the master switch: when it is off the mirror carries no
/// personal fields at all and other users only see that the account is private.
@immutable
class ProfilePrivacy {
  const ProfilePrivacy({
    this.showProfile = true,
    this.bio = false,
    this.country = false,
    this.age = false,
    this.favorites = false,
    this.stats = false,
  });

  static const ProfilePrivacy defaults = ProfilePrivacy();

  /// Whether other users can open this profile at all.
  final bool showProfile;
  final bool bio;
  final bool country;
  final bool age;
  final bool favorites;
  final bool stats;

  factory ProfilePrivacy.fromMap(Object? raw) {
    if (raw is! Map) return defaults;
    return ProfilePrivacy(
      // Older documents predate these switches. A profile stays visible so
      // comments keep working, while the bio is opt-in like every other field.
      showProfile: raw['showProfile'] != false,
      bio: raw['bio'] == true,
      country: raw['country'] == true,
      age: raw['age'] == true,
      favorites: raw['favorites'] == true,
      stats: raw['stats'] == true,
    );
  }

  Map<String, dynamic> toMap() => <String, dynamic>{
    'showProfile': showProfile,
    'bio': bio,
    'country': country,
    'age': age,
    'favorites': favorites,
    'stats': stats,
  };

  ProfilePrivacy copyWith({
    bool? showProfile,
    bool? bio,
    bool? country,
    bool? age,
    bool? favorites,
    bool? stats,
  }) => ProfilePrivacy(
    showProfile: showProfile ?? this.showProfile,
    bio: bio ?? this.bio,
    country: country ?? this.country,
    age: age ?? this.age,
    favorites: favorites ?? this.favorites,
    stats: stats ?? this.stats,
  );
}

/// A favourite shown on a public profile. It is a display-only snapshot: no
/// progress, history or private library data is published with it.
@immutable
class ProfileFavorite {
  const ProfileFavorite({
    required this.animeId,
    required this.title,
    this.imageUrl = '',
  });

  final String animeId;
  final String title;
  final String imageUrl;

  factory ProfileFavorite.fromMap(Object? raw) {
    if (raw is! Map) {
      return const ProfileFavorite(animeId: '', title: '');
    }
    return ProfileFavorite(
      animeId: raw['animeId'] as String? ?? '',
      title: raw['title'] as String? ?? '',
      imageUrl: raw['imageUrl'] as String? ?? '',
    );
  }

  Map<String, dynamic> toMap() => <String, dynamic>{
    'animeId': animeId,
    'title': title,
    'imageUrl': imageUrl,
  };
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
    this.favorites = const <ProfileFavorite>[],
    this.badges = ProfileBadges.none,
    this.photoVersion = 0,
    this.coverVersion = 0,
    this.pendingDeletion = false,
    this.profileHidden = false,
    this.usernameChangedAt,
  });

  final String uid;
  final String username;
  final String displayName;
  final String country;
  final String ageGroup;
  final String bio;
  final ProfilePrivacy privacy;
  final ProfileStats stats;

  /// Favourite titles published with the public mirror, newest first. The list
  /// is empty until the owner enables the favourites privacy switch.
  final List<ProfileFavorite> favorites;
  final ProfileBadges badges;
  final int photoVersion;

  /// Bumped whenever the cover picture changes, so every device drops its
  /// cached banner. The bytes live in `users/{uid}/private/cover`.
  final int coverVersion;
  final bool pendingDeletion;

  /// True when this came from the public mirror of an account whose owner hid
  /// their profile. Only the handle and badges are published in that case.
  final bool profileHidden;
  final DateTime createdAt;
  final DateTime updatedAt;

  /// When the handle was last changed. A regular account may rename once every
  /// [usernameChangeInterval]; verified and developer accounts rename freely.
  final DateTime? usernameChangedAt;

  static const Duration usernameChangeInterval = Duration(hours: 48);

  /// Official accounts (verified or developer) are exempt from the cooldown.
  bool get freeUsernameChanges => badges.any;

  /// The moment the next rename becomes possible, or null when it is possible
  /// right now.
  DateTime? get nextUsernameChangeAt {
    if (freeUsernameChanges) return null;
    final changed = usernameChangedAt;
    if (changed == null) return null;
    final next = changed.add(usernameChangeInterval);
    return next;
  }

  bool canChangeUsernameAt(DateTime now) {
    if (freeUsernameChanges) return true;
    final next = nextUsernameChangeAt;
    return next == null || !now.isBefore(next);
  }

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
    List<ProfileFavorite>? favorites,
    ProfileBadges? badges,
    int? photoVersion,
    int? coverVersion,
    bool? pendingDeletion,
    bool? profileHidden,
    DateTime? usernameChangedAt,
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
    favorites: favorites ?? this.favorites,
    badges: badges ?? this.badges,
    photoVersion: photoVersion ?? this.photoVersion,
    coverVersion: coverVersion ?? this.coverVersion,
    pendingDeletion: pendingDeletion ?? this.pendingDeletion,
    profileHidden: profileHidden ?? this.profileHidden,
    usernameChangedAt: usernameChangedAt ?? this.usernameChangedAt,
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
    'favorites': favorites.map((item) => item.toMap()).toList(),
    'badges': badges.toMap(),
    'photoVersion': photoVersion,
    'coverVersion': coverVersion,
    'pendingDeletion': pendingDeletion,
    if (usernameChangedAt != null)
      'usernameChangedAt': Timestamp.fromDate(usernameChangedAt!),
    'createdAt': Timestamp.fromDate(createdAt),
    'updatedAt': Timestamp.fromDate(updatedAt),
  };

  /// Public mirror document. Only fields the owner allowed are present, so a
  /// reader can never see private values even before the UI filters anything.
  ///
  /// The handle and badges always stay visible because comments show them, but
  /// a profile the owner hid carries nothing else. A batch `set(merge: true)`
  /// never removes a key, so `save()` uses a plain `set` for the mirror.
  Map<String, dynamic> toMapPublic() {
    final base = <String, dynamic>{
      'username': username,
      'normalizedUsername': normalizedUsername,
      'displayName': displayName,
      'badges': badges.toMap(),
      'photoVersion': photoVersion,
      'coverVersion': coverVersion,
      'updatedAt': Timestamp.fromDate(updatedAt),
    };
    if (!privacy.showProfile) {
      return base..['private'] = true;
    }
    return base
      ..['private'] = false
      ..addAll(<String, dynamic>{
        if (privacy.bio && bio.isNotEmpty) 'bio': bio,
        if (privacy.country) 'country': country,
        if (privacy.age) 'ageGroup': ageGroup,
        if (privacy.stats) 'stats': stats.toMap(),
        if (privacy.favorites)
          'favorites': favorites.take(12).map((item) => item.toMap()).toList(),
      });
  }

  factory UserProfile.fromMap(String uid, Map<String, dynamic> raw) {
    DateTime readDate(String key) {
      final value = raw[key];
      if (value is Timestamp) return value.toDate();
      if (value is DateTime) return value;
      return DateTime.now();
    }

    DateTime? readOptionalDate(String key) {
      final value = raw[key];
      if (value is Timestamp) return value.toDate();
      if (value is DateTime) return value;
      return null;
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
      favorites: raw['favorites'] is List
          ? (raw['favorites'] as List)
                .map(ProfileFavorite.fromMap)
                .where((item) => item.animeId.isNotEmpty)
                .toList(growable: false)
          : const <ProfileFavorite>[],
      badges: ProfileBadges.fromMap(raw['badges']),
      photoVersion: (raw['photoVersion'] as num?)?.toInt() ?? 0,
      coverVersion: (raw['coverVersion'] as num?)?.toInt() ?? 0,
      pendingDeletion: raw['pendingDeletion'] == true,
      profileHidden: raw['private'] == true,
      usernameChangedAt: readOptionalDate('usernameChangedAt'),
      createdAt: readDate('createdAt'),
      updatedAt: readDate('updatedAt'),
    );
  }

  /// Reads a `profiles/{uid}` mirror. Missing optional fields stay empty and a
  /// missing statistic reads as zero, which the UI shows as "not shared".
  factory UserProfile.fromPublicMap(String uid, Map<String, dynamic> raw) =>
      UserProfile.fromMap(uid, raw);
}
