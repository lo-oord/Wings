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
    this.read = false,
    this.badges = ProfileBadges.none,
    this.photoVersion = 0,
    this.episodeNumber,
    this.animeTitle,
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
  final String? episodeNumber;
  final String? animeTitle;
  final DateTime createdAt;
  final bool read;
  final ProfileBadges badges;
  final int photoVersion;

  String get route => '/episode/$episodeId/comments';

  /// Stable tray id so the same alert never buzzes twice.
  int get trayId => 'reply:$id'.hashCode.abs() % 100000;

  SocialNotification copyWith({bool? read}) => SocialNotification(
    id: id,
    type: type,
    actorUid: actorUid,
    actorName: actorName,
    actorUsername: actorUsername,
    text: text,
    episodeId: episodeId,
    commentId: commentId,
    episodeNumber: episodeNumber,
    animeTitle: animeTitle,
    createdAt: createdAt,
    read: read ?? this.read,
    badges: badges,
    photoVersion: photoVersion,
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
      episodeNumber: data['episodeNumber'] as String?,
      animeTitle: data['animeTitle'] as String?,
      createdAt: created is Timestamp
          ? created.toDate()
          : DateTime.fromMillisecondsSinceEpoch(0),
      read: data['read'] == true,
      badges: ProfileBadges.fromMap(data['actorBadges']),
      photoVersion: (data['photoVersion'] as num?)?.toInt() ?? 0,
    );
  }
}
