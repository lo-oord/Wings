import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/localization/app_localizations.dart';
import '../../app/providers.dart';
import '../../app/router/route_paths.dart';
import '../../app/theme/app_tokens.dart';
import '../../app/theme/context_ext.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/wings_buttons.dart';
import '../../core/widgets/wings_cards.dart';
import '../../core/widgets/wings_image.dart';
import '../../core/widgets/wings_layout.dart';
import '../../data/models/library.dart';

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final palette = context.palette;
    final user = ref.watch(authProvider);
    final library = ref.watch(libraryProvider);
    final downloads = ref.watch(downloadTasksProvider);
    final completedDownloads = downloads
        .where((task) => task.status == DownloadStatus.completed)
        .length;

    final favorites = library.favorites.length;
    final completed = library.byStatus(LibraryStatus.completed).length;
    final watching = library.byStatus(LibraryStatus.watching).length;
    final history = library.history;

    return Scaffold(
      appBar: WingsAppBar(showBack: true, title: Text(l10n.profileTitle)),
      body: ListView(
        padding: const EdgeInsets.only(bottom: Space.xxxl),
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.all(Space.lg),
            child: Row(
              children: <Widget>[
                Container(
                  width: 68,
                  height: 68,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: palette.surfaceAlt,
                    border: Border.all(color: palette.border),
                  ),
                  clipBehavior: Clip.antiAlias,
                  alignment: Alignment.center,
                  child: user == null
                      ? const WingsMark(size: 34)
                      : (user.avatarPath != null &&
                                File(user.avatarPath!).existsSync()
                            ? Image.file(
                                File(user.avatarPath!),
                                fit: BoxFit.cover,
                              )
                            : Text(
                                user.displayName.characters.first.toUpperCase(),
                                style: context.text.headlineSmall,
                              )),
                ),
                const SizedBox(width: Space.lg),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        user?.displayName ?? l10n.profileGuest,
                        style: context.text.titleLarge,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        user == null
                            ? l10n.profileSignInPrompt
                            : '@${user.username} · ${user.email}',
                        style: context.text.bodySmall?.copyWith(
                          color: palette.textMuted,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: Space.lg),
            child: Row(
              children: <Widget>[
                _StatCard(label: l10n.profileFavorites, value: '$favorites'),
                const SizedBox(width: Space.sm),
                _StatCard(label: l10n.profileWatching, value: '$watching'),
                const SizedBox(width: Space.sm),
                _StatCard(label: l10n.profileCompleted, value: '$completed'),
                const SizedBox(width: Space.sm),
                _StatCard(
                  label: l10n.profileDownloads,
                  value: '$completedDownloads',
                ),
              ],
            ),
          ),
          const SizedBox(height: Space.lg),
          if (user == null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: Space.lg),
              child: Column(
                children: <Widget>[
                  WingsButton(
                    label: l10n.authLogin,
                    icon: Icons.login_rounded,
                    expand: true,
                    onPressed: () => context.push(RoutePaths.login),
                  ),
                  const SizedBox(height: Space.sm),
                  WingsButton(
                    label: l10n.authRegister,
                    variant: WingsButtonVariant.outline,
                    expand: true,
                    onPressed: () => context.push(RoutePaths.register),
                  ),
                ],
              ),
            ),
          if (user != null) ...<Widget>[
            WingsSettingsGroup(
              title: l10n.settingsAccount,
              children: <Widget>[
                WingsSettingsTile(
                  icon: Icons.download_done_rounded,
                  title: l10n.settingsDownloads,
                  subtitle: formatBytes(
                    downloads
                        .where(
                          (task) => task.status == DownloadStatus.completed,
                        )
                        .fold<int>(0, (sum, task) => sum + task.totalBytes),
                  ),
                  showChevron: true,
                  onTap: () => context.push(RoutePaths.downloads),
                ),
                WingsSettingsTile(
                  icon: Icons.logout_rounded,
                  title: l10n.settingsSignOut,
                  destructive: true,
                  onTap: () async {
                    await ref.read(authProvider.notifier).signOut();
                    if (context.mounted) context.pop();
                  },
                ),
                WingsSettingsTile(
                  icon: Icons.delete_forever_outlined,
                  title: l10n.profileDeleteAccount,
                  destructive: true,
                  onTap: () async {
                    final confirmed = await WingsDialog.confirm(
                      context,
                      title: l10n.profileDeleteAccount,
                      message: l10n.profileDeleteBody,
                      confirmLabel: l10n.commonDelete,
                      destructive: true,
                    );
                    if (!confirmed) return;
                    await ref.read(authProvider.notifier).deleteAccount();
                    if (context.mounted) {
                      context.go(RoutePaths.settings);
                      context.showSnack(l10n.profileDeleteDone);
                    }
                  },
                ),
              ],
            ),
          ],
          WingsSettingsGroup(
            title: l10n.profileStats,
            children: <Widget>[
              WingsSettingsTile(
                icon: Icons.video_library_outlined,
                title: l10n.libraryTitle,
                subtitle: '${library.entries.length}',
                showChevron: true,
                onTap: () => context.go(RoutePaths.library),
              ),
              WingsSettingsTile(
                icon: Icons.history_rounded,
                title: l10n.libraryHistory,
                subtitle: '${history.length}',
                showChevron: true,
                onTap: () => context.go(RoutePaths.library),
              ),
              WingsSettingsTile(
                icon: Icons.notifications_none_rounded,
                title: l10n.notificationsTitle,
                showChevron: true,
                onTap: () => context.push(RoutePaths.notifications),
              ),
            ],
          ),
          if (history.isNotEmpty) ...<Widget>[
            WingsSectionHeader(title: l10n.homeContinueWatching),
            for (final entry in history.take(4))
              WingsContinueCard(
                entry: entry,
                width: double.infinity,
                onTap: () => context.push(
                  RoutePaths.watch(
                    animeId: entry.animeId,
                    episodeId: entry.episodeId,
                  ),
                ),
              ),
          ],
        ],
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(
          vertical: Space.md,
          horizontal: Space.xs,
        ),
        decoration: BoxDecoration(
          color: palette.surface,
          borderRadius: BorderRadius.circular(Radii.sm),
          border: Border.all(color: palette.border),
        ),
        child: Column(
          children: <Widget>[
            Text(
              value,
              style: context.text.titleLarge?.copyWith(color: palette.primary),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: context.text.labelSmall?.copyWith(
                color: palette.textMuted,
                fontSize: 10,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
