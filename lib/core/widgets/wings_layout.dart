import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../app/router/route_paths.dart';
import '../../app/theme/app_tokens.dart';
import '../../app/theme/context_ext.dart';
import '../../app/localization/app_localizations.dart';
import 'wings_image.dart';

class WingsSectionHeader extends StatelessWidget {
  const WingsSectionHeader({
    super.key,
    required this.title,
    this.actionLabel,
    this.onAction,
    this.padding = const EdgeInsets.fromLTRB(
      Space.lg,
      Space.xl,
      Space.lg,
      Space.md,
    ),
  });

  final String title;
  final String? actionLabel;
  final VoidCallback? onAction;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: padding,
      child: Row(
        children: <Widget>[
          Expanded(
            child: Text(
              title,
              style: context.text.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (actionLabel != null && onAction != null)
            GestureDetector(
              onTap: onAction,
              behavior: HitTestBehavior.opaque,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: Space.xs,
                  vertical: Space.xs,
                ),
                child: Row(
                  children: <Widget>[
                    Text(
                      actionLabel!,
                      style: context.text.labelMedium?.copyWith(
                        color: context.palette.primary,
                      ),
                    ),
                    const SizedBox(width: 2),
                    Icon(
                      context.isRtl
                          ? Icons.chevron_left_rounded
                          : Icons.chevron_right_rounded,
                      size: 16,
                      color: context.palette.primary,
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

enum WingsBadgeStyle { neutral, brand, overlay, success, warning }

class WingsBadge extends StatelessWidget {
  const WingsBadge(
    this.label, {
    super.key,
    this.style = WingsBadgeStyle.neutral,
    this.icon,
    this.compact = false,
  });

  final String label;
  final WingsBadgeStyle style;
  final IconData? icon;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final (background, foreground) = switch (style) {
      WingsBadgeStyle.neutral => (palette.surfaceHigh, palette.textSecondary),
      WingsBadgeStyle.brand => (null, palette.onPrimary),
      WingsBadgeStyle.overlay => (
        palette.overlay.withValues(alpha: 0.72),
        Colors.white,
      ),
      WingsBadgeStyle.success => (
        palette.success.withValues(alpha: 0.16),
        palette.success,
      ),
      WingsBadgeStyle.warning => (
        palette.warning.withValues(alpha: 0.18),
        palette.warning,
      ),
    };

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? Space.sm : Space.md - 2,
        vertical: compact ? 3 : 5,
      ),
      decoration: BoxDecoration(
        gradient: style == WingsBadgeStyle.brand ? palette.brandGradient : null,
        color: background,
        borderRadius: BorderRadius.circular(Radii.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (icon != null) ...<Widget>[
            Icon(icon, size: compact ? 10 : 12, color: foreground),
            const SizedBox(width: 3),
          ],
          Text(
            label,
            style: context.text.labelSmall?.copyWith(
              color: foreground,
              fontSize: compact ? 10 : 11,
              height: 1.1,
            ),
          ),
        ],
      ),
    );
  }
}

class WingsRatingLabel extends StatelessWidget {
  const WingsRatingLabel({
    super.key,
    required this.rating,
    this.compact = false,
  });

  final double rating;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Icon(
          Icons.star_rounded,
          size: compact ? 13 : 15,
          color: palette.warning,
        ),
        const SizedBox(width: 2),
        Text(
          rating.toStringAsFixed(1),
          style: (compact ? context.text.labelSmall : context.text.labelMedium)
              ?.copyWith(
                color: palette.textPrimary,
                fontWeight: FontWeight.w600,
              ),
        ),
      ],
    );
  }
}

class WingsAppBar extends StatelessWidget implements PreferredSizeWidget {
  const WingsAppBar({
    super.key,
    this.title,
    this.actions,
    this.showBack = false,
    this.bottom,
    this.transparent = true,
  });

  final Widget? title;
  final List<Widget>? actions;
  final bool showBack;
  final PreferredSizeWidget? bottom;
  final bool transparent;

  @override
  Size get preferredSize =>
      Size.fromHeight(kToolbarHeight + (bottom?.preferredSize.height ?? 0));

  /// A screen opened from a notification or a shared link has nothing beneath
  /// it, so a plain `pop` used to leave the reader stuck on that page. Falls
  /// back to the home tab instead of doing nothing.
  void _handleBack(BuildContext context) {
    final router = GoRouter.maybeOf(context);
    if (router != null) {
      if (router.canPop()) {
        router.pop();
      } else {
        router.go(RoutePaths.latest);
      }
      return;
    }
    Navigator.of(context).maybePop();
  }

  @override
  Widget build(BuildContext context) {
    return AppBar(
      backgroundColor: transparent
          ? Colors.transparent
          : context.palette.surface,
      automaticallyImplyLeading: false,
      leading: showBack
          ? Padding(
              padding: const EdgeInsets.only(left: Space.sm, right: Space.sm),
              child: IconButton(
                icon: Icon(
                  context.isRtl
                      ? Icons.arrow_forward_rounded
                      : Icons.arrow_back_rounded,
                  size: 22,
                ),
                onPressed: () => _handleBack(context),
              ),
            )
          : null,
      title: title,
      actions: actions,
      bottom: bottom,
    );
  }
}

/// Floating, pill-shaped navigation bar with an animated selected capsule.
class WingsBottomNav extends StatelessWidget {
  const WingsBottomNav({
    super.key,
    required this.currentIndex,
    required this.onSelect,
  });

  final int currentIndex;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final localizations = AppLocalizations.of(context);
    final destinations = <(IconData, IconData, String)>[
      (
        Icons.play_circle_outline_rounded,
        Icons.play_circle_fill_rounded,
        localizations.navLatest,
      ),
      (
        Icons.travel_explore_rounded,
        Icons.travel_explore_rounded,
        localizations.navExplore,
      ),
      (
        Icons.collections_bookmark_outlined,
        Icons.collections_bookmark_rounded,
        localizations.navLibrary,
      ),
      (
        Icons.settings_outlined,
        Icons.settings_rounded,
        localizations.navSettings,
      ),
    ];

    return Padding(
      padding: const EdgeInsets.fromLTRB(Space.lg, 0, Space.lg, Space.sm),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: palette.surface,
          borderRadius: BorderRadius.circular(Radii.pill),
          border: Border.all(color: palette.border),
          boxShadow: <BoxShadow>[
            BoxShadow(
              color: Colors.black.withValues(
                alpha: palette.isDark ? 0.4 : 0.08,
              ),
              blurRadius: 24,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.all(Space.xs + 2),
          child: Row(
            children: <Widget>[
              for (var index = 0; index < destinations.length; index++)
                Expanded(
                  child: _NavItem(
                    icon: destinations[index].$1,
                    activeIcon: destinations[index].$2,
                    label: destinations[index].$3,
                    selected: index == currentIndex,
                    onTap: () => onSelect(index),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.icon,
    required this.activeIcon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final IconData activeIcon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final foreground = selected ? palette.primary : palette.textMuted;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    return Semantics(
      selected: selected,
      button: true,
      label: label,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(Radii.pill),
        splashFactory: NoSplash.splashFactory,
        child: Stack(
          alignment: Alignment.center,
          children: <Widget>[
            Positioned.fill(
              child: AnimatedOpacity(
                opacity: selected ? 1 : 0,
                duration: reduceMotion ? Duration.zero : Motion.normal,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: palette.primary.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(Radii.pill),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: Space.sm - 2),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  AnimatedScale(
                    scale: selected ? 1.08 : 1,
                    duration: reduceMotion ? Duration.zero : Motion.fast,
                    curve: Motion.emphasized,
                    child: AnimatedSwitcher(
                      duration: reduceMotion ? Duration.zero : Motion.fast,
                      child: Icon(
                        selected ? activeIcon : icon,
                        key: ValueKey<bool>(selected),
                        size: 21,
                        color: foreground,
                      ),
                    ),
                  ),
                  const SizedBox(height: 2),
                  AnimatedDefaultTextStyle(
                    duration: reduceMotion ? Duration.zero : Motion.fast,
                    style: context.text.labelSmall!.copyWith(
                      color: foreground,
                      fontSize: 10.5,
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                      height: 1.2,
                    ),
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class WingsSettingsTile extends StatelessWidget {
  const WingsSettingsTile({
    super.key,
    this.icon,
    required this.title,
    this.subtitle,
    this.trailing,
    this.onTap,
    this.destructive = false,
    this.showChevron = false,
  });

  final IconData? icon;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool destructive;
  final bool showChevron;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: Space.lg,
          vertical: Space.md,
        ),
        child: Row(
          children: <Widget>[
            if (icon != null) ...<Widget>[
              Icon(
                icon,
                size: 19,
                color: destructive ? palette.danger : palette.textSecondary,
              ),
              const SizedBox(width: Space.md),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    title,
                    style: context.text.bodyLarge?.copyWith(
                      fontSize: 14,
                      color: destructive ? palette.danger : palette.textPrimary,
                    ),
                  ),
                  if (subtitle != null) ...<Widget>[
                    const SizedBox(height: 2),
                    Text(
                      subtitle!,
                      style: context.text.bodySmall?.copyWith(
                        color: palette.textMuted,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            ?trailing,
            if (showChevron)
              Padding(
                padding: const EdgeInsets.only(left: Space.xs),
                child: Icon(
                  context.isRtl
                      ? Icons.chevron_left_rounded
                      : Icons.chevron_right_rounded,
                  size: 18,
                  color: palette.textMuted,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Grouped settings surface so every section shares one visual rhythm.
class WingsSettingsGroup extends StatelessWidget {
  const WingsSettingsGroup({
    super.key,
    required this.title,
    required this.children,
    this.footer,
  });

  final String title;
  final List<Widget> children;
  final String? footer;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Padding(
      padding: const EdgeInsets.fromLTRB(Space.lg, Space.xl, Space.lg, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.only(
              bottom: Space.sm,
              right: Space.xs,
              left: Space.xs,
            ),
            child: Text(
              title,
              style: context.text.labelSmall?.copyWith(
                color: palette.textMuted,
                letterSpacing: 0.6,
              ),
            ),
          ),
          Container(
            decoration: BoxDecoration(
              color: palette.surface,
              borderRadius: BorderRadius.circular(Radii.md),
              border: Border.all(color: palette.border),
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: <Widget>[
                for (
                  var index = 0;
                  index < children.length;
                  index++
                ) ...<Widget>[
                  children[index],
                  if (index != children.length - 1)
                    Divider(
                      height: 1,
                      thickness: 1,
                      color: palette.border,
                      indent: Space.lg,
                      endIndent: Space.lg,
                    ),
                ],
              ],
            ),
          ),
          if (footer != null)
            Padding(
              padding: const EdgeInsets.only(
                top: Space.sm,
                right: Space.xs,
                left: Space.xs,
              ),
              child: Text(
                footer!,
                style: context.text.bodySmall?.copyWith(
                  color: palette.textMuted,
                  fontSize: 11,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

abstract final class WingsSheet {
  /// Shows a compact card in the middle of the screen rather than a sheet.
  static Future<T?> show<T>(
    BuildContext context, {
    required String title,
    required WidgetBuilder builder,
    bool scrollable = false,
  }) {
    final palette = context.palette;
    return showDialog<T>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.55),
      builder: (dialogContext) {
        return Dialog(
          insetPadding: const EdgeInsets.symmetric(
            horizontal: Space.xxl,
            vertical: Space.xxl,
          ),
          backgroundColor: palette.surface,
          surfaceTintColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(Radii.lg),
            side: BorderSide(color: palette.border),
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400, maxHeight: 460),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    Space.lg,
                    Space.md,
                    Space.sm,
                    Space.xs,
                  ),
                  child: Row(
                    children: <Widget>[
                      Expanded(
                        child: Text(
                          title,
                          style: dialogContext.text.titleMedium,
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close_rounded, size: 18),
                        color: palette.textMuted,
                        onPressed: () => Navigator.of(dialogContext).pop(),
                      ),
                    ],
                  ),
                ),
                Flexible(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(
                      Space.md,
                      Space.xs,
                      Space.md,
                      Space.md,
                    ),
                    child: builder(dialogContext),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

abstract final class WingsDialog {
  static Future<bool> confirm(
    BuildContext context, {
    required String title,
    required String message,
    required String confirmLabel,
    String? cancelLabel,
    bool destructive = false,
  }) async {
    final palette = context.palette;
    final localizations = AppLocalizations.of(context);
    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actionsPadding: const EdgeInsets.fromLTRB(
          Space.md,
          0,
          Space.md,
          Space.sm,
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(cancelLabel ?? localizations.commonCancel),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: TextButton.styleFrom(
              foregroundColor: destructive ? palette.danger : palette.primary,
            ),
            child: Text(confirmLabel),
          ),
        ],
      ),
    );
    return result ?? false;
  }
}

/// Compact empty brand mark with the app wordmark.
class WingsBrandHeader extends StatelessWidget {
  const WingsBrandHeader({super.key, this.trailing});

  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        const WingsMark(size: 26),
        const SizedBox(width: Space.sm),
        Text(
          'Wings',
          style: context.text.titleLarge?.copyWith(
            fontWeight: FontWeight.w700,
            fontSize: 20,
          ),
        ),
        const Spacer(),
        ?trailing,
      ],
    );
  }
}
