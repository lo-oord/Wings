import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wings/data/models/social.dart';

void main() {
  group('EpisodeComment.fromDoc', () {
    test('maps a full document including the author snapshot', () {
      final comment = EpisodeComment.fromDoc('ep-1', 'c-1', <String, dynamic>{
        'authorUid': 'uid-1',
        'authorUsername': 'shadow_07',
        'authorName': 'Shadow',
        'authorBadges': <String, dynamic>{'verified': true, 'developer': false},
        'photoVersion': 3,
        'text': 'حلقة رائعة',
        'edited': false,
        'deleted': false,
        'replyCount': 2,
        'createdAt': Timestamp.fromDate(DateTime(2026, 3, 1)),
        'updatedAt': Timestamp.fromDate(DateTime(2026, 3, 1)),
      });
      expect(comment.episodeId, 'ep-1');
      expect(comment.id, 'c-1');
      expect(comment.badges.verified, isTrue);
      expect(comment.badges.developer, isFalse);
      expect(comment.replyCount, 2);
      expect(comment.isDeleted, isFalse);
      expect(comment.createdAt.year, 2026);
    });

    test('keeps deleted placeholders readable', () {
      final comment = EpisodeComment.fromDoc('ep-1', 'c-2', <String, dynamic>{
        'text': '',
        'deleted': true,
      });
      expect(comment.isDeleted, isTrue);
      expect(comment.text, isEmpty);
      expect(comment.badges.any, isFalse);
    });

    test('parses replies with their parent id', () {
      final reply = EpisodeComment.fromDoc('ep-1', 'r-1', <String, dynamic>{
        'parentId': 'c-1',
        'authorUid': 'uid-2',
        'text': 'أتفق',
      }, parentId: 'c-1');
      expect(reply.parentId, 'c-1');
      expect(reply.authorUid, 'uid-2');
    });
  });
}
