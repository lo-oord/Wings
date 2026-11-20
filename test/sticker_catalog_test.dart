import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:wings/data/models/social.dart';
import 'package:wings/data/models/sticker_catalog.dart';

void main() {
  late Map<String, dynamic> manifest;
  late Set<String> assetsOnDisk;
  late StickerCatalog catalog;

  setUpAll(() {
    manifest = jsonDecode(
      File(StickerCatalog.manifestPath).readAsStringSync(),
    ) as Map<String, dynamic>;
    assetsOnDisk = <String>{
      for (final entity in Directory(
        'assets/stickers',
      ).listSync(recursive: true))
        if (entity is File) entity.path.replaceAll(r'\', '/'),
    };
    catalog = StickerCatalog.fromJson(manifest, availableAssets: assetsOnDisk);
  });

  group('bundled sticker manifest', () {
    testWidgets('loads through the asset bundle with no missing files', (
      tester,
    ) async {
      final bundled = await StickerCatalog.load();
      expect(bundled.all.length, catalog.all.length);
      expect(bundled.missingAssets, isEmpty);
      expect(bundled.byId('cb_party'), isNotNull);
    });

    test('every referenced asset exists in the repository', () {
      expect(catalog.missingAssets, isEmpty);
      for (final sticker in catalog.all) {
        expect(
          File(sticker.assetPath).existsSync(),
          isTrue,
          reason: '${sticker.id} points at a missing asset',
        );
      }
    });

    test('sticker ids are unique and stable', () {
      final ids = catalog.all.map((sticker) => sticker.id).toList();
      expect(ids.toSet().length, ids.length);
      // Ids are written to Firestore, so they must never change.
      expect(catalog.byId('om_1f602')?.assetPath, endsWith('om_1f602.webp'));
      expect(catalog.byId('cb_laugh')?.nameEn, 'Cheeky laugh');
    });

    test('both sources are present with their licences', () {
      final openmoji = catalog.all
          .where((sticker) => sticker.source == 'openmoji')
          .toList();
      final chibi = catalog.all
          .where((sticker) => sticker.source == 'wings-original')
          .toList();
      expect(openmoji, isNotEmpty);
      expect(chibi.length, 8);
      expect(
        openmoji.every((sticker) => sticker.license == 'CC BY-SA 4.0'),
        isTrue,
      );
      expect(File('assets/stickers/ATTRIBUTION.md').existsSync(), isTrue);
    });

    test('every sticker belongs to a declared category', () {
      final categoryIds = catalog.categories.map((item) => item.id).toSet();
      for (final sticker in catalog.all) {
        expect(categoryIds, contains(sticker.categoryId));
      }
    });

    test('the picker never offers an empty shelf', () {
      expect(
        catalog.availableCategories.first.id,
        StickerCatalog.allCategoryId,
      );
      for (final category in catalog.availableCategories) {
        expect(catalog.forCategory(category.id), isNotEmpty);
      }
      expect(
        catalog.availableCategories.map((category) => category.id).toSet(),
        containsAll(<String>['expressions', 'laughter', 'sadness', 'chibi']),
      );
    });

    test('search matches names and keywords in both languages', () {
      expect(catalog.search('laugh', arabic: false), isNotEmpty);
      expect(catalog.search('ضحك', arabic: true), isNotEmpty);
      expect(catalog.search('zzzz', arabic: false), isEmpty);
      expect(
        catalog.search('ضحك', arabic: true, categoryId: 'chibi'),
        everyElement(predicate<Sticker>((s) => s.categoryId == 'chibi')),
      );
    });

    test('a disabled or missing asset never enters the catalogue', () {
      final broken = StickerCatalog.fromJson(<String, dynamic>{
        'categories': <dynamic>[
          <String, dynamic>{
            'id': 'all',
            'name': <String, dynamic>{'ar': 'الكل', 'en': 'All'},
          },
        ],
        'stickers': <dynamic>[
          <String, dynamic>{
            'stickerId': 'om_hidden',
            'categoryId': 'all',
            'assetPath': 'assets/stickers/openmoji/om_hidden.webp',
            'displayName': <String, dynamic>{'ar': 'مخفي', 'en': 'Hidden'},
            'enabled': false,
          },
          <String, dynamic>{
            'stickerId': 'om_gone',
            'categoryId': 'all',
            'assetPath': 'assets/stickers/openmoji/om_gone.webp',
            'displayName': <String, dynamic>{'ar': 'مفقود', 'en': 'Gone'},
            'enabled': true,
          },
        ],
      }, availableAssets: <String>{});
      expect(broken.all, isEmpty);
      expect(
        broken.missingAssets,
        contains('assets/stickers/openmoji/om_gone.webp'),
      );
      expect(broken.byId('om_hidden'), isNull);
    });
  });

  group('comment sticker data', () {
    test('legacy documents without a sticker id still parse', () {
      final comment = EpisodeComment.fromDoc('ep-1', 'c-1', <String, dynamic>{
        'authorUid': 'u-1',
        'text': 'تعليق قديم',
      });
      expect(comment.stickerId, isNull);
      expect(comment.text, 'تعليق قديم');
    });

    test('a valid sticker id is kept next to the text', () {
      final comment = EpisodeComment.fromDoc('ep-1', 'c-2', <String, dynamic>{
        'authorUid': 'u-1',
        'text': 'هذا الملصق مضحك جدًا',
        'stickerId': 'om_1f602',
      });
      expect(comment.text, 'هذا الملصق مضحك جدًا');
      expect(comment.stickerId, 'om_1f602');
    });

    test('an unknown or malformed sticker id never throws', () {
      final unknown = EpisodeComment.fromDoc('ep-1', 'c-3', <String, dynamic>{
        'text': '',
        'stickerId': 'om_removed_from_catalogue',
      });
      expect(unknown.stickerId, 'om_removed_from_catalogue');
      expect(unknown.text, isEmpty);

      final malformed = EpisodeComment.fromDoc('ep-1', 'c-4', <String, dynamic>{
        'text': 'نص',
        'stickerId': 42,
      });
      expect(malformed.stickerId, isNull);
      expect(malformed.text, 'نص');
    });
  });
}
