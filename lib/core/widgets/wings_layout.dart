import 'package:flutter/material.dart';

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
                onPressed: () => Navigator.of(context).maybePop(),
              ),
            )
          : null,
      title: title,
      actions: actions,
      bottom: bottom,
    );
  }
}

/// The persistent four-destination navigation bar.
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
        Icons.auto_awesome_outlined,
        Icons.auto_awesome,
        localizations.navLatest,
      ),
      (Icons.explore_outlined, Icons.explore, localizations.navExplore),
      (
        Icons.video_library_outlined,
        Icons.video_library,
        localizations.navLibrary,
      ),
      (Icons.tune_outlined, Icons.tune, localizations.navSettings),
    ];

    return DecoratedBox(
      decoration: BoxDecoration(
        color: palette.surface,
        border: Border(top: BorderSide(color: palette.border)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: Space.sm,
            vertical: Space.xs + 2,
          ),
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
    final foreground = selected ? palette.onPrimary : palette.textMuted;
    return Semantics(
      selected: selected,
      button: true,
      label: label,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(Radii.sm),
        child: AnimatedContainer(
          duration: Motion.normal,
          curve: Motion.standard,
          padding: const EdgeInsets.symmetric(vertical: Space.sm),
          decoration: BoxDecoration(
            gradient: selected ? palette.brandGradient : null,
            borderRadius: BorderRadius.circular(Radii.sm),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(selected ? activeIcon : icon, size: 20, color: foreground),
              const SizedBox(height: 3),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: context.text.labelSmall?.copyWith(
                  color: foreground,
                  fontSize: 10.5,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
            ],
          ),
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
  static Future<T?> show<T>(
    BuildContext context, {
    required String title,
    required WidgetBuilder builder,
    bool scrollable = false,
  }) {
    return showModalBottomSheet<T>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: context.palette.surface,
      builder: (sheetContext) {
        return Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.viewInsetsOf(sheetContext).bottom,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.only(top: Space.md, bottom: Space.xs),
                child: Center(
                  child: Container(
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: sheetContext.palette.borderStrong,
                      borderRadius: BorderRadius.circular(Radii.pill),
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  Space.lg,
                  Space.sm,
                  Space.lg,
                  Space.sm,
                ),
                child: Text(title, style: sheetContext.text.titleMedium),
              ),
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(
                    Space.lg,
                    Space.sm,
                    Space.lg,
                    Space.xl,
                  ),
                  child: builder(sheetContext),
                ),
              ),
            ],
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
