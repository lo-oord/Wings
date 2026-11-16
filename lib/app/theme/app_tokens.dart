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
