import 'package:flutter/material.dart';

/// The Wings colour system, derived from the official green wing mark.
@immutable
class WingsPalette extends ThemeExtension<WingsPalette> {
  const WingsPalette({
    required this.background,
    required this.surface,
    required this.surfaceAlt,
    required this.surfaceHigh,
    required this.border,
    required this.borderStrong,
    required this.primary,
    required this.primaryBright,
    required this.accent,
    required this.mint,
    required this.onPrimary,
    required this.textPrimary,
    required this.textSecondary,
    required this.textMuted,
    required this.danger,
    required this.warning,
    required this.success,
    required this.overlay,
    required this.skeletonBase,
    required this.skeletonHighlight,
    required this.isDark,
  });

  final Color background;
  final Color surface;
  final Color surfaceAlt;
  final Color surfaceHigh;
  final Color border;
  final Color borderStrong;
  final Color primary;
  final Color primaryBright;
  final Color accent;
  final Color mint;
  final Color onPrimary;
  final Color textPrimary;
  final Color textSecondary;
  final Color textMuted;
  final Color danger;
  final Color warning;
  final Color success;
  final Color overlay;
  final Color skeletonBase;
  final Color skeletonHighlight;
  final bool isDark;

  static const WingsPalette dark = WingsPalette(
    background: Color(0xFF07110C),
    surface: Color(0xFF0D1A13),
    surfaceAlt: Color(0xFF12241A),
    surfaceHigh: Color(0xFF183024),
    border: Color(0xFF1E3A2B),
    borderStrong: Color(0xFF2A5140),
    primary: Color(0xFF20B978),
    primaryBright: Color(0xFF159B62),
    accent: Color(0xFF7BD83B),
    mint: Color(0xFF6DE0A6),
    onPrimary: Color(0xFF04120B),
    textPrimary: Color(0xFFF1FAF5),
    textSecondary: Color(0xFFA9C3B4),
    textMuted: Color(0xFF75907F),
    danger: Color(0xFFF26D6D),
    warning: Color(0xFFF2C14E),
    success: Color(0xFF4CD787),
    overlay: Color(0xCC04100A),
    skeletonBase: Color(0xFF132219),
    skeletonHighlight: Color(0xFF1E382A),
    isDark: true,
  );

  static const WingsPalette light = WingsPalette(
    background: Color(0xFFF5FAF7),
    surface: Color(0xFFFFFFFF),
    surfaceAlt: Color(0xFFEDF6F0),
    surfaceHigh: Color(0xFFE2F1E8),
    border: Color(0xFFDCEBE2),
    borderStrong: Color(0xFFC4DDCE),
    primary: Color(0xFF107F52),
    primaryBright: Color(0xFF159B62),
    accent: Color(0xFF49A81E),
    mint: Color(0xFF2FA46C),
    onPrimary: Color(0xFFFFFFFF),
    textPrimary: Color(0xFF0A1B13),
    textSecondary: Color(0xFF4A6255),
    textMuted: Color(0xFF7A8F83),
    danger: Color(0xFFC44343),
    warning: Color(0xFF9A6B00),
    success: Color(0xFF137A46),
    overlay: Color(0xCC05130D),
    skeletonBase: Color(0xFFE7F1EB),
    skeletonHighlight: Color(0xFFF6FBF8),
    isDark: false,
  );

  /// Brand gradient used for primary actions and selected states.
  LinearGradient get brandGradient => LinearGradient(
    begin: AlignmentDirectional.topStart,
    end: AlignmentDirectional.bottomEnd,
    colors: isDark
        ? const [Color(0xFF2ECC87), Color(0xFF149C63)]
        : const [Color(0xFF159B62), Color(0xFF0A6B43)],
  );

  /// Higher-contrast gradient reserved for the featured banner.
  LinearGradient get accentGradient => const LinearGradient(
    begin: AlignmentDirectional.topStart,
    end: AlignmentDirectional.bottomEnd,
    colors: [Color(0xFF7BD83B), Color(0xFF17A96D), Color(0xFF064B32)],
  );

  LinearGradient get scrimGradient => LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [
      overlay.withValues(alpha: 0.0),
      overlay.withValues(alpha: 0.55),
      overlay,
    ],
    stops: const [0.35, 0.72, 1],
  );

  LinearGradient get skeletonGradient => LinearGradient(
    colors: [skeletonBase, skeletonHighlight, skeletonBase],
    stops: const [0.1, 0.5, 0.9],
  );

  @override
  WingsPalette copyWith({
    Color? background,
    Color? surface,
    Color? surfaceAlt,
    Color? surfaceHigh,
    Color? border,
    Color? borderStrong,
    Color? primary,
    Color? primaryBright,
    Color? accent,
    Color? mint,
    Color? onPrimary,
    Color? textPrimary,
    Color? textSecondary,
    Color? textMuted,
    Color? danger,
    Color? warning,
    Color? success,
    Color? overlay,
    Color? skeletonBase,
    Color? skeletonHighlight,
    bool? isDark,
  }) {
    return WingsPalette(
      background: background ?? this.background,
      surface: surface ?? this.surface,
      surfaceAlt: surfaceAlt ?? this.surfaceAlt,
      surfaceHigh: surfaceHigh ?? this.surfaceHigh,
      border: border ?? this.border,
      borderStrong: borderStrong ?? this.borderStrong,
      primary: primary ?? this.primary,
      primaryBright: primaryBright ?? this.primaryBright,
      accent: accent ?? this.accent,
      mint: mint ?? this.mint,
      onPrimary: onPrimary ?? this.onPrimary,
      textPrimary: textPrimary ?? this.textPrimary,
      textSecondary: textSecondary ?? this.textSecondary,
      textMuted: textMuted ?? this.textMuted,
      danger: danger ?? this.danger,
      warning: warning ?? this.warning,
      success: success ?? this.success,
      overlay: overlay ?? this.overlay,
      skeletonBase: skeletonBase ?? this.skeletonBase,
      skeletonHighlight: skeletonHighlight ?? this.skeletonHighlight,
      isDark: isDark ?? this.isDark,
    );
  }

  @override
  WingsPalette lerp(ThemeExtension<WingsPalette>? other, double t) {
    if (other is! WingsPalette) return this;
    return WingsPalette(
      background: Color.lerp(background, other.background, t)!,
      surface: Color.lerp(surface, other.surface, t)!,
      surfaceAlt: Color.lerp(surfaceAlt, other.surfaceAlt, t)!,
      surfaceHigh: Color.lerp(surfaceHigh, other.surfaceHigh, t)!,
      border: Color.lerp(border, other.border, t)!,
      borderStrong: Color.lerp(borderStrong, other.borderStrong, t)!,
      primary: Color.lerp(primary, other.primary, t)!,
      primaryBright: Color.lerp(primaryBright, other.primaryBright, t)!,
      accent: Color.lerp(accent, other.accent, t)!,
      mint: Color.lerp(mint, other.mint, t)!,
      onPrimary: Color.lerp(onPrimary, other.onPrimary, t)!,
      textPrimary: Color.lerp(textPrimary, other.textPrimary, t)!,
      textSecondary: Color.lerp(textSecondary, other.textSecondary, t)!,
      textMuted: Color.lerp(textMuted, other.textMuted, t)!,
      danger: Color.lerp(danger, other.danger, t)!,
      warning: Color.lerp(warning, other.warning, t)!,
      success: Color.lerp(success, other.success, t)!,
      overlay: Color.lerp(overlay, other.overlay, t)!,
      skeletonBase: Color.lerp(skeletonBase, other.skeletonBase, t)!,
      skeletonHighlight: Color.lerp(
        skeletonHighlight,
        other.skeletonHighlight,
        t,
      )!,
      isDark: t < 0.5 ? isDark : other.isDark,
    );
  }
}
