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

class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  final PageController _controller = PageController();
  int _index = 0;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _finish() async {
    await ref.read(settingsProvider.notifier).completeOnboarding();
    if (mounted) context.go(RoutePaths.latest);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final palette = context.palette;
    final pages = <(IconData, String, String)>[
      (Icons.auto_awesome_rounded, l10n.onboardingTitle1, l10n.onboardingBody1),
      (
        Icons.play_circle_outline_rounded,
        l10n.onboardingTitle2,
        l10n.onboardingBody2,
      ),
      (
        Icons.video_library_outlined,
        l10n.onboardingTitle3,
        l10n.onboardingBody3,
      ),
    ];

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(
                Space.lg,
                Space.sm,
                Space.lg,
                0,
              ),
              child: Row(
                children: <Widget>[
                  const WingsLockup(size: 26),
                  const Spacer(),
                  TextButton(
                    onPressed: _finish,
                    child: Text(l10n.onboardingSkip),
                  ),
                ],
              ),
            ),
            Expanded(
              child: PageView.builder(
                controller: _controller,
                itemCount: pages.length,
                onPageChanged: (value) => setState(() => _index = value),
                itemBuilder: (context, index) {
                  final page = pages[index];
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: Space.xxl),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: <Widget>[
                        Container(
                          width: 132,
                          height: 132,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: LinearGradient(
                              begin: AlignmentDirectional.topStart,
                              end: AlignmentDirectional.bottomEnd,
                              colors: <Color>[
                                palette.surfaceAlt,
                                palette.surfaceHigh,
                              ],
                            ),
                            border: Border.all(color: palette.border),
                          ),
                          child: Icon(
                            page.$1,
                            size: 52,
                            color: palette.primary,
                          ),
                        ),
                        const SizedBox(height: Space.xxl),
                        Text(
                          page.$2,
                          textAlign: TextAlign.center,
                          style: context.text.headlineSmall?.copyWith(
                            height: 1.35,
                          ),
                        ),
                        const SizedBox(height: Space.md),
                        Text(
                          page.$3,
                          textAlign: TextAlign.center,
                          style: context.text.bodyMedium?.copyWith(
                            color: palette.textSecondary,
                            height: 1.7,
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: Space.md),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: <Widget>[
                  for (var dot = 0; dot < pages.length; dot++)
                    AnimatedContainer(
                      duration: Motion.normal,
                      curve: Motion.standard,
                      margin: const EdgeInsets.symmetric(horizontal: 3),
                      width: dot == _index ? 20 : 7,
                      height: 7,
                      decoration: BoxDecoration(
                        color: dot == _index
                            ? palette.primary
                            : palette.borderStrong,
                        borderRadius: BorderRadius.circular(Radii.pill),
                      ),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                Space.xl,
                0,
                Space.xl,
                Space.xl,
              ),
              child: WingsButton(
                label: _index == pages.length - 1
                    ? l10n.onboardingStart
                    : l10n.onboardingNext,
                expand: true,
                onPressed: () {
                  if (_index == pages.length - 1) {
                    _finish();
                  } else {
                    _controller.nextPage(
                      duration: Motion.page,
                      curve: Motion.standard,
                    );
                  }
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
