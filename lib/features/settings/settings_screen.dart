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
import '../../core/widgets/wings_image.dart';
import '../../core/widgets/wings_layout.dart';

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
              child: InkWell(
                onTap: () => context.push(
                  user == null ? RoutePaths.welcome : RoutePaths.profile,
                ),
                borderRadius: BorderRadius.circular(Radii.md),
                child: Container(
                  padding: const EdgeInsets.all(Space.md),
                  decoration: BoxDecoration(
                    gradient: palette.brandGradient,
                    borderRadius: BorderRadius.circular(Radii.md),
                  ),
                  child: Row(
                    children: <Widget>[
                      CircleAvatar(
                        radius: 22,
                        backgroundColor: Colors.white24,
                        child: Text(
                          user == null
                              ? 'W'
                              : user.displayName.characters.first.toUpperCase(),
                          style: context.text.titleMedium?.copyWith(
                            color: Colors.white,
                          ),
                        ),
                      ),
                      const SizedBox(width: Space.md),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Text(
                              user?.displayName ?? l10n.settingsGuest,
                              style: context.text.titleSmall?.copyWith(
                                color: Colors.white,
                              ),
                            ),
                            Text(
                              user?.email ?? l10n.profileSignInPrompt,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: context.text.labelSmall?.copyWith(
                                color: Colors.white70,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Icon(
                        context.isRtl
                            ? Icons.chevron_left_rounded
                            : Icons.chevron_right_rounded,
                        color: Colors.white70,
                        size: 20,
                      ),
                    ],
                  ),
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
                if (user != null)
                  WingsSettingsTile(
                    icon: Icons.logout_rounded,
                    title: l10n.settingsSignOut,
                    destructive: true,
                    onTap: () async {
                      await ref.read(authProvider.notifier).signOut();
                      if (context.mounted) {
                        context.showSnack(l10n.settingsSignOut);
                      }
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
          : const Icon(Icons.chevron_right_rounded, size: 18),
      onTap: _granted == true
          ? null
          : () async {
              final granted = await ref
                  .read(notificationServiceProvider)
                  .requestPermission();
              if (mounted) setState(() => _granted = granted);
            },
    );
  }
}
