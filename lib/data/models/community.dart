import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import 'user_profile.dart';

/// What a unified post carries.
///
/// One model and one document serve every kind: text, pictures, a video inside
/// the feed, and a short vertical Reel. There is no second posts system.
enum PostKind { post, reel }

/// A verified `@mention`.
///
/// The uid is what identifies the account; the username is only a display
/// snapshot so the text can be rendered without a lookup per mention. A handle
/// that is no longer in [Post.mentions] is never turned into a link, which is
/// what stops a hand-typed `@name` from faking an account.
@immutable
class MentionRef {
  const MentionRef({required this.uid, required this.username});

  final String uid;
  final String username;

  Map<String, dynamic> toMap() => <String, dynamic>{
    'uid': uid,
    'username': username,
  };

  factory MentionRef.fromMap(Object? raw) {
    if (raw is! Map) return const MentionRef(uid: '', username: '');
    return MentionRef(
      uid: raw['uid'] as String? ?? '',
      username: raw['username'] as String? ?? '',
    );
  }
}

/// An anime the post talks about.
///
/// The id is the catalogue id used by the existing details screen; the title and
/// artwork are a display snapshot so a post renders without a catalogue read.
/// Renaming a title later never breaks the link because navigation uses [id].
@immutable
class AnimeRef {
  const AnimeRef({required this.id, required this.title, this.imageUrl = ''});

  final String id;
  final String title;
  final String imageUrl;

  Map<String, dynamic> toMap() => <String, dynamic>{
    'id': id,
    'title': title,
    'imageUrl': imageUrl,
  };

  factory AnimeRef.fromMap(Object? raw) {
    if (raw is! Map) return const AnimeRef(id: '', title: '');
    return AnimeRef(
      id: raw['id'] as String? ?? '',
      title: raw['title'] as String? ?? '',
      imageUrl: raw['imageUrl'] as String? ?? '',
    );
  }
}

/// A community post.
///
/// Documents live in `posts/{postId}`. The author's handle, name, badges and
/// photo version are a display snapshot copied from the unified account, the
/// same way comments already snapshot their writer, so a feed never needs one
/// profile read per post. [UserHandle] replaces the snapshot with the live
/// public mirror as soon as it arrives, so a rename or a badge shows up
/// everywhere without rewriting the post.
@immutable
class Post {
  const Post({
    required this.id,
    required this.authorUid,
    required this.authorUsername,
    required this.authorName,
    required this.text,
    required this.imageKeys,
    required this.createdAt,
    required this.updatedAt,
    this.badges = ProfileBadges.none,
    this.photoVersion = 0,
    this.edited = false,
    this.likeCount = 0,
    this.commentCount = 0,
    this.kind = PostKind.post,
    this.videoKey,
    this.videoThumbnailKey,
    this.videoDurationMs = 0,
    this.videoWidth = 0,
    this.videoHeight = 0,
    this.mentions = const <MentionRef>[],
    this.animeRefs = const <AnimeRef>[],
    this.viewCount = 0,
  });

  final String id;
  final String authorUid;
  final String authorUsername;
  final String authorName;
  final ProfileBadges badges;
  final int photoVersion;

  /// Post body. May be empty when the post is picture-only.
  final String text;

  /// Tigris object keys (`users/{uid}/posts/{postId}/{file}`). The bucket is
  /// private, so a key is not a URL: it is exchanged for a short-lived signed
  /// URL by the media Worker.
  final List<String> imageKeys;

  final DateTime createdAt;
  final DateTime updatedAt;
  final bool edited;
  final int likeCount;
  final int commentCount;

  final PostKind kind;

  /// Tigris object key of the video, or null for a picture/text post.
  final String? videoKey;
  final String? videoThumbnailKey;

  /// Probed on the device before upload; shown as the duration badge and used
  /// by the player skeleton. Never trusted for ranking.
  final int videoDurationMs;
  final int videoWidth;
  final int videoHeight;

  final List<MentionRef> mentions;
  final List<AnimeRef> animeRefs;

  /// Unique viewers, counted from `posts/{id}/views`; not a stored field.
  final int viewCount;

  bool get hasImages => imageKeys.isNotEmpty;

  bool get hasVideo => (videoKey ?? '').isNotEmpty;

  bool get isReel => kind == PostKind.reel;

  /// Ids used by the anime community feed query.
  ///
  /// Deduplicated: mentioning the same anime twice in one post never creates a
  /// second relationship.
  List<String> get animeIds => <String>{
    for (final ref in animeRefs)
      if (ref.id.isNotEmpty) ref.id,
  }.toList(growable: false);

  double? get videoAspectRatio =>
      videoWidth > 0 && videoHeight > 0 ? videoWidth / videoHeight : null;

  Post copyWith({
    String? text,
    List<String>? imageKeys,
    bool? edited,
    int? likeCount,
    int? commentCount,
    DateTime? updatedAt,
    List<MentionRef>? mentions,
    List<AnimeRef>? animeRefs,
    int? viewCount,
  }) => Post(
    id: id,
    authorUid: authorUid,
    authorUsername: authorUsername,
    authorName: authorName,
    badges: badges,
    photoVersion: photoVersion,
    text: text ?? this.text,
    imageKeys: imageKeys ?? this.imageKeys,
    createdAt: createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    edited: edited ?? this.edited,
    likeCount: likeCount ?? this.likeCount,
    commentCount: commentCount ?? this.commentCount,
    kind: kind,
    videoKey: videoKey,
    videoThumbnailKey: videoThumbnailKey,
    videoDurationMs: videoDurationMs,
    videoWidth: videoWidth,
    videoHeight: videoHeight,
    mentions: mentions ?? this.mentions,
    animeRefs: animeRefs ?? this.animeRefs,
    viewCount: viewCount ?? this.viewCount,
  );

  Map<String, dynamic> toMap() => <String, dynamic>{
    'authorUid': authorUid,
    'authorUsername': authorUsername,
    'authorName': authorName,
    'authorBadges': badges.toMap(),
    'photoVersion': photoVersion,
    'text': text,
    'images': imageKeys,
    'edited': edited,
    'likeCount': likeCount,
    'commentCount': commentCount,
    'kind': kind.name,
    if (videoKey != null) 'videoKey': videoKey,
    if (videoThumbnailKey != null) 'videoThumbnailKey': videoThumbnailKey,
    if (videoKey != null) 'videoDurationMs': videoDurationMs,
    if (videoKey != null) 'videoWidth': videoWidth,
    if (videoKey != null) 'videoHeight': videoHeight,
    'mentions': mentions.map((item) => item.toMap()).toList(),
    'animeRefs': animeRefs.map((item) => item.toMap()).toList(),
    'animeIds': animeIds,
    'createdAt': FieldValue.serverTimestamp(),
    'updatedAt': FieldValue.serverTimestamp(),
  };

  factory Post.fromDoc(String id, Map<String, dynamic> raw) {
    DateTime read(Object? value) =>
        value is Timestamp ? value.toDate() : DateTime.now();
    final images = raw['images'];
    return Post(
      id: id,
      authorUid: raw['authorUid'] as String? ?? '',
      authorUsername: raw['authorUsername'] as String? ?? '',
      authorName: raw['authorName'] as String? ?? '',
      badges: ProfileBadges.fromMap(raw['authorBadges']),
      photoVersion: (raw['photoVersion'] as num?)?.toInt() ?? 0,
      text: raw['text'] as String? ?? '',
      imageKeys: images is List
          ? images
                .whereType<String>()
                .where((key) => key.isNotEmpty)
                .toList(growable: false)
          : const <String>[],
      createdAt: read(raw['createdAt']),
      updatedAt: read(raw['updatedAt']),
      edited: raw['edited'] == true,
      likeCount: (raw['likeCount'] as num?)?.toInt().clamp(0, 1 << 31) ?? 0,
      commentCount:
          (raw['commentCount'] as num?)?.toInt().clamp(0, 1 << 31) ?? 0,
      kind: raw['kind'] == 'reel' ? PostKind.reel : PostKind.post,
      videoKey:
          raw['videoKey'] is String && (raw['videoKey'] as String).isNotEmpty
          ? raw['videoKey'] as String
          : null,
      videoThumbnailKey:
          raw['videoThumbnailKey'] is String &&
              (raw['videoThumbnailKey'] as String).isNotEmpty
          ? raw['videoThumbnailKey'] as String
          : null,
      videoDurationMs:
          (raw['videoDurationMs'] as num?)?.toInt().clamp(0, 3600000) ?? 0,
      videoWidth: (raw['videoWidth'] as num?)?.toInt().clamp(0, 10000) ?? 0,
      videoHeight: (raw['videoHeight'] as num?)?.toInt().clamp(0, 10000) ?? 0,
      mentions: raw['mentions'] is List
          ? (raw['mentions'] as List)
                .map(MentionRef.fromMap)
                .where((item) => item.uid.isNotEmpty)
                .toList(growable: false)
          : const <MentionRef>[],
      animeRefs: raw['animeRefs'] is List
          ? (raw['animeRefs'] as List)
                .map(AnimeRef.fromMap)
                .where((item) => item.id.isNotEmpty)
                .toList(growable: false)
          : const <AnimeRef>[],
      viewCount: (raw['viewCount'] as num?)?.toInt().clamp(0, 1 << 31) ?? 0,
    );
  }
}

/// One page of the feed plus the opaque cursor for the next one.
@immutable
class PostPage {
  const PostPage({
    required this.items,
    required this.cursor,
    required this.hasMore,
  });

  static const PostPage empty = PostPage(
    items: <Post>[],
    cursor: null,
    hasMore: false,
  );

  final List<Post> items;
  final DocumentSnapshot<Map<String, dynamic>>? cursor;
  final bool hasMore;
}

/// Public community counters of one account.
///
/// They are never denormalised into a writable field: followers and following
/// are counted from the relationship documents themselves, so no client can
/// set a number by hand.
@immutable
class CommunityCounts {
  const CommunityCounts({
    this.posts = 0,
    this.followers = 0,
    this.following = 0,
  });

  static const CommunityCounts zero = CommunityCounts();

  final int posts;
  final int followers;
  final int following;
}

/// A member shown in a followers / following list.
@immutable
class CommunityMember {
  const CommunityMember({required this.uid, required this.profile});

  final String uid;
  final UserProfile? profile;

  String get username => profile?.username ?? '';
  String get displayName => (profile?.displayName.trim().isNotEmpty ?? false)
      ? profile!.displayName
      : username;
}

/// Reasons offered by the report sheet. Kept in one place so a post, a comment
/// and a profile all report in the same vocabulary.
enum ReportReason {
  spam('spam'),
  harassment('harassment'),
  hate('hate'),
  sexual('sexual'),
  violence('violence'),
  impersonation('impersonation'),
  other('other');

  const ReportReason(this.id);

  final String id;

  String label({required bool arabic}) => switch (this) {
    ReportReason.spam => arabic ? 'محتوى مزعج أو دعائي' : 'Spam or advertising',
    ReportReason.harassment => arabic ? 'تنمّر أو إزعاج' : 'Harassment',
    ReportReason.hate => arabic ? 'خطاب كراهية' : 'Hate speech',
    ReportReason.sexual => arabic ? 'محتوى غير لائق' : 'Inappropriate content',
    ReportReason.violence => arabic ? 'عنف أو تهديد' : 'Violence or threats',
    ReportReason.impersonation => arabic ? 'انتحال شخصية' : 'Impersonation',
    ReportReason.other => arabic ? 'سبب آخر' : 'Something else',
  };
}
