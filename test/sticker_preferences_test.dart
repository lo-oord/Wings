import 'package:flutter_test/flutter_test.dart';
import 'package:wings/features/stickers/comment_draft.dart';
import 'package:wings/features/stickers/sticker_preferences.dart';

class _MemoryStore implements StickerPreferencesStore {
  final Map<String, Object> values = <String, Object>{};

  @override
  Object? read(String key) => values[key];

  @override
  Future<void> write(String key, Object value) async {
    values[key] = value;
  }
}

void main() {
  group('sticker favourites and recents', () {
    test('a favourite can be added and removed', () async {
      final store = _MemoryStore();
      final preferences = StickerPreferences(store);
      expect(preferences.favorites, isEmpty);

      await preferences.toggleFavorite('om_1f602');
      expect(preferences.favorites, <String>['om_1f602']);

      await preferences.toggleFavorite('cb_laugh');
      expect(preferences.favorites, <String>['om_1f602', 'cb_laugh']);

      await preferences.toggleFavorite('om_1f602');
      expect(preferences.favorites, <String>['cb_laugh']);
    });

    test('recents are unique, newest first and bounded', () async {
      final store = _MemoryStore();
      final preferences = StickerPreferences(store);
      await preferences.markUsed('om_1f602');
      await preferences.markUsed('cb_laugh');
      await preferences.markUsed('om_1f602');
      expect(preferences.recents, <String>['om_1f602', 'cb_laugh']);

      for (var index = 0; index < 20; index++) {
        await preferences.markUsed('om_$index');
      }
      expect(preferences.recents.length, StickerPreferences.recentLimit);
      expect(preferences.recents.first, 'om_19');
      expect(preferences.recents.toSet().length, preferences.recents.length);
    });

    test('stored values never contain artwork or unknown types', () async {
      final store = _MemoryStore();
      store.values[StickerPreferences.recentsKey] = <Object?>[1, null, 'om_x'];
      final preferences = StickerPreferences(store);
      expect(preferences.recents, <String>['om_x']);
    });
  });

  group('comment draft', () {
    test('text only is sendable', () {
      const draft = CommentDraft(text: 'حلقة رائعة');
      expect(draft.canSend, isTrue);
      expect(draft.normalizedStickerId, isNull);
    });

    test('sticker only is sendable', () {
      const draft = CommentDraft(stickerId: 'om_1f602');
      expect(draft.canSend, isTrue);
      expect(draft.hasText, isFalse);
    });

    test('text above a sticker is sendable and keeps both', () {
      const draft = CommentDraft(
        text: '  هذا الملصق مضحك جدًا  ',
        stickerId: 'om_1f602',
      );
      expect(draft.canSend, isTrue);
      expect(draft.trimmedText, 'هذا الملصق مضحك جدًا');
      expect(draft.normalizedStickerId, 'om_1f602');
    });

    test('an empty draft is never sendable', () {
      expect(const CommentDraft().canSend, isFalse);
      expect(const CommentDraft(text: '   ').canSend, isFalse);
      expect(const CommentDraft(stickerId: '  ').canSend, isFalse);
      expect(const CommentDraft(text: '').fits(1000), isTrue);
      expect(CommentDraft(text: 'a' * 1001).fits(1000), isFalse);
    });
  });
}
