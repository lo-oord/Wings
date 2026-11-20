import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import 'user_profile.dart';

enum ReactionType { like, dislike }

@immutable
class EpisodeCounts {
  const EpisodeCounts({this.likes = 0, this.dislikes = 0, this.comments = 0});

  static const EpisodeCounts zero = EpisodeCounts();

  final int likes;
  final int dislikes;
  final int comments;
}

/// One root comment, or one reply.
///
/// The same document shape serves an episode thread and a community post
/// thread: [episodeId] carries the target id (an episode id, or a post id), so
/// Wings keeps a single comment system rather than a second one for posts.
/// Replies live in `comments/{commentId}/replies`.
@immutable
class EpisodeComment {
  const EpisodeComment({
    required this.id,
    required this.episodeId,
    required this.authorUid,
    required this.authorUsername,
    required this.authorName,
    required this.text,
    this.stickerId,
    required this.createdAt,
    required this.updatedAt,
    this.parentId,
    this.badges = ProfileBadges.none,
    this.photoVersion = 0,
    this.edited = false,
    this.deleted = false,
    this.replyCount = 0,
  });

  final String id;
  final String episodeId;
  final String? parentId;
  final String authorUid;
  final String authorUsername;
  final String authorName;
  final ProfileBadges badges;
  final int photoVersion;
  final String text;

  /// Id of a bundled sticker shown under the text, or null for a text-only
  /// comment. Only the id is stored; the artwork ships inside the app.
  final String? stickerId;

  final bool edited;
  final bool deleted;
  final int replyCount;
  final DateTime createdAt;
  final DateTime updatedAt;

  bool get isDeleted => deleted;

  factory EpisodeComment.fromDoc(
    String episodeId,
    String id,
    Map<String, dynamic> raw, {
    String? parentId,
  }) {
    DateTime read(Object? value) =>
        value is Timestamp ? value.toDate() : DateTime.now();
    return EpisodeComment(
      id: id,
      episodeId: episodeId,
      parentId: parentId ?? raw['parentId'] as String?,
      authorUid: raw['authorUid'] as String? ?? '',
      authorUsername: raw['authorUsername'] as String? ?? '',
      authorName: raw['authorName'] as String? ?? '',
      badges: ProfileBadges.fromMap(raw['authorBadges']),
      photoVersion: (raw['photoVersion'] as num?)?.toInt() ?? 0,
      text: raw['text'] as String? ?? '',
      stickerId:
          raw['stickerId'] is String && (raw['stickerId'] as String).isNotEmpty
          ? raw['stickerId'] as String
          : null,
      edited: raw['edited'] == true,
      deleted: raw['deleted'] == true,
      replyCount: (raw['replyCount'] as num?)?.toInt() ?? 0,
      createdAt: read(raw['createdAt']),
      updatedAt: read(raw['updatedAt']),
    );
  }

  EpisodeComment copyWith({
    bool? deleted,
    int? replyCount,
    String? text,
    bool? edited,
  }) => EpisodeComment(
    id: id,
    episodeId: episodeId,
    parentId: parentId,
    authorUid: authorUid,
    authorUsername: authorUsername,
    authorName: authorName,
    badges: badges,
    photoVersion: photoVersion,
    text: text ?? this.text,
    stickerId: stickerId,
    edited: edited ?? this.edited,
    deleted: deleted ?? this.deleted,
    replyCount: replyCount ?? this.replyCount,
    createdAt: createdAt,
    updatedAt: updatedAt,
  );
}

@immutable
class CommentPage {
  const CommentPage({
    required this.items,
    required this.cursor,
    required this.hasMore,
  });

  static const CommentPage empty = CommentPage(
    items: <EpisodeComment>[],
    cursor: null,
    hasMore: false,
  );

  final List<EpisodeComment> items;

  /// Firestore cursor for the next page; opaque to the UI.
  final DocumentSnapshot<Map<String, dynamic>>? cursor;

  final bool hasMore;
}
