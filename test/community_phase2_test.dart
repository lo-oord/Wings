import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wings/data/models/community.dart';
import 'package:wings/features/community/suggestion_panel.dart';

void main() {
  group('unified post model', () {
    test('a phase one document still parses as a plain post', () {
      final post = Post.fromDoc('p1', <String, dynamic>{
        'authorUid': 'u1',
        'authorUsername': 'lord',
        'authorName': 'Lord',
        'text': 'hello',
        'images': <String>['k1'],
        'createdAt': DateTime(2026),
        'updatedAt': DateTime(2026),
      });
      expect(post.kind, PostKind.post);
      expect(post.hasVideo, isFalse);
      expect(post.isReel, isFalse);
      expect(post.mentions, isEmpty);
      expect(post.animeRefs, isEmpty);
      expect(post.imageKeys, <String>['k1']);
    });

    test('a reel keeps its video metadata and references', () {
      final post = Post.fromDoc('p2', <String, dynamic>{
        'authorUid': 'u1',
        'authorUsername': 'lord',
        'authorName': 'Lord',
        'text': 'watch #Naruto @lord',
        'images': <String>[],
        'kind': 'reel',
        'videoKey': 'users/u1/posts/p2/v.mp4',
        'videoThumbnailKey': 'users/u1/posts/p2/c.jpg',
        'videoDurationMs': 14000,
        'videoWidth': 1080,
        'videoHeight': 1920,
        'mentions': <Map<String, dynamic>>[
          <String, dynamic>{'uid': 'u9', 'username': 'sakura'},
        ],
        'animeRefs': <Map<String, dynamic>>[
          <String, dynamic>{'id': 'naruto', 'title': 'Naruto'},
        ],
        'createdAt': DateTime(2026),
        'updatedAt': DateTime(2026),
      });
      expect(post.isReel, isTrue);
      expect(post.hasVideo, isTrue);
      expect(post.videoDurationMs, 14000);
      expect(post.videoAspectRatio, 1080 / 1920);
      expect(post.mentions.single.uid, 'u9');
      expect(post.animeIds, <String>['naruto']);
    });

    test('writing a post stores the anime ids used by the feed query', () {
      final post = Post(
        id: 'p3',
        authorUid: 'u1',
        authorUsername: 'lord',
        authorName: 'Lord',
        text: 'hi',
        imageKeys: const <String>[],
        createdAt: DateTime(2026),
        updatedAt: DateTime(2026),
        animeRefs: const <AnimeRef>[
          AnimeRef(id: 'a1', title: 'One'),
          AnimeRef(id: 'a2', title: 'Two'),
          AnimeRef(id: 'a1', title: 'One again'),
        ],
      );
      final map = post.toMap();
      expect(map['kind'], 'post');
      // The duplicate reference never becomes a duplicate relationship.
      expect(map['animeIds'], <String>['a1', 'a2']);
      expect(map['mentions'], isEmpty);
    });

    test('an empty mention is dropped instead of creating a fake account', () {
      final post = Post.fromDoc('p4', <String, dynamic>{
        'authorUid': 'u1',
        'text': 'hi @nobody',
        'mentions': <Map<String, dynamic>>[
          <String, dynamic>{'uid': '', 'username': 'nobody'},
          <String, dynamic>{'uid': 'u7', 'username': 'real'},
        ],
      });
      expect(post.mentions.length, 1);
      expect(post.mentions.single.uid, 'u7');
    });
  });

  group('composer triggers', () {
    TextEditingController controllerWith(String text) {
      final controller = TextEditingController(text: text);
      controller.selection = TextSelection.collapsed(offset: text.length);
      return controller;
    }

    test('@handle opens a mention picker with the typed prefix', () {
      final controller = controllerWith('hello @lor');
      final trigger = detectTrigger(controller);
      expect(trigger, isNotNull);
      expect(trigger!.kind, SuggestionKind.mention);
      expect(trigger.query, 'lor');
      controller.dispose();
    });

    test('#title opens the anime picker and allows spaces', () {
      final controller = controllerWith('watching #one pie');
      final trigger = detectTrigger(controller);
      expect(trigger, isNotNull);
      expect(trigger!.kind, SuggestionKind.anime);
      expect(trigger.query, 'one pie');
      controller.dispose();
    });

    test('a closed mention or a new line does not reopen the picker', () {
      final closed = controllerWith('hello @lord how are you');
      expect(detectTrigger(closed), isNull);
      final newline = controllerWith('line one\nhello');
      expect(detectTrigger(newline), isNull);
      closed.dispose();
      newline.dispose();
    });

    test(
      'picking a suggestion replaces the trigger and keeps the caret after',
      () {
        final controller = controllerWith('hello @lor world');
        controller.selection = const TextSelection.collapsed(offset: 10);
        final trigger = detectTrigger(controller)!;
        applySuggestion(controller, trigger, '@lord');
        expect(controller.text, 'hello @lord world');
        // The caret sits right after the handle, before the space that was
        // already in the text, so the member keeps typing in the same sentence.
        expect(controller.selection.baseOffset, 'hello @lord'.length);
        controller.dispose();
      },
    );

    test('picking an anime keeps one hashtag for a title with spaces', () {
      final controller = controllerWith('see #one');
      final trigger = detectTrigger(controller)!;
      applySuggestion(controller, trigger, '#One Piece');
      expect(controller.text, 'see #One Piece ');
      controller.dispose();
    });
  });
}
