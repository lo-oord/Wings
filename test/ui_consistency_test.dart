import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:wings/app/theme/app_palette.dart';
import 'package:wings/app/theme/app_theme.dart';
import 'package:wings/app/theme/app_tokens.dart';
import 'package:wings/core/widgets/wings_cards.dart';
import 'package:wings/core/widgets/wings_layout.dart';

void main() {
  group('poster card geometry', () {
    test('a cell always has room for the poster, two title lines and meta', () {
      for (final scale in <double>[0.9, 1, 1.15, 1.3]) {
        final height = PosterCardMetrics.heightFor(
          PosterCardMetrics.width,
          textScale: scale,
        );
        final smallestContent =
            PosterCardMetrics.width / Ratios.poster +
            2 * 13 * 1.4 * scale +
            PosterCardMetrics.metaHeight * scale;
        expect(height, greaterThanOrEqualTo(smallestContent));
      }
    });

    test('the rail height matches a full-width card', () {
      expect(
        PosterCardMetrics.railHeight,
        greaterThanOrEqualTo(
          PosterCardMetrics.heightFor(PosterCardMetrics.width),
        ),
      );
    });

    test('grid columns adapt to the available width but stay bounded', () {
      expect(AnimeGrid.columnsFor(320), 2);
      expect(AnimeGrid.columnsFor(768), 5);
      expect(AnimeGrid.columnsFor(2400), 8);
    });
  });

  test('playback speed labels stay consistent between settings and player', () {
    expect(PlaybackOptions.speedLabel(1), '1×');
    expect(PlaybackOptions.speedLabel(1.25), '1.25×');
    expect(PlaybackOptions.speeds.first, 0.5);
  });

  testWidgets('settings rows keep a stable minimum height', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildWingsTheme(WingsPalette.dark),
        home: Scaffold(
          body: Column(
            children: <Widget>[
              const WingsSettingsTile(
                icon: Icons.settings_outlined,
                title: 'Theme',
                subtitle: 'Dark',
                showChevron: true,
              ),
              WingsSettingsTile(
                icon: Icons.notifications_outlined,
                title: 'New episodes',
                trailing: Switch(value: true, onChanged: (_) {}),
              ),
            ],
          ),
        ),
      ),
    );

    final tiles = find.byType(WingsSettingsTile);
    expect(tiles, findsNWidgets(2));
    expect(
      tester.getSize(tiles.at(0)).height,
      greaterThanOrEqualTo(Sizes.settingsRow),
    );
    expect(
      tester.getSize(tiles.at(1)).height,
      greaterThanOrEqualTo(Sizes.settingsRow),
    );
  });
}
