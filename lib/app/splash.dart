import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../core/widgets/wings_image.dart';
import 'theme/app_palette.dart';
import 'theme/app_theme.dart';
import 'theme/app_tokens.dart';

/// The branded launch screen.
///
/// It is the very first frame the app draws. [WingsBootstrap] keeps it on top
/// of the interface until the local store and its services are ready, then
/// fades it away, so opening the app never shows a blank window or an
/// interface that is still assembling itself.
class WingsSplashApp extends StatelessWidget {
  const WingsSplashApp({
    super.key,
    required this.progress,
    this.failed = false,
    this.onRetry,
  });

  /// Start-up progress, 0..1, reported by the bootstrap.
  final ValueListenable<double> progress;

  /// True when opening the store failed, so the splash offers a retry instead
  /// of waiting forever.
  final bool failed;

  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Wings',
      debugShowCheckedModeBanner: false,
      theme: buildWingsTheme(WingsPalette.light),
      darkTheme: buildWingsTheme(WingsPalette.dark),
      themeMode: ThemeMode.system,
      home: WingsSplashScreen(
        progress: progress,
        failed: failed,
        onRetry: onRetry,
      ),
    );
  }
}

class WingsSplashScreen extends StatefulWidget {
  const WingsSplashScreen({
    super.key,
    required this.progress,
    this.failed = false,
    this.onRetry,
  });

  final ValueListenable<double> progress;
  final bool failed;
  final VoidCallback? onRetry;

  @override
  State<WingsSplashScreen> createState() => _WingsSplashScreenState();
}

class _WingsSplashScreenState extends State<WingsSplashScreen>
    with TickerProviderStateMixin {
  late final AnimationController _enter = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..forward();

  /// A slow breath under the mark, started once the entrance is complete so
  /// the two motions never fight each other.
  late final AnimationController _breath = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2800),
  );

  late final Animation<double> _fade = CurvedAnimation(
    parent: _enter,
    curve: const Interval(0, 0.7, curve: Curves.easeOutCubic),
  );

  late final Animation<Offset> _rise = Tween<Offset>(
    begin: const Offset(0, 0.1),
    end: Offset.zero,
  ).animate(CurvedAnimation(parent: _enter, curve: Curves.easeOutQuint));

  late final Animation<double> _scale = Tween<double>(
    begin: 0.9,
    end: 1,
  ).animate(CurvedAnimation(parent: _enter, curve: Curves.easeOutQuint));

  late final Animation<double> _wordmark = CurvedAnimation(
    parent: _enter,
    curve: const Interval(0.25, 0.9, curve: Curves.easeOutCubic),
  );

  late final Animation<double> _footer = CurvedAnimation(
    parent: _enter,
    curve: const Interval(0.45, 1, curve: Curves.easeOutCubic),
  );

  @override
  void initState() {
    super.initState();
    _enter.addStatusListener(_onEntranceDone);
  }

  void _onEntranceDone(AnimationStatus status) {
    if (status != AnimationStatus.completed || !mounted) return;
    final reduceMotion = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (!reduceMotion) _breath.repeat(reverse: true);
  }

  @override
  void dispose() {
    _enter.removeStatusListener(_onEntranceDone);
    _enter.dispose();
    _breath.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = Theme.of(context).extension<WingsPalette>()!;
    final reduceMotion = MediaQuery.maybeDisableAnimationsOf(context) ?? false;

    return Scaffold(
      backgroundColor: palette.background,
      body: DecoratedBox(
        decoration: BoxDecoration(
          // The wash gathers behind the mark and fades back to the neutral
          // canvas at the edges, so the launch still reads as Wings without
          // turning the whole screen green.
          gradient: RadialGradient(
            center: const Alignment(0, -0.3),
            radius: 0.72,
            colors: <Color>[
              palette.primary.withValues(alpha: palette.isDark ? 0.14 : 0.08),
              palette.background,
            ],
          ),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: Space.xxl),
            child: Column(
              children: <Widget>[
                const Spacer(flex: 4),
                FadeTransition(
                  opacity: reduceMotion ? kAlwaysCompleteAnimation : _fade,
                  child: SlideTransition(
                    position: _rise,
                    child: ScaleTransition(
                      scale: reduceMotion ? kAlwaysCompleteAnimation : _scale,
                      child: _SplashMark(
                        palette: palette,
                        breath: reduceMotion ? null : _breath,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: Space.xl),
                FadeTransition(
                  opacity: reduceMotion ? kAlwaysCompleteAnimation : _wordmark,
                  child: Column(
                    children: <Widget>[
                      Text(
                        'Wings',
                        style: TextStyle(
                          color: palette.textPrimary,
                          fontSize: 28,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -0.8,
                          height: 1.1,
                        ),
                      ),
                      const SizedBox(height: Space.sm - 2),
                      Text(
                        'أنمي بلا حدود',
                        style: TextStyle(
                          color: palette.textMuted,
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          letterSpacing: 2,
                        ),
                      ),
                    ],
                  ),
                ),
                const Spacer(flex: 3),
                FadeTransition(
                  opacity: reduceMotion ? kAlwaysCompleteAnimation : _footer,
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: Space.xxxl),
                    child: SizedBox(
                      height: 56,
                      child: Center(
                        child: widget.failed
                            ? _SplashFailure(onRetry: widget.onRetry)
                            : _SplashProgress(progress: widget.progress),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SplashMark extends StatelessWidget {
  const _SplashMark({required this.palette, this.breath});

  final WingsPalette palette;
  final Animation<double>? breath;

  @override
  Widget build(BuildContext context) {
    final halo = Container(
      width: 168,
      height: 168,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          colors: <Color>[
            palette.primary.withValues(alpha: 0.22),
            palette.primary.withValues(alpha: 0),
          ],
        ),
      ),
    );

    return SizedBox(
      width: 176,
      height: 176,
      child: Stack(
        alignment: Alignment.center,
        children: <Widget>[
          if (breath == null)
            halo
          else
            ScaleTransition(
              scale: Tween<double>(begin: 1, end: 1.08).animate(
                CurvedAnimation(parent: breath!, curve: Curves.easeInOut),
              ),
              child: halo,
            ),
          Container(
            width: 124,
            height: 124,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: palette.surface,
              border: Border.all(color: palette.border),
              boxShadow: <BoxShadow>[
                BoxShadow(
                  color: palette.primary.withValues(alpha: 0.2),
                  blurRadius: 44,
                  spreadRadius: 2,
                ),
              ],
            ),
            child: const WingsMark(size: 78),
          ),
        ],
      ),
    );
  }
}

/// A thin bar that advances with the real start-up work instead of looping
/// forever, so the wait is honest about what is happening.
class _SplashProgress extends StatefulWidget {
  const _SplashProgress({required this.progress});

  final ValueListenable<double> progress;

  @override
  State<_SplashProgress> createState() => _SplashProgressState();
}

class _SplashProgressState extends State<_SplashProgress> {
  late double _value = widget.progress.value.clamp(0.0, 1.0);

  @override
  void initState() {
    super.initState();
    widget.progress.addListener(_sync);
  }

  void _sync() => setState(() {});

  @override
  void dispose() {
    widget.progress.removeListener(_sync);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = Theme.of(context).extension<WingsPalette>()!;
    final target = widget.progress.value.clamp(0.0, 1.0);

    return SizedBox(
      width: 148,
      height: 4,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(Radii.pill),
        child: Stack(
          fit: StackFit.expand,
          children: <Widget>[
            ColoredBox(color: palette.surfaceHigh),
            TweenAnimationBuilder<double>(
              tween: Tween<double>(begin: _value, end: target),
              duration: Motion.normal,
              curve: Motion.standard,
              onEnd: () => _value = target,
              builder: (context, animated, _) => FractionallySizedBox(
                alignment: AlignmentDirectional.centerStart,
                widthFactor: animated,
                heightFactor: 1,
                child: DecoratedBox(
                  decoration: BoxDecoration(gradient: palette.brandGradient),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SplashFailure extends StatelessWidget {
  const _SplashFailure({this.onRetry});

  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final palette = Theme.of(context).extension<WingsPalette>()!;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Text(
          'تعذّر تجهيز التطبيق',
          style: TextStyle(color: palette.textSecondary, fontSize: 13),
        ),
        const SizedBox(height: Space.sm),
        TextButton(onPressed: onRetry, child: const Text('إعادة المحاولة')),
      ],
    );
  }
}
