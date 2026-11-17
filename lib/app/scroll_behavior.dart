import 'package:flutter/material.dart';

/// Keeps scrolling calm: no stretch and no glow when a list reaches its end.
///
/// The default Material behaviour on Android stretches the whole scroll view
/// while the finger pulls past the edge and springs it back on release, which
/// looks like the page itself is being deformed. This behaviour draws nothing
/// past the edge and clamps the content instead.
class WingsScrollBehavior extends MaterialScrollBehavior {
  const WingsScrollBehavior();

  @override
  Widget buildOverscrollIndicator(
    BuildContext context,
    Widget child,
    ScrollableDetails details,
  ) => child;

  @override
  ScrollPhysics getScrollPhysics(BuildContext context) =>
      const ClampingScrollPhysics();
}
