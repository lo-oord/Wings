import 'package:flutter/material.dart';

import '../../app/theme/app_tokens.dart';
import '../../app/theme/context_ext.dart';
import 'wings_motion.dart';

enum WingsButtonVariant { primary, tonal, outline, ghost }

class WingsButton extends StatelessWidget {
  const WingsButton({
    super.key,
    required this.label,
    this.onPressed,
    this.icon,
    this.variant = WingsButtonVariant.primary,
    this.expand = false,
    this.loading = false,
    this.height = 46,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final WingsButtonVariant variant;
  final bool expand;
  final bool loading;
  final double height;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final enabled = onPressed != null && !loading;

    final foreground = switch (variant) {
      WingsButtonVariant.primary => palette.onPrimary,
      WingsButtonVariant.tonal => palette.textPrimary,
      WingsButtonVariant.outline => palette.textPrimary,
      WingsButtonVariant.ghost => palette.primary,
    };

    final decoration = switch (variant) {
      WingsButtonVariant.primary => BoxDecoration(
        gradient: palette.brandGradient,
        borderRadius: BorderRadius.circular(Radii.sm),
      ),
      WingsButtonVariant.tonal => BoxDecoration(
        color: palette.surfaceHigh,
        borderRadius: BorderRadius.circular(Radii.sm),
      ),
      WingsButtonVariant.outline => BoxDecoration(
        borderRadius: BorderRadius.circular(Radii.sm),
        border: Border.all(color: palette.borderStrong),
      ),
      WingsButtonVariant.ghost => null,
    };

    final content = Row(
      mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: <Widget>[
        if (loading)
          SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(strokeWidth: 2, color: foreground),
          )
        else if (icon != null)
          Icon(icon, size: 18, color: foreground),
        if (loading || icon != null) const SizedBox(width: Space.sm),
        Flexible(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: context.text.labelLarge?.copyWith(color: foreground),
          ),
        ),
      ],
    );

    final button = Opacity(
      opacity: enabled ? 1 : 0.55,
      child: AnimatedContainer(
        duration: Motion.fast,
        curve: Motion.standard,
        height: height,
        padding: const EdgeInsets.symmetric(horizontal: Space.lg),
        decoration: decoration,
        alignment: Alignment.center,
        child: content,
      ),
    );

    return Semantics(
      button: true,
      enabled: enabled,
      label: label,
      child: WingsPressable(
        borderRadius: BorderRadius.circular(Radii.sm),
        haptic: variant != WingsButtonVariant.ghost,
        onTap: enabled ? onPressed : null,
        child: SizedBox(width: expand ? double.infinity : null, child: button),
      ),
    );
  }
}

class WingsIconButton extends StatelessWidget {
  const WingsIconButton({
    super.key,
    required this.icon,
    this.onPressed,
    this.size = 40,
    this.tooltip,
    this.filled = false,
    this.color,
  });

  final IconData icon;
  final VoidCallback? onPressed;
  final double size;
  final String? tooltip;
  final bool filled;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final button = WingsPressable(
      borderRadius: BorderRadius.circular(Radii.pill),
      haptic: false,
      onTap: onPressed,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: filled ? palette.surfaceHigh : Colors.transparent,
          shape: BoxShape.circle,
        ),
        child: Icon(
          icon,
          size: size * 0.52,
          color: onPressed == null
              ? palette.textMuted
              : (color ?? palette.textPrimary),
        ),
      ),
    );
    if (tooltip == null) return button;
    return Tooltip(message: tooltip!, child: button);
  }
}

/// Selectable pill used for genres, filters and sort options.
class WingsFilterChip extends StatelessWidget {
  const WingsFilterChip({
    super.key,
    required this.label,
    this.selected = false,
    this.onTap,
    this.leadingIcon,
  });

  final String label;
  final bool selected;
  final VoidCallback? onTap;
  final IconData? leadingIcon;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final foreground = selected ? palette.onPrimary : palette.textSecondary;
    return WingsPressable(
      borderRadius: BorderRadius.circular(Radii.pill),
      haptic: false,
      onTap: onTap,
      child: AnimatedContainer(
        duration: Motion.fast,
        curve: Motion.standard,
        padding: const EdgeInsets.symmetric(
          horizontal: Space.md + 2,
          vertical: Space.sm,
        ),
        decoration: BoxDecoration(
          gradient: selected ? palette.brandGradient : null,
          color: selected ? null : palette.surfaceAlt,
          borderRadius: BorderRadius.circular(Radii.pill),
          border: Border.all(
            color: selected ? Colors.transparent : palette.border,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            if (leadingIcon != null) ...<Widget>[
              Icon(leadingIcon, size: 14, color: foreground),
              const SizedBox(width: Space.xs + 2),
            ],
            Text(
              label,
              style: context.text.labelMedium?.copyWith(color: foreground),
            ),
          ],
        ),
      ),
    );
  }
}
