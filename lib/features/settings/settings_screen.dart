import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../app/localization/app_localizations.dart';
import '../../app/providers.dart';
import '../../app/router/route_paths.dart';
import '../../app/theme/app_tokens.dart';
import '../../app/theme/context_ext.dart';
import '../../core/storage/local_store.dart';
import '../../core/utils/formatters.dart';
import '../../core/utils/tr.dart';
import '../../core/widgets/wings_image.dart';
import '../../core/widgets/wings_layout.dart';
import '../profile/avatar_view.dart';

final appInfoProvider = FutureProvider<PackageInfo>(
  (ref) => PackageInfo.fromPlatform(),
);

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final palette = context.palette;
    final settings = ref.watch(settingsProvider);
    final user = ref.watch(authProvider);
    final profile = ref.watch(profileProvider);
    final info = ref.watch(appInfoProvider).value;
    final storage = ref.watch(storageUsedProvider);

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: ListView(
          padding: const EdgeInsets.only(bottom: Space.xxxl),
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(
                Space.lg,
                Space.md,
                Space.lg,
                Space.sm,
              ),
              child: Text(l10n.navSettings, style: context.text.headlineSmall),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: Space.lg),
              child: _AccountCard(
                name: (profile?.displayName.isNotEmpty ?? false)
                    ? profile!.displayName
                    : (user?.displayName ?? l10n.settingsGuest),
                email: user?.email ?? '',
                uid: user?.id ?? '',
                photoVersion: profile?.photoVersion ?? 0,
                subtitle: user == null
                    ? l10n.profileSignInPrompt
                    : (profile?.username.isNotEmpty == true
                          ? '@${profile!.username}'
                          : l10n.settingsGuest),
                onTap: () => context.push(
                  user == null ? RoutePaths.welcome : RoutePaths.profile,
                ),
              ),
            ),
            WingsSettingsGroup(
              title: l10n.settingsAppearance,
              children: <Widget>[
                WingsSettingsTile(
                  icon: Icons.brightness_6_outlined,
                  title: l10n.settingsTheme,
                  subtitle: _themeLabel(context, settings.themeMode),
                  showChevron: true,
                  onTap: () => _pickTheme(context, ref, settings.themeMode),
                ),
                WingsSettingsTile(
                  icon: Icons.translate_rounded,
                  title: l10n.settingsLanguage,
                  subtitle: settings.localeCode == 'ar'
                      ? l10n.settingsArabic
                      : l10n.settingsEnglish,
                  showChevron: true,
                  onTap: () => _pickLanguage(context, ref, settings.localeCode),
                ),
              ],
            ),
            WingsSettingsGroup(
              title: l10n.settingsPlayback,
              children: <Widget>[
                WingsSettingsTile(
                  icon: Icons.speed_rounded,
                  title: l10n.settingsDefaultSpeed,
                  subtitle: '${settings.playbackSpeed}×',
                  showChevron: true,
                  onTap: () => _pickSpeed(context, ref, settings.playbackSpeed),
                ),
                WingsSettingsTile(
                  icon: Icons.high_quality_outlined,
                  title: l10n.settingsDefaultQuality,
                  subtitle: settings.preferredQuality,
                  showChevron: true,
                  onTap: () =>
                      _pickQuality(context, ref, settings.preferredQuality),
                ),
                WingsSettingsTile(
                  icon: Icons.playlist_play_rounded,
                  title: l10n.settingsAutoNext,
                  trailing: Switch(
                    value: settings.autoplayNext,
                    onChanged: (value) => ref
                        .read(settingsProvider.notifier)
                        .update(
                          (current) => current.copyWith(autoplayNext: value),
                        ),
                  ),
                ),
                WingsSettingsTile(
                  icon: Icons.restore_rounded,
                  title: l10n.settingsRememberPosition,
                  trailing: Switch(
                    value: settings.rememberPosition,
                    onChanged: (value) => ref
                        .read(settingsProvider.notifier)
                        .update(
                          (current) =>
                              current.copyWith(rememberPosition: value),
                        ),
                  ),
                ),
              ],
            ),
            WingsSettingsGroup(
              title: l10n.settingsDownloads,
              children: <Widget>[
                WingsSettingsTile(
                  icon: Icons.folder_outlined,
                  title: l10n.settingsDownloads,
                  subtitle: formatBytes(storage),
                  showChevron: true,
                  onTap: () => context.push(RoutePaths.downloads),
                ),
                WingsSettingsTile(
                  icon: Icons.pause_circle_outline_rounded,
                  title: Tr.of(
                    context,
                    ar: 'إيقاف كل التنزيلات مؤقتًا',
                    en: 'Pause all downloads',
                  ),
                  showChevron: true,
                  onTap: () async {
                    await ref.read(downloadServiceProvider).pauseAll();
                    if (context.mounted) {
                      context.showSnack(
                        Tr.of(
                          context,
                          ar: 'تم إيقاف التنزيلات مؤقتًا.',
                          en: 'Downloads paused.',
                        ),
                      );
                    }
                  },
                ),
                WingsSettingsTile(
                  icon: Icons.play_circle_outline_rounded,
                  title: Tr.of(
                    context,
                    ar: 'استئناف التنزيلات',
                    en: 'Resume downloads',
                  ),
                  showChevron: true,
                  onTap: () => ref.read(downloadServiceProvider).resumeAll(),
                ),
                WingsSettingsTile(
                  icon: Icons.replay_rounded,
                  title: Tr.of(
                    context,
                    ar: 'إعادة محاولة التنزيلات الفاشلة',
                    en: 'Retry failed downloads',
                  ),
                  showChevron: true,
                  onTap: () => ref.read(downloadServiceProvider).retryAll(),
                ),
              ],
            ),
            WingsSettingsGroup(
              title: l10n.settingsNotifications,
              children: <Widget>[
                _PermissionTile(),
                WingsSettingsTile(
                  icon: Icons.new_releases_outlined,
                  title: l10n.settingsNotificationsEpisodes,
                  trailing: Switch(
                    value: settings.notifyNewEpisodes,
                    onChanged: (value) => ref
                        .read(settingsProvider.notifier)
                        .update(
                          (current) =>
                              current.copyWith(notifyNewEpisodes: value),
                        ),
                  ),
                ),
                WingsSettingsTile(
                  icon: Icons.download_done_rounded,
                  title: l10n.settingsNotificationsDownloads,
                  trailing: Switch(
                    value: settings.notifyDownloads,
                    onChanged: (value) => ref
                        .read(settingsProvider.notifier)
                        .update(
                          (current) => current.copyWith(notifyDownloads: value),
                        ),
                  ),
                ),
                WingsSettingsTile(
                  icon: Icons.forum_outlined,
                  title: Tr.of(
                    context,
                    ar: 'إشعارات الردود على تعليقاتي',
                    en: 'Replies to my comments',
                  ),
                  trailing: Switch(
                    value: settings.notifyReplies,
                    onChanged: (value) => ref
                        .read(settingsProvider.notifier)
                        .update(
                          (current) => current.copyWith(notifyReplies: value),
                        ),
                  ),
                ),
                WingsSettingsTile(
                  icon: Icons.campaign_outlined,
                  title: l10n.settingsNotificationsGeneral,
                  trailing: Switch(
                    value: settings.notifyGeneral,
                    onChanged: (value) => ref
                        .read(settingsProvider.notifier)
                        .update(
                          (current) => current.copyWith(notifyGeneral: value),
                        ),
                  ),
                ),
              ],
            ),
            WingsSettingsGroup(
              title: l10n.settingsPrivacy,
              children: <Widget>[
                WingsSettingsTile(
                  icon: Icons.cleaning_services_outlined,
                  title: l10n.settingsClearCache,
                  showChevron: true,
                  onTap: () => _clearCache(context, ref),
                ),
                WingsSettingsTile(
                  icon: Icons.manage_search_rounded,
                  title: l10n.settingsClearSearch,
                  showChevron: true,
                  onTap: () => _clearSearch(context, ref),
                ),
                WingsSettingsTile(
                  icon: Icons.history_rounded,
                  title: l10n.settingsClearHistory,
                  showChevron: true,
                  onTap: () => _clearHistory(context, ref),
                ),
                WingsSettingsTile(
                  icon: Icons.shield_outlined,
                  title: l10n.settingsPrivacyPolicy,
                  showChevron: true,
                  onTap: () => context.push(RoutePaths.legal('privacy')),
                ),
              ],
            ),
            WingsSettingsGroup(
              title: l10n.settingsAbout,
              children: <Widget>[
                WingsSettingsTile(
                  icon: Icons.info_outline_rounded,
                  title: l10n.settingsAbout,
                  subtitle:
                      '${l10n.settingsVersion} ${info?.version ?? '1.0.0'}',
                  showChevron: true,
                  onTap: () => context.push(RoutePaths.about),
                ),
                WingsSettingsTile(
                  icon: Icons.description_outlined,
                  title: l10n.settingsTerms,
                  showChevron: true,
                  onTap: () => context.push(RoutePaths.legal('terms')),
                ),
                WingsSettingsTile(
                  icon: Icons.share_outlined,
                  title: Tr.of(
                    context,
                    ar: 'مشاركة التطبيق',
                    en: 'Share the app',
                  ),
                  showChevron: true,
                  onTap: () => ref
                      .read(shareServiceProvider)
                      .shareText(
                        Tr.of(
                          context,
                          ar: 'جرّب Wings لمشاهدة الأنمي — تطبيق خفيف وأنيق.',
                          en: 'Try Wings for watching anime — a light, polished app.',
                        ),
                        subject: 'Wings',
                      ),
                ),
                if (user != null)
                  WingsSettingsTile(
                    icon: Icons.logout_rounded,
                    title: l10n.settingsSignOut,
                    destructive: true,
                    onTap: () async {
                      final confirmed = await WingsDialog.confirm(
                        context,
                        title: l10n.settingsSignOut,
                        message: Tr.of(
                          context,
                          ar: 'سيتم تسجيل الخروج من هذا الجهاز. مكتبتك وإعداداتك المزامنة تبقى محفوظة.',
                          en: 'You will be signed out of this device. Your synced library and settings stay safe.',
                        ),
                        confirmLabel: l10n.settingsSignOut,
                        destructive: true,
                      );
                      if (!confirmed) return;
                      await ref.read(authProvider.notifier).signOut();
                      if (context.mounted) context.go(RoutePaths.welcome);
                    },
                  ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                Space.lg,
                Space.xl,
                Space.lg,
                0,
              ),
              child: Center(
                child: Column(
                  children: <Widget>[
                    const WingsMark(size: 34, opacity: 0.7),
                    const SizedBox(height: Space.xs),
                    Text(
                      'Wings · ${info?.version ?? '1.0.0'}+${info?.buildNumber ?? '1'}',
                      style: context.text.labelSmall?.copyWith(
                        color: palette.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _themeLabel(BuildContext context, ThemeMode mode) {
    final l10n = AppLocalizations.of(context);
    return switch (mode) {
      ThemeMode.system => l10n.settingsThemeSystem,
      ThemeMode.light => l10n.settingsThemeLight,
      ThemeMode.dark => l10n.settingsThemeDark,
    };
  }

  Future<void> _pickTheme(
    BuildContext context,
    WidgetRef ref,
    ThemeMode current,
  ) async {
    final l10n = AppLocalizations.of(context);
    await WingsSheet.show<void>(
      context,
      title: l10n.settingsTheme,
      builder: (sheetContext) => Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          for (final mode in ThemeMode.values)
            WingsSettingsTile(
              title: _themeLabel(sheetContext, mode),
              trailing: current == mode
                  ? Icon(
                      Icons.check_rounded,
                      size: 18,
                      color: sheetContext.palette.primary,
                    )
                  : null,
              onTap: () async {
                await ref.read(settingsProvider.notifier).setThemeMode(mode);
                if (sheetContext.mounted) Navigator.of(sheetContext).pop();
              },
            ),
        ],
      ),
    );
  }

  Future<void> _pickLanguage(
    BuildContext context,
    WidgetRef ref,
    String current,
  ) async {
    final l10n = AppLocalizations.of(context);
    await WingsSheet.show<void>(
      context,
      title: l10n.settingsLanguage,
      builder: (sheetContext) => Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          for (final code in const <String>['ar', 'en'])
            WingsSettingsTile(
              title: code == 'ar' ? l10n.settingsArabic : l10n.settingsEnglish,
              trailing: current == code
                  ? Icon(
                      Icons.check_rounded,
                      size: 18,
                      color: sheetContext.palette.primary,
                    )
                  : null,
              onTap: () async {
                await ref.read(settingsProvider.notifier).setLocale(code);
                if (sheetContext.mounted) Navigator.of(sheetContext).pop();
              },
            ),
        ],
      ),
    );
  }

  Future<void> _pickSpeed(
    BuildContext context,
    WidgetRef ref,
    double current,
  ) async {
    final l10n = AppLocalizations.of(context);
    await WingsSheet.show<void>(
      context,
      title: l10n.settingsDefaultSpeed,
      builder: (sheetContext) => Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          for (final speed in const <double>[0.75, 1, 1.25, 1.5, 2])
            WingsSettingsTile(
              title: '$speed×',
              trailing: current == speed
                  ? Icon(
                      Icons.check_rounded,
                      size: 18,
                      color: sheetContext.palette.primary,
                    )
                  : null,
              onTap: () async {
                await ref
                    .read(settingsProvider.notifier)
                    .update(
                      (settings) => settings.copyWith(playbackSpeed: speed),
                    );
                if (sheetContext.mounted) Navigator.of(sheetContext).pop();
              },
            ),
        ],
      ),
    );
  }

  Future<void> _pickQuality(
    BuildContext context,
    WidgetRef ref,
    String current,
  ) async {
    final l10n = AppLocalizations.of(context);
    await WingsSheet.show<void>(
      context,
      title: l10n.settingsDefaultQuality,
      builder: (sheetContext) => Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          for (final quality in const <String>['1080p', '720p', '480p', '360p'])
            WingsSettingsTile(
              title: quality,
              trailing: current == quality
                  ? Icon(
                      Icons.check_rounded,
                      size: 18,
                      color: sheetContext.palette.primary,
                    )
                  : null,
              onTap: () async {
                await ref
                    .read(settingsProvider.notifier)
                    .update(
                      (settings) =>
                          settings.copyWith(preferredQuality: quality),
                    );
                if (sheetContext.mounted) Navigator.of(sheetContext).pop();
              },
            ),
        ],
      ),
    );
  }

  Future<void> _clearCache(BuildContext context, WidgetRef ref) async {
    final l10n = AppLocalizations.of(context);
    ref.read(localStoreProvider).clear(LocalStore.cacheBox);
    PaintingBinding.instance.imageCache
      ..clear()
      ..clearLiveImages();
    if (context.mounted) context.showSnack(l10n.settingsCacheCleared);
  }

  Future<void> _clearSearch(BuildContext context, WidgetRef ref) async {
    final l10n = AppLocalizations.of(context);
    await ref.read(libraryProvider.notifier).clearSearchHistory();
    if (context.mounted) context.showSnack(l10n.settingsSearchCleared);
  }

  Future<void> _clearHistory(BuildContext context, WidgetRef ref) async {
    final l10n = AppLocalizations.of(context);
    final confirmed = await WingsDialog.confirm(
      context,
      title: l10n.settingsConfirmClearTitle,
      message: l10n.libraryClearHistoryBody,
      confirmLabel: l10n.commonClear,
      destructive: true,
    );
    if (!confirmed) return;
    await ref.read(libraryProvider.notifier).clearHistory();
    if (context.mounted) context.showSnack(l10n.settingsHistoryCleared);
  }
}

/// Account summary at the top of settings.
///
/// Replaces the old gradient banner with a calm card that matches the settings
/// groups: the real avatar (or initials), the name, the handle, the email and a
/// single chevron. Nothing is truncated to the point of looking broken, and the
/// row keeps a 56 px target so the photo is readable.
class _AccountCard extends StatelessWidget {
  const _AccountCard({
    required this.name,
    required this.email,
    required this.uid,
    required this.photoVersion,
    required this.subtitle,
    required this.onTap,
  });

  final String name;
  final String email;
  final String uid;
  final int photoVersion;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Material(
      color: palette.surface,
      borderRadius: BorderRadius.circular(Radii.md),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(Radii.md),
        child: Container(
          padding: const EdgeInsets.all(Space.md),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(Radii.md),
            border: Border.all(color: palette.border),
          ),
          child: Row(
            children: <Widget>[
              UserAvatar(
                uid: uid,
                photoVersion: photoVersion,
                name: name,
                size: 56,
              ),
              const SizedBox(width: Space.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: context.text.titleSmall,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: context.text.labelSmall?.copyWith(
                        color: palette.primary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (email.isNotEmpty) ...<Widget>[
                      const SizedBox(height: 2),
                      Text(
                        email,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: context.text.labelSmall?.copyWith(
                          color: palette.textMuted,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: Space.sm),
              Icon(
                context.isRtl
                    ? Icons.chevron_left_rounded
                    : Icons.chevron_right_rounded,
                size: 18,
                color: palette.textMuted,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PermissionTile extends ConsumerStatefulWidget {
  const _PermissionTile();

  @override
  ConsumerState<_PermissionTile> createState() => _PermissionTileState();
}

class _PermissionTileState extends ConsumerState<_PermissionTile> {
  bool? _granted;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final granted = await ref
        .read(notificationServiceProvider)
        .isPermissionGranted();
    if (mounted) setState(() => _granted = granted);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return WingsSettingsTile(
      icon: Icons.notifications_active_outlined,
      title: l10n.settingsPermission,
      subtitle: _granted == null
          ? l10n.commonLoading
          : (_granted!
                ? l10n.settingsPermissionGranted
                : l10n.settingsPermissionDenied),
      trailing: _granted == true
          ? Icon(
              Icons.check_circle_rounded,
              size: 18,
              color: context.palette.success,
            )
          : Icon(
              context.isRtl
                  ? Icons.chevron_left_rounded
                  : Icons.chevron_right_rounded,
              size: 18,
            ),
      onTap: _granted == true
          ? null
          : () async {
              final granted = await ref
                  .read(notificationServiceProvider)
                  .requestPermission();
              if (!mounted) return;
              if (!granted) {
                // Permanently denied: the OS dialog never appears again, so the
                // only useful action is opening the app's settings page.
                await ref
                    .read(permissionServiceProvider)
                    .openNotificationSettings();
                if (!mounted) return;
                final now = await ref
                    .read(notificationServiceProvider)
                    .isPermissionGranted();
                if (mounted) setState(() => _granted = now);
                return;
              }
              setState(() => _granted = granted);
            },
    );
  }
}
