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

/// A reference to one episode of the catalogue, stored on a community post
/// that shares an episode.
///
/// Only the ids are authoritative: the titles, the number and the cover keys
/// are a display snapshot, and the player resolves the streams from the real
/// episode at play time. The video itself is never copied into the post.
@immutable
class EpisodeRef {
  const EpisodeRef({
    required this.animeId,
    required this.episodeId,
    this.animeTitle = '',
    this.episodeTitle = '',
    this.episodeNumber = 0,
    this.coverKey = '',
    this.animeCoverKey = '',
    this.coverUrl = '',
    this.season = 0,
    this.durationMs = 0,
  });

  final String animeId;
  final String episodeId;
  final String animeTitle;
  final String episodeTitle;
  final int episodeNumber;
  final String coverKey;
  final String animeCoverKey;

  /// Public cover URL captured at share time. The post stays readable even when
  /// the catalogue is unreachable or the title was removed.
  final String coverUrl;
  final int season;
  final int durationMs;

  bool get isNotEmpty => animeId.isNotEmpty && episodeId.isNotEmpty;

  String get displayTitle => episodeTitle.trim().isNotEmpty
      ? episodeTitle.trim()
      : '${animeTitle.trim()} · ${episodeNumber > 0 ? episodeNumber : 1}';

  Map<String, dynamic> toMap() => <String, dynamic>{
    'animeId': animeId,
    'episodeId': episodeId,
    if (animeTitle.isNotEmpty) 'animeTitle': animeTitle,
    if (episodeTitle.isNotEmpty) 'episodeTitle': episodeTitle,
    'episodeNumber': episodeNumber,
    if (coverKey.isNotEmpty) 'coverKey': coverKey,
    if (animeCoverKey.isNotEmpty) 'animeCoverKey': animeCoverKey,
    if (coverUrl.isNotEmpty) 'coverUrl': coverUrl,
    if (season > 0) 'season': season,
    if (durationMs > 0) 'durationMs': durationMs,
  };

  factory EpisodeRef.fromMap(Object? raw) {
    if (raw is! Map) {
      return const EpisodeRef(animeId: '', episodeId: '');
    }
    return EpisodeRef(
      animeId: raw['animeId'] as String? ?? '',
      episodeId: raw['episodeId'] as String? ?? '',
      animeTitle: raw['animeTitle'] as String? ?? '',
      episodeTitle: raw['episodeTitle'] as String? ?? '',
      episodeNumber: (raw['episodeNumber'] as num?)?.toInt() ?? 0,
      coverKey: raw['coverKey'] as String? ?? '',
      animeCoverKey: raw['animeCoverKey'] as String? ?? '',
      coverUrl: raw['coverUrl'] as String? ?? '',
      season: (raw['season'] as num?)?.toInt() ?? 0,
      durationMs: (raw['durationMs'] as num?)?.toInt() ?? 0,
    );
  }
}

/// One picture of a picture Reel and how long it stays on screen.
///
/// A Reel made of pictures has no video object at all: the frames are the same
/// private Tigris keys a picture post uses, played as a timed slideshow in the
/// community player.
@immutable
class ReelFrame {
  const ReelFrame({required this.key, this.durationMs = 2500});

  final String key;
  final int durationMs;

  Map<String, dynamic> toMap() => <String, dynamic>{
    'key': key,
    'durationMs': durationMs,
  };

  factory ReelFrame.fromMap(Object? raw) {
    if (raw is! Map) return const ReelFrame(key: '');
    return ReelFrame(
      key: raw['key'] as String? ?? '',
      durationMs:
          (raw['durationMs'] as num?)?.toInt().clamp(500, 15000) ?? 2500,
    );
  }
}

/// A public hashtag of the community.
///
/// Anime hashtags are `animeRefs` on the post; a hashtag in this collection is
/// a free topic. The creator of the first post that used it is kept forever,
/// and the usage counter is the only field another member may move.
@immutable
class HashtagInfo {
  const HashtagInfo({
    required this.slug,
    required this.name,
    required this.creatorUid,
    required this.creatorUsername,
    this.usageCount = 0,
  });

  final String slug;
  final String name;
  final String creatorUid;
  final String creatorUsername;
  final int usageCount;

  factory HashtagInfo.fromDoc(String slug, Map<String, dynamic> raw) =>
      HashtagInfo(
        slug: slug,
        name: raw['name'] as String? ?? slug,
        creatorUid: raw['creatorUid'] as String? ?? '',
        creatorUsername: raw['creatorUsername'] as String? ?? '',
        usageCount: (raw['usageCount'] as num?)?.toInt() ?? 0,
      );
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
    this.allowComments = true,
    this.allowDownload = true,
    this.allowRepost = true,
    this.category = '',
    this.soundTitle = '',
    this.repostedFrom = '',
    this.pinned = false,
    this.hashtags = const <String>[],
    this.episodeRef,
    this.reelFrames = const <ReelFrame>[],
    this.soundKey = '',
    this.soundAuthorUid = '',
    this.soundUsageCount = 0,
    this.videoBytes = 0,
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

  /// Per-post publishing choices. The defaults are permissive so every post
  /// written before these settings existed keeps behaving exactly as before.
  final bool allowComments;
  final bool allowDownload;
  final bool allowRepost;

  /// Optional topic picked in the composer (discussion, question, news…).
  final String category;

  /// Optional sound/music label shown under a Reel.
  final String soundTitle;

  /// Id of the original post when this one is a repost.
  final String repostedFrom;

  /// Set by the Owner (any post) or by staff. A pinned post is shown first in
  /// every community feed.
  final bool pinned;

  /// Free hashtags written by the author, normalized and without `#`.
  /// Anime titles are not here: they live in [animeRefs] so a tag always opens
  /// the right catalogue page.
  final List<String> hashtags;

  /// The catalogue episode this post shares, when it is an episode share.
  final EpisodeRef? episodeRef;

  /// Pictures of a picture Reel, in order, with their own duration.
  final List<ReelFrame> reelFrames;

  /// Object key of the sound/music used by a Reel, and the account that first
  /// published it so «استخدام هذا الصوت» can credit the original creator.
  final String soundKey;
  final String soundAuthorUid;
  final int soundUsageCount;

  /// Uploaded size of the video, checked by the rules against the per-kind
  /// ceiling (a community video and a Reel have different limits).
  final int videoBytes;

  bool get hasImages => imageKeys.isNotEmpty;

  bool get hasVideo => (videoKey ?? '').isNotEmpty;

  bool get isReel => kind == PostKind.reel;

  bool get hasSlides => reelFrames.isNotEmpty;

  bool get isPlayable => hasVideo || hasSlides;

  bool get hasEpisode => episodeRef?.isNotEmpty ?? false;

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
    bool? allowComments,
    bool? allowDownload,
    bool? allowRepost,
    String? category,
    String? soundTitle,
    String? repostedFrom,
    bool? pinned,
    List<String>? hashtags,
    EpisodeRef? episodeRef,
    List<ReelFrame>? reelFrames,
    String? soundKey,
    String? soundAuthorUid,
    int? soundUsageCount,
    int? videoBytes,
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
    allowComments: allowComments ?? this.allowComments,
    allowDownload: allowDownload ?? this.allowDownload,
    allowRepost: allowRepost ?? this.allowRepost,
    category: category ?? this.category,
    soundTitle: soundTitle ?? this.soundTitle,
    repostedFrom: repostedFrom ?? this.repostedFrom,
    pinned: pinned ?? this.pinned,
    hashtags: hashtags ?? this.hashtags,
    episodeRef: episodeRef ?? this.episodeRef,
    reelFrames: reelFrames ?? this.reelFrames,
    soundKey: soundKey ?? this.soundKey,
    soundAuthorUid: soundAuthorUid ?? this.soundAuthorUid,
    soundUsageCount: soundUsageCount ?? this.soundUsageCount,
    videoBytes: videoBytes ?? this.videoBytes,
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
    'allowComments': allowComments,
    'allowDownload': allowDownload,
    'allowRepost': allowRepost,
    if (category.isNotEmpty) 'category': category,
    if (soundTitle.isNotEmpty) 'soundTitle': soundTitle,
    if (repostedFrom.isNotEmpty) 'repostedFrom': repostedFrom,
    'pinned': pinned,
    if (hashtags.isNotEmpty) 'hashtags': hashtags,
    if (episodeRef != null && episodeRef!.isNotEmpty)
      'episodeRef': episodeRef!.toMap(),
    if (reelFrames.isNotEmpty)
      'reelFrames': reelFrames.map((frame) => frame.toMap()).toList(),
    if (soundKey.isNotEmpty) 'soundKey': soundKey,
    if (soundAuthorUid.isNotEmpty) 'soundAuthorUid': soundAuthorUid,
    if (soundUsageCount > 0) 'soundUsageCount': soundUsageCount,
    'videoBytes': videoBytes,
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
      allowComments: raw['allowComments'] != false,
      allowDownload: raw['allowDownload'] != false,
      allowRepost: raw['allowRepost'] != false,
      category: raw['category'] as String? ?? '',
      soundTitle: raw['soundTitle'] as String? ?? '',
      repostedFrom: raw['repostedFrom'] as String? ?? '',
      pinned: raw['pinned'] == true,
      hashtags: raw['hashtags'] is List
          ? (raw['hashtags'] as List)
                .whereType<String>()
                .where((tag) => tag.isNotEmpty)
                .take(10)
                .toList(growable: false)
          : const <String>[],
      episodeRef: raw['episodeRef'] is Map
          ? EpisodeRef.fromMap(raw['episodeRef'])
          : null,
      reelFrames: raw['reelFrames'] is List
          ? (raw['reelFrames'] as List)
                .map(ReelFrame.fromMap)
                .where((frame) => frame.key.isNotEmpty)
                .take(10)
                .toList(growable: false)
          : const <ReelFrame>[],
      soundKey: raw['soundKey'] as String? ?? '',
      soundAuthorUid: raw['soundAuthorUid'] as String? ?? '',
      soundUsageCount: (raw['soundUsageCount'] as num?)?.toInt() ?? 0,
      videoBytes: (raw['videoBytes'] as num?)?.toInt() ?? 0,
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
