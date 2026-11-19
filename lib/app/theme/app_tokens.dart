import 'package:flutter/material.dart';

/// Spacing scale. Every gap in the app comes from this scale.
abstract final class Space {
  static const double xxs = 2;
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 20;
  static const double xxl = 24;
  static const double xxxl = 32;
  static const double huge = 40;

  /// Standard horizontal page padding.
  static const EdgeInsets page = EdgeInsets.symmetric(horizontal: lg);
}

abstract final class Radii {
  static const double xs = 8;
  static const double sm = 12;
  static const double md = 16;
  static const double lg = 20;
  static const double xl = 28;
  static const double pill = 999;

  static const BorderRadius card = BorderRadius.all(Radius.circular(sm));
  static const BorderRadius sheet = BorderRadius.vertical(
    top: Radius.circular(xl),
  );
  static const BorderRadius dialog = BorderRadius.all(Radius.circular(lg));
}

/// Motion tokens keep transitions coherent across the app.
abstract final class Motion {
  static const Duration fast = Duration(milliseconds: 140);
  static const Duration normal = Duration(milliseconds: 240);
  static const Duration slow = Duration(milliseconds: 420);
  static const Duration page = Duration(milliseconds: 300);
  static const Duration imageFade = Duration(milliseconds: 220);

  static const Curve standard = Curves.easeOutCubic;
  static const Curve emphasized = Curves.easeOutQuint;
  static const Curve enter = Curves.easeOutCubic;
  static const Curve exit = Curves.easeInCubic;
}

/// Brand colours that are identical in light and dark mode (official badges).
abstract final class BrandColors {
  /// The gold of a verified handle, its seal and its profile frame.
  static const Color gold = Color(0xFFE3B341);

  /// The deep gold used for the second stop of the royal gradient.
  static const Color goldDeep = Color(0xFFB8860B);

  /// The blue mark of a developer account.
  static const Color developerBlue = Color(0xFF2F80ED);

  /// The red handle of a developer account.
  static const Color developerRed = Color(0xFFE5484D);

  /// The royal purple that starts the gradient of an account that is both
  /// verified and a developer.
  static const Color royalPurple = Color(0xFF8B5CF6);

  /// Gold → royal → gold sweep used by the "both badges" handle.
  static const LinearGradient royalGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: <Color>[royalPurple, gold, goldDeep, royalPurple],
    stops: <double>[0, 0.35, 0.65, 1],
  );

  static const Color googleBlue = Color(0xFF4285F4);

  /// The red of a live broadcast pill.
  static const Color live = Color(0xFFE5372B);
}

/// Shared control sizes. A tap target is never smaller than [minTouch].
abstract final class Sizes {
  /// Smallest comfortable Android/iOS target.
  static const double minTouch = 44;

  /// Height of an icon button in a toolbar or a card.
  static const double iconButton = 40;

  /// Height of a standard one-line settings row (before the InkWell padding).
  static const double settingsRow = 56;

  /// Height of a primary/secondary button. Compact actions use [buttonCompact].
  static const double button = 46;
  static const double buttonCompact = 38;

  /// Minimum height of a menu/sheet row.
  static const double sheetRow = 52;
}

/// Poster-card geometry, derived from the artwork ratio so a rail can never
/// clip its titles and a grid cell can never be shorter than its content.
abstract final class PosterCardMetrics {
  /// Width used in every horizontal rail in the app.
  static const double width = 144;

  /// Widest a poster card is allowed to grow inside a grid cell.
  static const double maxWidth = 160;

  /// Gap between the poster and its title.
  static const double imageGap = Space.sm;

  /// Distance between the title and the metadata line.
  static const double titleGap = 3;

  /// Two title lines at the shared `titleSmall` size (13 px, height 1.4).
  static const double titleHeight = 2 * 13 * 1.4;

  /// One metadata line at 11 px.
  static const double metaHeight = 14;

  /// Everything below the poster at the default text scale.
  static const double chrome = imageGap + titleHeight + titleGap + metaHeight;

  /// Space that the title and metadata need at [textScale].
  static double chromeFor(double textScale) =>
      imageGap + (titleHeight + titleGap + metaHeight) * textScale;

  /// Exact card height for a given width — poster is 2:3.
  static double heightFor(double cardWidth, {double textScale = 1}) =>
      cardWidth / Ratios.poster + chromeFor(textScale);

  /// Height of a rail holding [width]-wide cards. Rounded up so the two-line
  /// title and metadata always fit without clipping.
  static double get railHeight => heightFor(width).ceilToDouble() + 2;

  /// Rail height for the reader's current text scale.
  static double railHeightFor(BuildContext context) {
    final scale = MediaQuery.textScalerOf(context).scale(1);
    return heightFor(width, textScale: scale).ceilToDouble() + 2;
  }
}

/// Playback choices shared by the settings screen and the player menus, so the
/// two lists can never drift apart.
abstract final class PlaybackOptions {
  static const List<double> speeds = <double>[0.5, 0.75, 1, 1.25, 1.5, 2];
  static const List<String> qualities = <String>[
    '1080p',
    '720p',
    '480p',
    '360p',
  ];

  /// `1×` for whole values and `1.25×` for fractions.
  static String speedLabel(double speed) =>
      '${speed % 1 == 0 ? speed.toInt() : speed}×';
}

/// Layout breakpoints for responsive lists.
abstract final class Breakpoints {
  static const double compact = 600;
  static const double medium = 900;
  static const double expanded = 1240;
}

/// Aspect ratios used by artwork throughout the app.
abstract final class Ratios {
  static const double poster = 2 / 3;
  static const double backdrop = 16 / 9;
  static const double episodeThumb = 16 / 9;
}
