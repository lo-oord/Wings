import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app/localization/app_localizations.dart';
import '../../app/router/route_paths.dart';
import '../../app/theme/app_tokens.dart';
import '../../app/theme/context_ext.dart';
import '../../core/widgets/wings_image.dart';
import '../../core/widgets/wings_layout.dart';
import 'settings_screen.dart';

class AboutScreen extends ConsumerWidget {
  const AboutScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final palette = context.palette;
    final info = ref.watch(appInfoProvider).value;

    return Scaffold(
      appBar: WingsAppBar(showBack: true, title: Text(l10n.settingsAbout)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
          Space.lg,
          Space.lg,
          Space.lg,
          Space.xxxl,
        ),
        children: <Widget>[
          Center(
            child: Column(
              children: <Widget>[
                const WingsMark(size: 88),
                const SizedBox(height: Space.md),
                Text(
                  'Wings',
                  style: context.text.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: Space.xs),
                Text(
                  '${l10n.settingsVersion} ${info?.version ?? '1.0.0'} (${info?.buildNumber ?? '1'})',
                  style: context.text.labelSmall?.copyWith(
                    color: palette.textMuted,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: Space.xl),
          const SizedBox(height: Space.lg),
          WingsSettingsGroup(
            title: l10n.settingsAbout,
            children: <Widget>[
              WingsSettingsTile(
                icon: Icons.shield_outlined,
                title: l10n.settingsPrivacyPolicy,
                showChevron: true,
                onTap: () => context.push(RoutePaths.legal('privacy')),
              ),
              WingsSettingsTile(
                icon: Icons.description_outlined,
                title: l10n.settingsTerms,
                showChevron: true,
                onTap: () => context.push(RoutePaths.legal('terms')),
              ),
              WingsSettingsTile(
                icon: Icons.public_rounded,
                title: l10n.settingsOpenSource,
                showChevron: true,
                onTap: () => launchUrl(
                  Uri.parse('https://github.com/looooooooord/Wings'),
                  mode: LaunchMode.externalApplication,
                ),
              ),
            ],
          ),
          const SizedBox(height: Space.xl),
          Center(
            child: Text(
              '© 2026 Wings',
              style: context.text.labelSmall?.copyWith(
                color: palette.textMuted,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
