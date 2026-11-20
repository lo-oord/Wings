import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wings/data/models/community.dart';
import 'package:wings/data/models/social.dart';
import 'package:wings/data/models/social_notification.dart';
import 'package:wings/data/models/user_profile.dart';

void main() {
  group('Post', () {
    test('reads a complete document', () {
      final post = Post.fromDoc('p1', <String, dynamic>{
        'authorUid': 'u1',
        'authorUsername': 'wings_user',
        'authorName': 'Wings User',
        'authorBadges': <String, dynamic>{'verified': true, 'developer': false},
        'photoVersion': 3,
        'text': 'مرحبا',
        'images': <Object>['users/u1/posts/p1/a.jpg', 42, ''],
        'likeCount': 12,
        'commentCount': 4,
        'edited': true,
        'createdAt': Timestamp.fromDate(DateTime.utc(2026, 1, 1)),
        'updatedAt': Timestamp.fromDate(DateTime.utc(2026, 1, 2)),
      });

      expect(post.id, 'p1');
      expect(post.authorUid, 'u1');
      expect(post.badges.verified, isTrue);
      expect(post.photoVersion, 3);
      expect(post.imageKeys, <String>['users/u1/posts/p1/a.jpg']);
      expect(post.likeCount, 12);
      expect(post.commentCount, 4);
      expect(post.edited, isTrue);
      expect(post.createdAt.toUtc(), DateTime.utc(2026, 1, 1));
    });

    test('falls back safely on a sparse document', () {
      final post = Post.fromDoc('p2', <String, dynamic>{});

      expect(post.text, '');
      expect(post.imageKeys, isEmpty);
      expect(post.likeCount, 0);
      expect(post.commentCount, 0);
      expect(post.hasImages, isFalse);
      expect(post.badges, ProfileBadges.none);
    });

    test('copyWith keeps the identity and counters it is not given', () {
      final post = Post.fromDoc('p3', <String, dynamic>{
        'authorUid': 'u1',
        'authorUsername': 'wings_user',
        'authorName': 'Wings User',
        'text': 'قديم',
        'likeCount': 2,
        'commentCount': 1,
      });

      final edited = post.copyWith(text: 'جديد', edited: true);

      expect(edited.id, post.id);
      expect(edited.text, 'جديد');
      expect(edited.edited, isTrue);
      expect(edited.likeCount, 2);
      expect(edited.commentCount, 1);
    });
  });

  group('SocialNotification', () {
    SocialNotification build(Map<String, dynamic> data) =>
        SocialNotification.fromDoc('n1', <String, dynamic>{
          'actorUid': 'u2',
          'actorName': 'Actor',
          'actorUsername': 'actor',
          'read': false,
          'createdAt': Timestamp.fromDate(DateTime.utc(2026, 2, 1)),
          ...data,
        });

    test('a post alert opens the post', () {
      final alert = build(<String, dynamic>{'type': 'like', 'postId': 'p1'});

      expect(alert.isCommunity, isTrue);
      expect(alert.route, '/community/post/p1');
    });

    test('a follow alert still routes to the actor profile target', () {
      final alert = build(<String, dynamic>{'type': 'follow', 'postId': ''});

      expect(alert.isCommunity, isFalse);
      expect(alert.route, '/episode//comments');
    });

    test('an official notice keeps its own route', () {
      final alert = build(<String, dynamic>{
        'type': 'admin',
        'route': '/account-status',
        'title': 'تنبيه',
        'body': 'نص',
      });

      expect(alert.isAdmin, isTrue);
      expect(alert.route, '/account-status');
    });
  });

  group('EpisodeComment', () {
    test('carries the target id so post threads reuse the same model', () {
      final comment = EpisodeComment.fromDoc('post-1', 'c1', <String, dynamic>{
        'postId': 'post-1',
        'authorUid': 'u1',
        'authorUsername': 'wings_user',
        'authorName': 'Wings User',
        'text': 'تعليق',
        'replyCount': 2,
        'createdAt': Timestamp.fromDate(DateTime.utc(2026, 3, 1)),
        'updatedAt': Timestamp.fromDate(DateTime.utc(2026, 3, 1)),
      });

      expect(comment.episodeId, 'post-1');
      expect(comment.replyCount, 2);
      expect(comment.isDeleted, isFalse);
      expect(comment.copyWith(text: 'معدل', edited: true).text, 'معدل');
    });
  });
}
