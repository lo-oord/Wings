import 'package:flutter/material.dart';

import '../../app/theme/app_tokens.dart';
import '../../app/theme/context_ext.dart';
import '../services/app_feedback.dart';

/// A press that answers immediately with a small scale and an optional haptic.
///
/// The animation is driven by the ink highlight, so it starts on touch-down
/// rather than after the tap is recognised, and it collapses to zero when the
/// system asks for reduced motion. Nothing is rebuilt outside this subtree.
class WingsPressable extends StatefulWidget {
  const WingsPressable({
    super.key,
    required this.child,
    this.onTap,
    this.onLongPress,
    this.borderRadius,
    this.scale = 0.97,
    this.haptic = true,
    this.enabled = true,
  });

  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final BorderRadius? borderRadius;
  final double scale;
  final bool haptic;
  final bool enabled;

  @override
  State<WingsPressable> createState() => _WingsPressableState();
}

class _WingsPressableState extends State<WingsPressable> {
  bool _pressed = false;

  void _setPressed(bool value) {
    if (!mounted || _pressed == value) return;
    setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    final active = widget.enabled && widget.onTap != null;
    final radius = widget.borderRadius ?? BorderRadius.circular(Radii.sm);
    return Material(
      color: Colors.transparent,
      borderRadius: radius,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        borderRadius: radius,
        onTap: active
            ? () {
                if (widget.haptic) AppFeedback.hapticLight();
                widget.onTap?.call();
              }
            : null,
        onLongPress: widget.onLongPress,
        onHighlightChanged: active ? _setPressed : null,
        child: AnimatedScale(
          scale: _pressed && active ? widget.scale : 1,
          duration: context.motionDuration(Motion.fast),
          curve: Motion.standard,
          child: widget.child,
        ),
      ),
    );
  }
}

/// Swaps between two icons with a short scale/fade, so a state change reads as
/// one deliberate movement instead of an instant shape swap.
class WingsAnimatedIcon extends StatelessWidget {
  const WingsAnimatedIcon({
    super.key,
    required this.icon,
    this.size = 20,
    this.color,
    this.duration = Motion.fast,
  });

  final IconData icon;
  final double size;
  final Color? color;
  final Duration duration;

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: context.motionDuration(duration),
      switchInCurve: Motion.enter,
      switchOutCurve: Motion.exit,
      transitionBuilder: (child, animation) => ScaleTransition(
        scale: Tween<double>(begin: 0.82, end: 1).animate(animation),
        child: FadeTransition(opacity: animation, child: child),
      ),
      child: Icon(
        icon,
        key: ValueKey<IconData>(icon),
        size: size,
        color: color,
      ),
    );
  }
}

/// Fade + tiny rise used by states (empty, error, first paint). It plays once
/// per mount and is skipped entirely with reduced motion, so a rebuild does not
/// replay it.
class WingsFadeIn extends StatefulWidget {
  const WingsFadeIn({super.key, required this.child, this.offset = 8});

  final Widget child;
  final double offset;

  @override
  State<WingsFadeIn> createState() => _WingsFadeInState();
}

class _WingsFadeInState extends State<WingsFadeIn>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: Motion.normal,
  );

  @override
  void initState() {
    super.initState();
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (context.reduceMotion) return widget.child;
    final curved = CurvedAnimation(parent: _controller, curve: Motion.enter);
    return FadeTransition(
      opacity: curved,
      child: SlideTransition(
        position: Tween<Offset>(
          begin: Offset(0, widget.offset / 100),
          end: Offset.zero,
        ).animate(curved),
        child: widget.child,
      ),
    );
  }
}
