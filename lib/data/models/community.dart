import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import 'user_profile.dart';

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

  bool get hasImages => imageKeys.isNotEmpty;

  Post copyWith({
    String? text,
    List<String>? imageKeys,
    bool? edited,
    int? likeCount,
    int? commentCount,
    DateTime? updatedAt,
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
