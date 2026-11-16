import 'package:flutter/material.dart';

import '../../app/localization/app_localizations.dart';
import '../../app/theme/app_tokens.dart';
import '../../app/theme/context_ext.dart';
import '../errors/app_failure.dart';

/// Animated shimmer used for loading placeholders.
class WingsSkeleton extends StatefulWidget {
  const WingsSkeleton({
    super.key,
    this.width,
    this.height,
    this.borderRadius = const BorderRadius.all(Radius.circular(Radii.xs)),
    this.child,
  });

  final double? width;
  final double? height;
  final BorderRadius borderRadius;
  final Widget? child;

  @override
  State<WingsSkeleton> createState() => _WingsSkeletonState();
}

class _WingsSkeletonState extends State<WingsSkeleton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    Widget block(double t) {
      final center = -0.4 + t * 1.8;
      return DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: widget.borderRadius,
          gradient: LinearGradient(
            begin: Alignment(center - 0.6, 0),
            end: Alignment(center + 0.6, 0),
            colors: <Color>[
              palette.skeletonBase,
              palette.skeletonHighlight,
              palette.skeletonBase,
            ],
            stops: const <double>[0.25, 0.5, 0.75],
          ),
        ),
        child: SizedBox(
          width: widget.width,
          height: widget.height,
          child: widget.child,
        ),
      );
    }

    if (reduceMotion) return block(0.5);
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) => block(_controller.value),
    );
  }
}

/// A poster-shaped loading placeholder.
class WingsPosterSkeleton extends StatelessWidget {
  const WingsPosterSkeleton({super.key, this.width});

  final double? width;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          AspectRatio(
            aspectRatio: Ratios.poster,
            child: WingsSkeleton(borderRadius: BorderRadius.circular(Radii.sm)),
          ),
          const SizedBox(height: Space.sm),
          const WingsSkeleton(height: 12, width: 120),
          const SizedBox(height: Space.xs + 2),
          const WingsSkeleton(height: 10, width: 80),
        ],
      ),
    );
  }
}

/// Consistent empty state used everywhere in the app.
class WingsEmptyState extends StatelessWidget {
  const WingsEmptyState({
    super.key,
    required this.title,
    this.message,
    this.icon = Icons.auto_awesome_outlined,
    this.actionLabel,
    this.onAction,
  });

  final String title;
  final String? message;
  final IconData icon;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: Space.xxl,
          vertical: Space.xxxl,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: palette.surfaceAlt,
                border: Border.all(color: palette.border),
              ),
              child: Icon(icon, color: palette.primary, size: 26),
            ),
            const SizedBox(height: Space.lg),
            Text(
              title,
              textAlign: TextAlign.center,
              style: context.text.titleMedium,
            ),
            if (message != null) ...<Widget>[
              const SizedBox(height: Space.sm),
              Text(
                message!,
                textAlign: TextAlign.center,
                style: context.text.bodySmall?.copyWith(
                  color: palette.textSecondary,
                ),
              ),
            ],
            if (actionLabel != null && onAction != null) ...<Widget>[
              const SizedBox(height: Space.lg),
              TextButton(onPressed: onAction, child: Text(actionLabel!)),
            ],
          ],
        ),
      ),
    );
  }
}

class WingsErrorState extends StatelessWidget {
  const WingsErrorState({super.key, required this.failure, this.onRetry});

  final Object failure;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    final message = failure is AppFailure
        ? (failure as AppFailure).message(localizations)
        : localizations.stateErrorGeneric;
    return WingsEmptyState(
      icon: Icons.cloud_off_rounded,
      title: localizations.commonErrorTitle,
      message: message,
      actionLabel: onRetry == null ? null : localizations.commonRetry,
      onAction: onRetry,
    );
  }
}

/// Slim offline strip shown above cached content.
class WingsOfflineStrip extends StatelessWidget {
  const WingsOfflineStrip({super.key});

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Container(
      margin: const EdgeInsets.fromLTRB(Space.lg, Space.sm, Space.lg, Space.xs),
      padding: const EdgeInsets.symmetric(
        horizontal: Space.md,
        vertical: Space.sm,
      ),
      decoration: BoxDecoration(
        color: palette.surfaceAlt,
        borderRadius: BorderRadius.circular(Radii.sm),
        border: Border.all(color: palette.border),
      ),
      child: Row(
        children: <Widget>[
          Icon(Icons.wifi_off_rounded, size: 16, color: palette.textSecondary),
          const SizedBox(width: Space.sm),
          Expanded(
            child: Text(
              AppLocalizations.of(context).stateOfflineBody,
              style: context.text.bodySmall,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

/// Branded linear progress used for playback and downloads.
class WingsProgressBar extends StatelessWidget {
  const WingsProgressBar({
    super.key,
    required this.value,
    this.height = 4,
    this.background,
  });

  final double value;
  final double height;
  final Color? background;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return ClipRRect(
      borderRadius: BorderRadius.circular(Radii.pill),
      child: SizedBox(
        height: height,
        child: Stack(
          fit: StackFit.expand,
          children: <Widget>[
            ColoredBox(color: background ?? palette.border),
            FractionallySizedBox(
              alignment: AlignmentDirectional.centerStart,
              widthFactor: value.clamp(0.0, 1.0),
              child: DecoratedBox(
                decoration: BoxDecoration(gradient: palette.brandGradient),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Small inline spinner that keeps layout stable.
class WingsLoading extends StatelessWidget {
  const WingsLoading({super.key, this.size = 20});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SizedBox(
        width: size,
        height: size,
        child: CircularProgressIndicator(
          strokeWidth: 2,
          color: context.palette.primary,
        ),
      ),
    );
  }
}
