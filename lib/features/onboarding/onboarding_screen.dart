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
  bool _busy = false;

  Future<void> _finish({bool guest = false}) async {
    if (_busy) return;
    setState(() => _busy = true);
    final notifier = ref.read(settingsProvider.notifier);
    await notifier.completeOnboarding();
    if (guest) await notifier.enterGuestMode();
    if (!mounted) return;
    context.go(guest ? RoutePaths.latest : RoutePaths.welcome);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final palette = context.palette;

    final features = <(IconData, String)>[
      (Icons.play_circle_fill_rounded, l10n.onboardingTitle1),
      (Icons.download_for_offline_rounded, l10n.onboardingTitle2),
      (Icons.notifications_active_rounded, l10n.onboardingTitle3),
    ];

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(Space.xl),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              const Spacer(),
              Center(child: WingsMark(size: 96)),
              const SizedBox(height: Space.xl),
              Center(
                child: Text(
                  'Wings',
                  style: context.text.displaySmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.8,
                  ),
                ),
              ),
              const SizedBox(height: Space.xl),
              for (final feature in features)
                Padding(
                  padding: const EdgeInsets.only(bottom: Space.md),
                  child: Container(
                    padding: const EdgeInsets.all(Space.md),
                    decoration: BoxDecoration(
                      color: palette.surface,
                      borderRadius: BorderRadius.circular(Radii.md),
                      border: Border.all(color: palette.border),
                    ),
                    child: Row(
                      children: <Widget>[
                        Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: palette.primary.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(Radii.sm),
                          ),
                          child: Icon(
                            feature.$1,
                            size: 21,
                            color: palette.primary,
                          ),
                        ),
                        const SizedBox(width: Space.md),
                        Expanded(
                          child: Text(
                            feature.$2,
                            style: context.text.bodyLarge?.copyWith(
                              fontSize: 14,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              const Spacer(),
              WingsButton(
                label: l10n.authRegister,
                expand: true,
                loading: _busy,
                onPressed: _busy ? null : () => _finish(),
              ),
              const SizedBox(height: Space.sm),
              WingsButton(
                label: l10n.authContinueGuest,
                variant: WingsButtonVariant.ghost,
                expand: true,
                onPressed: _busy ? null : () => _finish(guest: true),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
