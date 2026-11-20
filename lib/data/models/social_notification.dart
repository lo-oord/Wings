import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import 'user_profile.dart';

/// An alert produced by another member of the community.
///
/// Documents live in `users/{uid}/notifications`, written by the client that
/// performed the action (the replier, for example) and readable only by the
/// account they belong to. No Cloud Functions are required.
@immutable
class SocialNotification {
  const SocialNotification({
    required this.id,
    required this.type,
    required this.actorUid,
    required this.actorName,
    required this.actorUsername,
    required this.text,
    required this.episodeId,
    required this.commentId,
    required this.createdAt,
    this.postId = '',
    this.read = false,
    this.badges = ProfileBadges.none,
    this.photoVersion = 0,
    this.episodeNumber,
    this.animeTitle,
    this.title = '',
    this.body = '',
    this.kind = '',
    this.targetRoute = '',
  });

  final String id;

  /// `reply` today; the field keeps the door open for `like` or `mention`.
  final String type;
  final String actorUid;
  final String actorName;
  final String actorUsername;
  final String text;
  final String episodeId;
  final String commentId;

  /// Community post an alert points at ('' for episode replies and official
  /// notices). The same notification collection serves both, so the app keeps
  /// one bell, one unread count and one list.
  final String postId;
  final String? episodeNumber;
  final String? animeTitle;

  /// Administrative notification (`type == 'admin'`) fields.
  final String title;
  final String body;
  final String kind;
  final String targetRoute;
  final DateTime createdAt;
  final bool read;
  final ProfileBadges badges;
  final int photoVersion;

  bool get isAdmin => type == 'admin';

  bool get isCommunity => !isAdmin && postId.isNotEmpty;

  String get route {
    if (isAdmin) return targetRoute.isEmpty ? '/account-status' : targetRoute;
    if (postId.isNotEmpty) return '/community/post/$postId';
    return '/episode/$episodeId/comments';
  }

  /// Stable tray id so the same alert never buzzes twice.
  int get trayId => '$type:$id'.hashCode.abs() % 100000;

  SocialNotification copyWith({bool? read}) => SocialNotification(
    id: id,
    type: type,
    actorUid: actorUid,
    actorName: actorName,
    actorUsername: actorUsername,
    text: text,
    episodeId: episodeId,
    commentId: commentId,
    postId: postId,
    episodeNumber: episodeNumber,
    animeTitle: animeTitle,
    createdAt: createdAt,
    read: read ?? this.read,
    badges: badges,
    photoVersion: photoVersion,
    title: title,
    body: body,
    kind: kind,
    targetRoute: targetRoute,
  );

  factory SocialNotification.fromDoc(String id, Map<String, dynamic> data) {
    final created = data['createdAt'];
    return SocialNotification(
      id: id,
      type: data['type'] as String? ?? 'reply',
      actorUid: data['actorUid'] as String? ?? '',
      actorName: data['actorName'] as String? ?? '',
      actorUsername: data['actorUsername'] as String? ?? '',
      text: data['text'] as String? ?? '',
      episodeId: data['episodeId'] as String? ?? '',
      commentId: data['commentId'] as String? ?? '',
      postId: data['postId'] as String? ?? '',
      episodeNumber: data['episodeNumber'] as String?,
      animeTitle: data['animeTitle'] as String?,
      createdAt: created is Timestamp
          ? created.toDate()
          : DateTime.fromMillisecondsSinceEpoch(0),
      read: data['read'] == true,
      badges: ProfileBadges.fromMap(data['actorBadges']),
      photoVersion: (data['photoVersion'] as num?)?.toInt() ?? 0,
      title: data['title'] as String? ?? '',
      body: data['body'] as String? ?? '',
      kind: data['kind'] as String? ?? '',
      targetRoute: data['route'] as String? ?? '',
    );
  }
}
