import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wings/app/theme/app_palette.dart';
import 'package:wings/app/theme/app_theme.dart';
import 'package:wings/data/models/sticker_catalog.dart';
import 'package:wings/features/social/comment_composer.dart';
import 'package:wings/features/stickers/sticker_preferences.dart';
import 'package:wings/features/stickers/sticker_providers.dart';

class _MemoryStore implements StickerPreferencesStore {
  final Map<String, Object> values = <String, Object>{};

  @override
  Object? read(String key) => values[key];

  @override
  Future<void> write(String key, Object value) async {
    values[key] = value;
  }
}

StickerCatalog _catalog() => StickerCatalog.fromJson(<String, dynamic>{
  'categories': <dynamic>[
    <String, dynamic>{
      'id': 'all',
      'name': <String, dynamic>{'ar': 'الكل', 'en': 'All'},
      'sortOrder': 0,
    },
    <String, dynamic>{
      'id': 'chibi',
      'name': <String, dynamic>{'ar': 'Chibi', 'en': 'Chibi'},
      'sortOrder': 1,
    },
  ],
  'stickers': <dynamic>[
    <String, dynamic>{
      'stickerId': 'cb_laugh',
      'categoryId': 'chibi',
      'assetPath': 'assets/stickers/chibi/cb_laugh.webp',
      'displayName': <String, dynamic>{
        'ar': 'ضحكة شقيّة',
        'en': 'Cheeky laugh',
      },
      'sortOrder': 10,
      'enabled': true,
    },
  ],
});

void main() {
  late TextEditingController controller;
  late List<(String, String?)> sent;

  Future<void> pumpComposer(
    WidgetTester tester, {
    Future<bool> Function(String text, String? stickerId)? onSend,
  }) async {
    controller = TextEditingController();
    sent = <(String, String?)>[];
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          stickerCatalogProvider.overrideWith((ref) => _catalog()),
          stickerPreferencesProvider.overrideWithValue(
            StickerPreferences(_MemoryStore()),
          ),
        ],
        child: MaterialApp(
          theme: buildWingsTheme(WingsPalette.dark),
          home: Scaffold(
            body: CommentComposer(
              controller: controller,
              sending: false,
              onSend: (text, stickerId, mentions, animeRefs) async {
                sent.add((text, stickerId));
                if (onSend != null) return onSend(text, stickerId);
                return true;
              },
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('sends a sticker on its own', (tester) async {
    await pumpComposer(tester);
    await tester.tap(find.byTooltip('Stickers'));
    await tester.pumpAndSettle();
    expect(find.text('Stickers'), findsOneWidget);

    await tester.tap(
      find.byKey(const ValueKey<String>('sticker_cell_cb_laugh')),
    );
    await tester.pumpAndSettle();
    expect(controller.text, isEmpty);
    expect(find.byTooltip('Remove sticker'), findsOneWidget);

    await tester.tap(find.byTooltip('Send'));
    await tester.pumpAndSettle();
    expect(sent, <(String, String?)>[('', 'cb_laugh')]);
    expect(find.byTooltip('Remove sticker'), findsNothing);
  });

  testWidgets('sends text above a sticker', (tester) async {
    await pumpComposer(tester);
    await tester.enterText(find.byType(TextField), 'هذا الملصق مضحك جدًا');
    await tester.tap(find.byTooltip('Stickers'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey<String>('sticker_cell_cb_laugh')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Send'));
    await tester.pumpAndSettle();
    expect(sent, <(String, String?)>[('هذا الملصق مضحك جدًا', 'cb_laugh')]);
    expect(controller.text, isEmpty);
  });

  testWidgets('opening and closing the picker keeps the draft', (tester) async {
    await pumpComposer(tester);
    await tester.enterText(find.byType(TextField), 'نص لم يُرسل بعد');
    await tester.tap(find.byTooltip('Stickers'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Close'));
    await tester.pumpAndSettle();
    expect(controller.text, 'نص لم يُرسل بعد');
    expect(find.byTooltip('Remove sticker'), findsNothing);
  });

  testWidgets('a sticker can be removed before sending', (tester) async {
    await pumpComposer(tester);
    await tester.tap(find.byTooltip('Stickers'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey<String>('sticker_cell_cb_laugh')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Remove sticker'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Send'));
    await tester.pumpAndSettle();
    expect(sent, isEmpty);
  });

  testWidgets('a pending send is never posted twice', (tester) async {
    final pending = Completer<bool>();
    await pumpComposer(tester, onSend: (text, stickerId) => pending.future);
    await tester.enterText(find.byType(TextField), 'مرة واحدة');
    await tester.tap(find.byTooltip('Send'));
    await tester.pump();
    await tester.tap(find.byTooltip('Send'));
    await tester.pump();
    expect(sent.length, 1);
    pending.complete(true);
    await tester.pumpAndSettle();
    expect(sent.length, 1);
    expect(controller.text, isEmpty);
  });
}
