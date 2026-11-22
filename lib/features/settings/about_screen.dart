import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app/localization/app_localizations.dart';
import '../../app/router/route_paths.dart';
import '../../app/theme/app_tokens.dart';
import '../../app/theme/context_ext.dart';
import '../../core/constants/app_links.dart';
import '../../core/utils/tr.dart';
import '../../core/widgets/update_prompt.dart';
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
                icon: Icons.verified_user_outlined,
                title: Tr.of(context, ar: 'مركز الأمان', en: 'Security centre'),
                subtitle: Tr.of(
                  context,
                  ar: 'كيف نحمي حسابك وبياناتك',
                  en: 'How your account and data are protected',
                ),
                showChevron: true,
                onTap: () => launchUrl(
                  Uri.parse(AppLinks.security),
                  mode: LaunchMode.externalApplication,
                ),
              ),
              WingsSettingsTile(
                icon: Icons.help_outline_rounded,
                title: Tr.of(
                  context,
                  ar: 'الدعم والأسئلة',
                  en: 'Support & FAQ',
                ),
                showChevron: true,
                onTap: () => launchUrl(
                  Uri.parse(AppLinks.support),
                  mode: LaunchMode.externalApplication,
                ),
              ),
              WingsSettingsTile(
                icon: Icons.public_rounded,
                title: Tr.of(
                  context,
                  ar: 'الموقع الرسمي',
                  en: 'Official website',
                ),
                subtitle: 'wingsapp.vercel.app',
                showChevron: true,
                onTap: () => launchUrl(
                  Uri.parse(AppLinks.site),
                  mode: LaunchMode.externalApplication,
                ),
              ),
              WingsSettingsTile(
                icon: Icons.system_update_alt_rounded,
                title: Tr.of(
                  context,
                  ar: 'التحقق من التحديثات',
                  en: 'Check for updates',
                ),
                showChevron: true,
                onTap: () => checkForUpdates(context, ref, manual: true),
              ),
              WingsSettingsTile(
                icon: Icons.new_releases_outlined,
                title: Tr.of(context, ar: 'كل الإصدارات', en: 'All releases'),
                showChevron: true,
                onTap: () => launchUrl(
                  Uri.parse('${AppLinks.site}/versions'),
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
