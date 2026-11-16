import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app_palette.dart';
import 'app_tokens.dart';

const String kFontFamily = 'Cairo';

TextTheme _textTheme(WingsPalette palette) {
  final base = Typography.material2021().black.apply(
    fontFamily: kFontFamily,
    bodyColor: palette.textPrimary,
    displayColor: palette.textPrimary,
  );
  return base.copyWith(
    displaySmall: base.displaySmall?.copyWith(
      fontSize: 30,
      height: 1.2,
      fontWeight: FontWeight.w700,
      letterSpacing: -0.4,
    ),
    headlineMedium: base.headlineMedium?.copyWith(
      fontSize: 24,
      height: 1.25,
      fontWeight: FontWeight.w700,
      letterSpacing: -0.3,
    ),
    headlineSmall: base.headlineSmall?.copyWith(
      fontSize: 20,
      height: 1.3,
      fontWeight: FontWeight.w700,
      letterSpacing: -0.2,
    ),
    titleLarge: base.titleLarge?.copyWith(
      fontSize: 17,
      height: 1.35,
      fontWeight: FontWeight.w600,
    ),
    titleMedium: base.titleMedium?.copyWith(
      fontSize: 15,
      height: 1.4,
      fontWeight: FontWeight.w600,
    ),
    titleSmall: base.titleSmall?.copyWith(
      fontSize: 13,
      height: 1.4,
      fontWeight: FontWeight.w600,
    ),
    bodyLarge: base.bodyLarge?.copyWith(fontSize: 15, height: 1.55),
    bodyMedium: base.bodyMedium?.copyWith(fontSize: 13.5, height: 1.6),
    bodySmall: base.bodySmall?.copyWith(
      fontSize: 12,
      height: 1.5,
      color: palette.textSecondary,
    ),
    labelLarge: base.labelLarge?.copyWith(
      fontSize: 14,
      fontWeight: FontWeight.w600,
      height: 1.2,
    ),
    labelMedium: base.labelMedium?.copyWith(
      fontSize: 12,
      fontWeight: FontWeight.w600,
      letterSpacing: 0.1,
    ),
    labelSmall: base.labelSmall?.copyWith(
      fontSize: 11,
      fontWeight: FontWeight.w600,
      letterSpacing: 0.2,
      color: palette.textMuted,
    ),
  );
}

ThemeData buildWingsTheme(WingsPalette palette) {
  final scheme = ColorScheme(
    brightness: palette.isDark ? Brightness.dark : Brightness.light,
    primary: palette.primary,
    onPrimary: palette.onPrimary,
    primaryContainer: palette.surfaceHigh,
    onPrimaryContainer: palette.textPrimary,
    secondary: palette.accent,
    onSecondary: palette.isDark ? const Color(0xFF0A1F0C) : Colors.white,
    secondaryContainer: palette.surfaceAlt,
    onSecondaryContainer: palette.textPrimary,
    tertiary: palette.mint,
    onTertiary: palette.onPrimary,
    error: palette.danger,
    onError: palette.isDark ? const Color(0xFF2A0909) : Colors.white,
    surface: palette.surface,
    onSurface: palette.textPrimary,
    surfaceContainerHighest: palette.surfaceHigh,
    onSurfaceVariant: palette.textSecondary,
    outline: palette.borderStrong,
    outlineVariant: palette.border,
  );

  final textTheme = _textTheme(palette);

  return ThemeData(
    useMaterial3: true,
    fontFamily: kFontFamily,
    brightness: scheme.brightness,
    colorScheme: scheme,
    scaffoldBackgroundColor: palette.background,
    canvasColor: palette.background,
    splashFactory: InkSparkle.splashFactory,
    textTheme: textTheme,
    extensions: <ThemeExtension<dynamic>>[palette],
    visualDensity: VisualDensity.standard,
    appBarTheme: AppBarTheme(
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: textTheme.titleLarge?.copyWith(fontSize: 19),
      iconTheme: IconThemeData(color: palette.textPrimary, size: 22),
      systemOverlayStyle: palette.isDark
          ? SystemUiOverlayStyle.light
          : SystemUiOverlayStyle.dark,
    ),
    iconTheme: IconThemeData(color: palette.textSecondary, size: 22),
    dividerTheme: DividerThemeData(
      color: palette.border,
      thickness: 1,
      space: 1,
    ),
    cardTheme: CardThemeData(
      color: palette.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: Radii.card),
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(
      color: palette.primary,
      linearTrackColor: palette.surfaceHigh,
      circularTrackColor: palette.surfaceHigh,
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: palette.primary,
        foregroundColor: palette.onPrimary,
        minimumSize: const Size(0, 48),
        padding: const EdgeInsets.symmetric(horizontal: Space.xl),
        textStyle: textTheme.labelLarge,
        shape: const RoundedRectangleBorder(borderRadius: Radii.card),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: palette.textPrimary,
        minimumSize: const Size(0, 48),
        padding: const EdgeInsets.symmetric(horizontal: Space.xl),
        textStyle: textTheme.labelLarge,
        side: BorderSide(color: palette.borderStrong),
        shape: const RoundedRectangleBorder(borderRadius: Radii.card),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: palette.primary,
        textStyle: textTheme.labelLarge,
        padding: const EdgeInsets.symmetric(horizontal: Space.md),
        minimumSize: const Size(0, 40),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: palette.surfaceAlt,
      contentPadding: const EdgeInsets.symmetric(
        horizontal: Space.lg,
        vertical: Space.md + 2,
      ),
      hintStyle: textTheme.bodyMedium?.copyWith(color: palette.textMuted),
      labelStyle: textTheme.bodyMedium?.copyWith(color: palette.textSecondary),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(Radii.sm),
        borderSide: BorderSide(color: palette.border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(Radii.sm),
        borderSide: BorderSide(color: palette.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(Radii.sm),
        borderSide: BorderSide(color: palette.primary, width: 1.5),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(Radii.sm),
        borderSide: BorderSide(color: palette.danger),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(Radii.sm),
        borderSide: BorderSide(color: palette.danger, width: 1.5),
      ),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: palette.surfaceAlt,
      selectedColor: palette.surfaceHigh,
      labelStyle: textTheme.labelMedium!.copyWith(color: palette.textSecondary),
      side: BorderSide(color: palette.border),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Radii.pill),
      ),
      padding: const EdgeInsets.symmetric(
        horizontal: Space.md,
        vertical: Space.xs,
      ),
      showCheckmark: false,
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: palette.surfaceHigh,
      contentTextStyle: textTheme.bodyMedium?.copyWith(
        color: palette.textPrimary,
      ),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Radii.sm),
      ),
      insetPadding: const EdgeInsets.all(Space.lg),
      elevation: 0,
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: palette.surface,
      surfaceTintColor: Colors.transparent,
      modalBackgroundColor: palette.surface,
      shape: const RoundedRectangleBorder(borderRadius: Radii.sheet),
      showDragHandle: false,
      constraints: const BoxConstraints(maxWidth: 640),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: palette.surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: Radii.dialog),
      titleTextStyle: textTheme.titleLarge,
      contentTextStyle: textTheme.bodyMedium?.copyWith(
        color: palette.textSecondary,
      ),
    ),
    sliderTheme: SliderThemeData(
      activeTrackColor: palette.primary,
      inactiveTrackColor: palette.surfaceHigh,
      thumbColor: palette.primary,
      overlayColor: palette.primary.withValues(alpha: 0.12),
      trackHeight: 3,
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected)
            ? palette.onPrimary
            : palette.textMuted,
      ),
      trackColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected)
            ? palette.primary
            : palette.surfaceHigh,
      ),
      trackOutlineColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected)
            ? Colors.transparent
            : palette.border,
      ),
    ),
    tabBarTheme: TabBarThemeData(
      labelColor: palette.textPrimary,
      unselectedLabelColor: palette.textMuted,
      indicatorColor: palette.primary,
      dividerColor: Colors.transparent,
      labelStyle: textTheme.labelLarge,
      unselectedLabelStyle: textTheme.labelMedium,
      indicatorSize: TabBarIndicatorSize.label,
    ),
    pageTransitionsTheme: const PageTransitionsTheme(
      builders: <TargetPlatform, PageTransitionsBuilder>{
        TargetPlatform.android: WingsPageTransitionsBuilder(),
        TargetPlatform.iOS: WingsPageTransitionsBuilder(),
        TargetPlatform.linux: WingsPageTransitionsBuilder(),
        TargetPlatform.macOS: WingsPageTransitionsBuilder(),
        TargetPlatform.windows: WingsPageTransitionsBuilder(),
      },
    ),
  );
}

/// A subtle horizontal fade/slide used for every route in the app.
class WingsPageTransitionsBuilder extends PageTransitionsBuilder {
  const WingsPageTransitionsBuilder();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    final curved = CurvedAnimation(
      parent: animation,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );
    final direction = Directionality.of(context);
    return FadeTransition(
      opacity: curved,
      child: SlideTransition(
        position: Tween<Offset>(
          begin: Offset(direction == TextDirection.rtl ? -0.04 : 0.04, 0),
          end: Offset.zero,
        ).animate(curved),
        child: child,
      ),
    );
  }
}
