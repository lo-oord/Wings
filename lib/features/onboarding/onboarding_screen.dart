import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/localization/app_localizations.dart';
import '../../app/providers.dart';
import '../../app/router/route_paths.dart';
import '../../app/theme/app_tokens.dart';
import '../../app/theme/context_ext.dart';
import '../../core/widgets/wings_buttons.dart';
import '../../core/widgets/wings_image.dart';

/// The three ideas the app is built around, shown once before the sign-in
/// gate. Each page is a full illustration with its own copy; the controls stay
/// fixed at the bottom so the action never moves under the thumb.
class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  final PageController _controller = PageController();
  int _index = 0;
  bool _busy = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _finish({bool guest = false}) async {
    if (_busy) return;
    setState(() => _busy = true);
    final notifier = ref.read(settingsProvider.notifier);
    // Onboarding is marked done for guests too, so the next launch opens the
    // catalogue directly instead of repeating the slides.
    await notifier.completeOnboarding();
    if (guest) await notifier.enterGuestMode();
    if (!mounted) return;
    context.go(guest ? RoutePaths.latest : RoutePaths.welcome);
  }

  void _advance(int lastIndex) {
    if (_index >= lastIndex) {
      _finish();
      return;
    }
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    _controller.nextPage(
      duration: reduceMotion ? Duration.zero : Motion.page,
      curve: Motion.emphasized,
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final palette = context.palette;

    final slides = <_Slide>[
      _Slide(
        icon: Icons.play_circle_fill_rounded,
        title: l10n.onboardingTitle1,
        body: l10n.onboardingBody1,
      ),
      _Slide(
        icon: Icons.high_quality_rounded,
        title: l10n.onboardingTitle2,
        body: l10n.onboardingBody2,
      ),
      _Slide(
        icon: Icons.collections_bookmark_rounded,
        title: l10n.onboardingTitle3,
        body: l10n.onboardingBody3,
      ),
    ];
    final lastIndex = slides.length - 1;
    final isLast = _index == lastIndex;

    return Scaffold(
      backgroundColor: palette.background,
      body: Stack(
        children: <Widget>[
          // Two soft washes keep the canvas from reading as a flat grey page
          // while staying neutral; the green never becomes a background.
          Positioned(
            top: -180,
            right: -120,
            child: _Glow(color: palette.primary.withValues(alpha: 0.16)),
          ),
          Positioned(
            bottom: -220,
            left: -140,
            child: _Glow(color: palette.accent.withValues(alpha: 0.1)),
          ),
          SafeArea(
            child: Column(
              children: <Widget>[
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    Space.xl,
                    Space.md,
                    Space.lg,
                    Space.sm,
                  ),
                  child: Row(
                    children: <Widget>[
                      const WingsMark(size: 30),
                      const SizedBox(width: Space.sm),
                      Text(
                        'Wings',
                        style: context.text.titleLarge?.copyWith(
                          fontWeight: FontWeight.w700,
                          letterSpacing: -0.4,
                        ),
                      ),
                      const Spacer(),
                      AnimatedOpacity(
                        opacity: isLast ? 0 : 1,
                        duration: Motion.fast,
                        child: IgnorePointer(
                          ignoring: isLast || _busy,
                          child: TextButton(
                            onPressed: _busy ? null : () => _finish(),
                            child: Text(l10n.onboardingSkip),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: PageView.builder(
                    controller: _controller,
                    itemCount: slides.length,
                    onPageChanged: (index) => setState(() => _index = index),
                    itemBuilder: (context, index) =>
                        _SlideView(slide: slides[index]),
                  ),
                ),
                Padding(
                  padding: const EdgeInsetsDirectional.fromSTEB(
                    Space.xl,
                    Space.md,
                    Space.xl,
                    Space.lg,
                  ),
                  child: Column(
                    children: <Widget>[
                      _PageDots(count: slides.length, index: _index),
                      const SizedBox(height: Space.xl),
                      WingsButton(
                        label: isLast
                            ? l10n.onboardingStart
                            : l10n.onboardingNext,
                        expand: true,
                        loading: _busy,
                        icon: isLast
                            ? Icons.check_rounded
                            : (context.isRtl
                                  ? Icons.arrow_back_rounded
                                  : Icons.arrow_forward_rounded),
                        onPressed: _busy ? null : () => _advance(lastIndex),
                      ),
                      const SizedBox(height: Space.xs),
                      TextButton(
                        onPressed: _busy ? null : () => _finish(guest: true),
                        child: Text(l10n.authContinueGuest),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Slide {
  const _Slide({required this.icon, required this.title, required this.body});

  final IconData icon;
  final String title;
  final String body;
}

class _SlideView extends StatelessWidget {
  const _SlideView({required this.slide});

  final _Slide slide;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return LayoutBuilder(
      builder: (context, constraints) {
        return SingleChildScrollView(
          padding: const EdgeInsetsDirectional.symmetric(horizontal: Space.xxl),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                _SlideArt(icon: slide.icon),
                const SizedBox(height: Space.xxxl),
                Text(
                  slide.title,
                  textAlign: TextAlign.center,
                  style: context.text.displaySmall?.copyWith(
                    fontSize: 27,
                    height: 1.25,
                    letterSpacing: -0.6,
                  ),
                ),
                const SizedBox(height: Space.md),
                Text(
                  slide.body,
                  textAlign: TextAlign.center,
                  style: context.text.bodyMedium?.copyWith(
                    color: palette.textSecondary,
                    height: 1.75,
                  ),
                ),
                const SizedBox(height: Space.xl),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// The illustration of a page: a rounded surface carrying the brand mark of
/// the feature, with a soft halo behind it.
class _SlideArt extends StatelessWidget {
  const _SlideArt({required this.icon});

  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return SizedBox(
      width: 236,
      height: 216,
      child: Stack(
        alignment: Alignment.center,
        children: <Widget>[
          Container(
            width: 216,
            height: 216,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: <Color>[
                  palette.primary.withValues(alpha: 0.18),
                  palette.primary.withValues(alpha: 0),
                ],
              ),
            ),
          ),
          Container(
            width: 164,
            height: 164,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(Radii.xl + 10),
              gradient: LinearGradient(
                begin: AlignmentDirectional.topStart,
                end: AlignmentDirectional.bottomEnd,
                colors: <Color>[palette.surface, palette.surfaceAlt],
              ),
              border: Border.all(color: palette.border),
              boxShadow: <BoxShadow>[
                BoxShadow(
                  color: Colors.black.withValues(
                    alpha: palette.isDark ? 0.35 : 0.07,
                  ),
                  blurRadius: 32,
                  offset: const Offset(0, 16),
                ),
              ],
            ),
            child: Center(
              child: Container(
                width: 76,
                height: 76,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: palette.brandGradient,
                  boxShadow: <BoxShadow>[
                    BoxShadow(
                      color: palette.primary.withValues(alpha: 0.35),
                      blurRadius: 22,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: Icon(icon, size: 36, color: palette.onPrimary),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PageDots extends StatelessWidget {
  const _PageDots({required this.count, required this.index});

  final int count;
  final int index;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: <Widget>[
        for (var i = 0; i < count; i++)
          AnimatedContainer(
            duration: reduceMotion ? Duration.zero : Motion.normal,
            curve: Motion.emphasized,
            width: i == index ? 26 : 8,
            height: 8,
            margin: const EdgeInsetsDirectional.only(end: Space.sm - 2),
            decoration: BoxDecoration(
              color: i == index ? palette.primary : palette.surfaceHigh,
              borderRadius: BorderRadius.circular(Radii.pill),
            ),
          ),
      ],
    );
  }
}

class _Glow extends StatelessWidget {
  const _Glow({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        width: 340,
        height: 340,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            colors: <Color>[color, color.withValues(alpha: 0)],
          ),
        ),
      ),
    );
  }
}
