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
