import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../app/localization/app_localizations.dart';
import '../../app/providers.dart';
import '../../app/router/route_paths.dart';
import '../../app/theme/app_tokens.dart';
import '../../app/theme/context_ext.dart';
import '../../core/utils/formatters.dart';
import '../../core/utils/tr.dart';
import '../../core/widgets/wings_buttons.dart';
import '../../core/widgets/wings_cards.dart';
import '../../core/widgets/wings_layout.dart';
import '../../data/auth/auth_error_text.dart';
import '../../data/models/library.dart';
import '../../data/models/user_profile.dart';
import '../auth/auth_screens.dart' show kCountries;
import '../auth/username_field.dart';
import '../social/username_text.dart';
import 'account_deletion_overlay.dart';
import 'account_security_section.dart';
import 'avatar_view.dart';

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final palette = context.palette;
    final user = ref.watch(authProvider);
    final profile = ref.watch(profileProvider);
    final library = ref.watch(libraryProvider);
    final downloads = ref.watch(downloadTasksProvider);
    final completedDownloads = downloads
        .where((task) => task.status == DownloadStatus.completed)
        .length;

    // Counters are published by LibraryController on every real change, so the
    // profile screen never republishes a second, differently computed set.

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
            padding: const EdgeInsets.fromLTRB(Space.lg, Space.sm, Space.lg, 0),
            child: Stack(
              children: <Widget>[
                UserCover(
                  uid: user?.id ?? '',
                  coverVersion: profile?.coverVersion ?? 0,
                  height: 144,
                ),
                PositionedDirectional(
                  top: Space.sm,
                  end: Space.sm,
                  child: Material(
                    color: Colors.black.withValues(alpha: 0.45),
                    shape: const CircleBorder(),
                    child: InkWell(
                      customBorder: const CircleBorder(),
                      onTap: user == null
                          ? null
                          : () => _coverSheet(context, ref),
                      child: const Padding(
                        padding: EdgeInsets.all(Space.sm),
                        child: Icon(
                          Icons.photo_camera_outlined,
                          size: 18,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(Space.lg),
            child: Row(
              children: <Widget>[
                GestureDetector(
                  onTap: user == null ? null : () => _pickAvatar(context, ref),
                  child: ProfileAvatarFrame(
                    badges: profile?.badges ?? ProfileBadges.none,
                    child: UserAvatar(
                      uid: user?.id ?? '',
                      photoVersion: profile?.photoVersion ?? 0,
                      name: user?.displayName ?? '',
                      size: 72,
                      localPath: null,
                    ),
                  ),
                ),
                const SizedBox(width: Space.lg),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        profile?.displayName.isNotEmpty == true
                            ? profile!.displayName
                            : (user?.displayName ?? l10n.profileGuest),
                        style: context.text.titleLarge,
                      ),
                      if (user != null) ...<Widget>[
                        const SizedBox(height: 2),
                        UsernameText(
                          username: profile?.username ?? user.username,
                          badges: profile?.badges ?? ProfileBadges.none,
                          style: context.text.labelMedium,
                        ),
                        if (profile != null &&
                            (profile.country.isNotEmpty ||
                                profile.ageGroup.isNotEmpty)) ...<Widget>[
                          const SizedBox(height: 2),
                          Wrap(
                            spacing: Space.sm,
                            runSpacing: 2,
                            children: <Widget>[
                              Text(
                                <String>[
                                  if (profile.country.isNotEmpty)
                                    _countryName(profile.country),
                                  if (profile.ageGroup.isNotEmpty)
                                    profile.ageGroup,
                                ].join(' · '),
                                style: context.text.labelSmall?.copyWith(
                                  color: palette.textMuted,
                                ),
                              ),
                            ],
                          ),
                        ],
                        const SizedBox(height: 2),
                        Row(
                          children: <Widget>[
                            Text(
                              user.email,
                              style: context.text.bodySmall?.copyWith(
                                color: palette.textMuted,
                              ),
                            ),
                            if (!user.emailVerified) ...<Widget>[
                              const SizedBox(width: Space.xs),
                              GestureDetector(
                                onTap: () => context.push(RoutePaths.verify),
                                child: Text(
                                  Tr.of(
                                    context,
                                    ar: 'غير مؤكد · تحقق',
                                    en: 'Unverified · verify',
                                  ),
                                  style: context.text.labelSmall?.copyWith(
                                    color: palette.warning,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ] else
                        Text(
                          l10n.profileSignInPrompt,
                          style: context.text.bodySmall?.copyWith(
                            color: palette.textMuted,
                          ),
                        ),
                    ],
                  ),
                ),
                if (user != null)
                  WingsIconButton(
                    icon: Icons.edit_outlined,
                    tooltip: Tr.of(context, ar: 'تعديل', en: 'Edit'),
                    onPressed: () => _editProfile(context, ref),
                  ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: Space.lg),
            // Four cards in one row squeezed their labels on small phones, so
            // narrow screens get two balanced rows instead.
            child: LayoutBuilder(
              builder: (context, constraints) {
                final stats = <Widget>[
                  _StatCard(label: l10n.profileFavorites, value: '$favorites'),
                  _StatCard(label: l10n.profileWatching, value: '$watching'),
                  _StatCard(label: l10n.profileCompleted, value: '$completed'),
                  _StatCard(
                    label: l10n.profileDownloads,
                    value: '$completedDownloads',
                  ),
                ];
                Row pair(Iterable<Widget> items) => Row(
                  children: <Widget>[
                    for (final (index, item) in items.indexed) ...<Widget>[
                      if (index > 0) const SizedBox(width: Space.sm),
                      item,
                    ],
                  ],
                );
                if (constraints.maxWidth >= 380) return pair(stats);
                return Column(
                  children: <Widget>[
                    pair(stats.take(2)),
                    const SizedBox(height: Space.sm),
                    pair(stats.skip(2)),
                  ],
                );
              },
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
                  icon: Icons.account_circle_outlined,
                  title: Tr.of(
                    context,
                    ar: 'تغيير الصورة الشخصية',
                    en: 'Change profile picture',
                  ),
                  subtitle: Tr.of(
                    context,
                    ar: 'صورة مربعة تظهر بجانب اسمك',
                    en: 'A square picture next to your name',
                  ),
                  showChevron: true,
                  onTap: () => _pickAvatar(context, ref),
                ),
                WingsSettingsTile(
                  icon: Icons.badge_outlined,
                  title: Tr.of(context, ar: 'تعديل الملف', en: 'Edit profile'),
                  subtitle: Tr.of(
                    context,
                    ar: 'الاسم الظاهر والنبذة',
                    en: 'Display name and bio',
                  ),
                  showChevron: true,
                  onTap: () => _editProfile(context, ref),
                ),
                WingsSettingsTile(
                  icon: Icons.alternate_email_rounded,
                  title: Tr.of(
                    context,
                    ar: 'تغيير اسم المستخدم',
                    en: 'Change username',
                  ),
                  subtitle: _usernameSubtitle(context, profile),
                  showChevron: true,
                  onTap: () => _changeUsername(context, ref),
                ),
                WingsSettingsTile(
                  icon: Icons.wallpaper_outlined,
                  title: Tr.of(context, ar: 'صورة الغلاف', en: 'Cover picture'),
                  subtitle: Tr.of(
                    context,
                    ar: 'بانر أعلى الملف — منفصل عن الصورة الشخصية',
                    en: 'The banner above your profile — separate from the avatar',
                  ),
                  showChevron: true,
                  onTap: () => _coverSheet(context, ref),
                ),
                WingsSettingsTile(
                  icon: Icons.lock_outline_rounded,
                  title: Tr.of(context, ar: 'الخصوصية', en: 'Privacy'),
                  subtitle: Tr.of(
                    context,
                    ar: 'تحكم ما يراه الآخرون',
                    en: 'Control what others see',
                  ),
                  showChevron: true,
                  onTap: () => _privacySheet(context, ref),
                ),
                WingsSettingsTile(
                  icon: Icons.download_done_rounded,
                  title: l10n.settingsDownloads,
                  subtitle: formatBytes(
                    downloads
                        .where(
                          (task) => task.status == DownloadStatus.completed,
                        )
                        .fold<int>(0, (total, task) => total + task.totalBytes),
                  ),
                  showChevron: true,
                  onTap: () => context.push(RoutePaths.downloads),
                ),
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
                    if (!confirmed || !context.mounted) return;
                    await ref.read(authProvider.notifier).signOut();
                    if (!context.mounted) return;
                    if (context.canPop()) context.pop();
                  },
                ),
                WingsSettingsTile(
                  icon: Icons.delete_forever_outlined,
                  title: l10n.profileDeleteAccount,
                  destructive: true,
                  onTap: () => _deleteAccount(context, ref),
                ),
              ],
            ),
            // How this account signs in, and what can still be linked to it.
            const Padding(
              padding: EdgeInsets.only(top: Space.md),
              child: AccountSecuritySection(),
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
            // A full-width 16:9 card made one episode taller than the phone's
            // header; the profile uses the same compact rail as the home feed.
            SizedBox(
              height: 176,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: Space.lg),
                itemCount: history.take(6).length,
                separatorBuilder: (_, _) => const SizedBox(width: Space.md),
                itemBuilder: (context, index) {
                  final entry = history[index];
                  return WingsContinueCard(
                    entry: entry,
                    onTap: () => context.push(
                      RoutePaths.watch(
                        animeId: entry.animeId,
                        episodeId: entry.episodeId,
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _pickAvatar(BuildContext context, WidgetRef ref) async {
    final file = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      maxWidth: 1024,
      imageQuality: 90,
    );
    if (file == null) return;
    try {
      await ref.read(authProvider.notifier).saveAvatar(file.path);
      if (context.mounted) {
        context.showSnack(
          Tr.of(context, ar: 'تم تحديث الصورة', en: 'Picture updated'),
        );
      }
    } on Object catch (error) {
      if (context.mounted) {
        context.showSnack(authErrorText(context, error), isError: true);
      }
    }
  }

  /// Cover actions: pick a new banner or remove the current one. The image is
  /// compressed into Firestore bytes, never uploaded to Storage.
  Future<void> _coverSheet(BuildContext context, WidgetRef ref) async {
    await showModalBottomSheet<void>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.all(Space.lg),
              child: Text(
                Tr.of(context, ar: 'صورة الغلاف', en: 'Cover picture'),
                style: context.text.titleSmall,
              ),
            ),
            WingsSettingsTile(
              icon: Icons.photo_library_outlined,
              title: Tr.of(
                context,
                ar: 'اختيار غلاف جديد',
                en: 'Choose a new cover',
              ),
              onTap: () async {
                Navigator.of(sheetContext).pop();
                await _pickCover(context, ref);
              },
            ),
            WingsSettingsTile(
              icon: Icons.delete_outline_rounded,
              title: Tr.of(context, ar: 'إزالة الغلاف', en: 'Remove cover'),
              destructive: true,
              onTap: () async {
                Navigator.of(sheetContext).pop();
                try {
                  await ref.read(authProvider.notifier).removeCover();
                  if (context.mounted) {
                    context.showSnack(
                      Tr.of(
                        context,
                        ar: 'تمت إزالة الغلاف',
                        en: 'Cover removed',
                      ),
                    );
                  }
                } on Object catch (error) {
                  if (context.mounted) {
                    context.showSnack(
                      authErrorText(context, error),
                      isError: true,
                    );
                  }
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickCover(BuildContext context, WidgetRef ref) async {
    final user = ref.read(authProvider);
    if (user == null) {
      context.push(RoutePaths.login);
      return;
    }
    final file = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      maxWidth: 1600,
      imageQuality: 92,
    );
    if (file == null) return;
    try {
      await ref.read(authProvider.notifier).saveCover(file.path);
      if (context.mounted) {
        context.showSnack(
          Tr.of(context, ar: 'تم تحديث الغلاف', en: 'Cover updated'),
        );
      }
    } on Object catch (error) {
      if (context.mounted) {
        context.showSnack(authErrorText(context, error), isError: true);
      }
    }
  }

  Future<void> _editProfile(BuildContext context, WidgetRef ref) async {
    final profile = ref.read(profileProvider);
    if (profile == null) return;
    final name = TextEditingController(text: profile.displayName);
    final bio = TextEditingController(text: profile.bio);
    var country = profile.country.isEmpty ? 'SA' : profile.country;
    var ageGroup = profile.ageGroup.isEmpty ? '18-24' : profile.ageGroup;
    const ageGroups = <(String, String)>[
      ('under-13', 'أقل من 13'),
      ('13-17', '13 - 17'),
      ('18-24', '18 - 24'),
      ('25-34', '25 - 34'),
      ('35+', '35+'),
    ];
    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(Tr.of(context, ar: 'تعديل الملف', en: 'Edit profile')),
        content: SingleChildScrollView(
          child: StatefulBuilder(
            builder: (dialogContext, setDialogState) => Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                TextField(
                  controller: name,
                  maxLength: 40,
                  decoration: InputDecoration(
                    labelText: Tr.of(
                      context,
                      ar: 'الاسم الظاهر',
                      en: 'Display name',
                    ),
                  ),
                ),
                TextField(
                  controller: bio,
                  maxLength: 300,
                  maxLines: 3,
                  decoration: InputDecoration(
                    labelText: Tr.of(context, ar: 'نبذة', en: 'Bio'),
                  ),
                ),
                const SizedBox(height: Space.sm),
                DropdownButtonFormField<String>(
                  initialValue: country,
                  isExpanded: true,
                  decoration: InputDecoration(
                    labelText: Tr.of(context, ar: 'الدولة', en: 'Country'),
                    prefixIcon: const Icon(Icons.public_rounded, size: 18),
                  ),
                  items: <DropdownMenuItem<String>>[
                    for (final item in kCountries)
                      DropdownMenuItem<String>(
                        value: item.$1,
                        child: Text(item.$2),
                      ),
                  ],
                  onChanged: (value) {
                    if (value != null) setDialogState(() => country = value);
                  },
                ),
                const SizedBox(height: Space.sm),
                DropdownButtonFormField<String>(
                  initialValue: ageGroup,
                  isExpanded: true,
                  decoration: InputDecoration(
                    labelText: Tr.of(
                      context,
                      ar: 'الفئة العمرية',
                      en: 'Age group',
                    ),
                    prefixIcon: const Icon(Icons.cake_outlined, size: 18),
                  ),
                  items: <DropdownMenuItem<String>>[
                    for (final item in ageGroups)
                      DropdownMenuItem<String>(
                        value: item.$1,
                        child: Text(item.$2),
                      ),
                  ],
                  onChanged: (value) {
                    if (value != null) setDialogState(() => ageGroup = value);
                  },
                ),
              ],
            ),
          ),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(Tr.of(context, ar: 'إلغاء', en: 'Cancel')),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(Tr.of(context, ar: 'حفظ', en: 'Save')),
          ),
        ],
      ),
    );
    if (saved == true) {
      try {
        await ref
            .read(authProvider.notifier)
            .updateProfile(
              displayName: name.text,
              bio: bio.text,
              country: country,
              ageGroup: ageGroup,
            );
      } on Object catch (error) {
        if (context.mounted) {
          context.showSnack(authErrorText(context, error), isError: true);
        }
      }
    }
    name.dispose();
    bio.dispose();
  }

  /// Either the current handle or, while the 48-hour cooldown runs, how long
  /// until the next change is allowed.
  String _usernameSubtitle(BuildContext context, UserProfile? profile) {
    if (profile == null) return '@';
    final next = profile.nextUsernameChangeAt;
    final label = '@${profile.username}';
    if (next == null) {
      return profile.freeUsernameChanges
          ? Tr.of(
              context,
              ar: '$label · تغيير غير محدود',
              en: '$label · unlimited changes',
            )
          : label;
    }
    final remaining = next.difference(DateTime.now());
    final hours = (remaining.inMinutes / 60).ceil().clamp(1, 48);
    return Tr.of(
      context,
      ar: '$label · التغيير متاح بعد $hours ساعة',
      en: '$label · change available in ${hours}h',
    );
  }

  Future<void> _changeUsername(BuildContext context, WidgetRef ref) async {
    final profile = ref.read(profileProvider);
    if (profile != null && !profile.canChangeUsernameAt(DateTime.now())) {
      final next = profile.nextUsernameChangeAt;
      final remaining = next == null
          ? const Duration(hours: 48)
          : next.difference(DateTime.now());
      final hours = (remaining.inMinutes / 60).ceil().clamp(1, 48);
      context.showSnack(
        Tr.of(
          context,
          ar: 'يمكن تغيير اسم المستخدم مرة كل 48 ساعة. المتاح بعد $hours ساعة.',
          en: 'A username can be changed once every 48 hours. Available in ${hours}h.',
        ),
        isError: true,
      );
      return;
    }
    final controller = TextEditingController(text: profile?.username ?? '');
    var available = false;
    final accepted = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        insetPadding: const EdgeInsets.symmetric(
          horizontal: Space.xl,
          vertical: Space.xxl,
        ),
        title: Text(
          Tr.of(context, ar: 'تغيير اسم المستخدم', en: 'Change username'),
        ),
        content: SizedBox(
          width: 300,
          child: StatefulBuilder(
            builder: (context, setState) => UsernameField(
              controller: controller,
              onAvailabilityChanged: (value) => available = value,
            ),
          ),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(Tr.of(context, ar: 'إلغاء', en: 'Cancel')),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(Tr.of(context, ar: 'حفظ', en: 'Save')),
          ),
        ],
      ),
    );
    if (accepted == true) {
      if (!available) {
        if (context.mounted) {
          context.showSnack(
            Tr.of(
              context,
              ar: 'اختر اسمًا متاحًا أولًا.',
              en: 'Choose an available username first.',
            ),
            isError: true,
          );
        }
      } else {
        try {
          await ref.read(authProvider.notifier).changeUsername(controller.text);
          if (context.mounted) {
            context.showSnack(
              Tr.of(context, ar: 'تم تحديث الاسم', en: 'Username updated'),
            );
          }
        } on Object catch (error) {
          if (context.mounted) {
            context.showSnack(authErrorText(context, error), isError: true);
          }
        }
      }
    }
    controller.dispose();
  }

  Future<void> _privacySheet(BuildContext context, WidgetRef ref) async {
    final profile = ref.read(profileProvider);
    if (profile == null) return;
    var privacy = profile.privacy;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (sheetContext, setState) => SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.all(Space.lg),
                child: Text(
                  Tr.of(context, ar: 'الخصوصية', en: 'Privacy'),
                  style: context.text.titleMedium,
                ),
              ),
              SwitchListTile(
                value: privacy.showProfile,
                title: Text(
                  Tr.of(
                    context,
                    ar: 'إظهار حسابي للآخرين',
                    en: 'Show my profile to others',
                  ),
                ),
                subtitle: Text(
                  Tr.of(
                    context,
                    ar: 'عند الإيقاف يظهر اسمك في التعليقات فقط، بلا بيانات أو إحصائيات.',
                    en: 'When off, only your name appears in comments — no profile details.',
                  ),
                  style: context.text.labelSmall?.copyWith(
                    color: context.palette.textMuted,
                  ),
                ),
                onChanged: (value) => setState(
                  () => privacy = privacy.copyWith(showProfile: value),
                ),
              ),
              SwitchListTile(
                value: privacy.bio,
                title: Text(Tr.of(context, ar: 'إظهار النبذة', en: 'Show bio')),
                onChanged: (value) =>
                    setState(() => privacy = privacy.copyWith(bio: value)),
              ),
              SwitchListTile(
                value: privacy.country,
                title: Text(
                  Tr.of(context, ar: 'إظهار الدولة', en: 'Show country'),
                ),
                onChanged: (value) =>
                    setState(() => privacy = privacy.copyWith(country: value)),
              ),
              SwitchListTile(
                value: privacy.age,
                title: Text(
                  Tr.of(
                    context,
                    ar: 'إظهار الفئة العمرية',
                    en: 'Show age group',
                  ),
                ),
                onChanged: (value) =>
                    setState(() => privacy = privacy.copyWith(age: value)),
              ),
              SwitchListTile(
                value: privacy.stats,
                title: Text(
                  Tr.of(context, ar: 'إظهار الإحصائيات', en: 'Show statistics'),
                ),
                onChanged: (value) =>
                    setState(() => privacy = privacy.copyWith(stats: value)),
              ),
              SwitchListTile(
                value: privacy.favorites,
                title: Text(
                  Tr.of(context, ar: 'إظهار المفضلة', en: 'Show favourites'),
                ),
                subtitle: Text(
                  Tr.of(
                    context,
                    ar: 'تُنشر أسماء الأعمال المفضلة فقط، بلا تقدم أو سجل مشاهدة.',
                    en: 'Only favourite titles are published — never progress or history.',
                  ),
                  style: context.text.labelSmall?.copyWith(
                    color: context.palette.textMuted,
                  ),
                ),
                onChanged: (value) => setState(
                  () => privacy = privacy.copyWith(favorites: value),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(Space.lg),
                child: WingsButton(
                  label: Tr.of(context, ar: 'حفظ', en: 'Save'),
                  expand: true,
                  onPressed: () async {
                    try {
                      await ref
                          .read(authProvider.notifier)
                          .updatePrivacy(privacy);
                      // Re-publish right away so turning a switch on (or off)
                      // changes what other users read without waiting for the
                      // next library change.
                      final library = ref.read(libraryProvider);
                      await ref
                          .read(authProvider.notifier)
                          .publishStats(
                            ProfileStats(
                              animeWatched: library.entries.length,
                              episodesWatched: library.history.length,
                              favorites: library.favorites.length,
                              completed: library
                                  .byStatus(LibraryStatus.completed)
                                  .length,
                            ),
                            favorites: <ProfileFavorite>[
                              for (final entry in library.favorites.take(12))
                                ProfileFavorite(
                                  animeId: entry.anime.id,
                                  title: entry.anime.title,
                                  imageUrl: entry.anime.imageUrl ?? '',
                                ),
                            ],
                          );
                      if (sheetContext.mounted) {
                        Navigator.of(sheetContext).pop();
                      }
                    } on Object catch (error) {
                      if (sheetContext.mounted) {
                        context.showSnack(
                          authErrorText(context, error),
                          isError: true,
                        );
                      }
                    }
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _deleteAccount(BuildContext context, WidgetRef ref) async {
    final l10n = AppLocalizations.of(context);
    final auth = ref.read(authRepositoryProvider);
    final confirmed = await WingsDialog.confirm(
      context,
      title: l10n.profileDeleteAccount,
      message:
          '${l10n.profileDeleteBody}\n\n'
          '${Tr.of(context, ar: 'سيُحذف ملفك وتعليقاتك ومكتبتك وسجل مشاهدتك نهائيًا. الطلب يستغرق بعض الوقت إذا كان لديك محتوى كثير.', en: 'Your profile, comments, library and watch history are removed permanently. The request takes a while when you have a lot of content.')}',
      confirmLabel: l10n.commonDelete,
      destructive: true,
    );
    if (!confirmed) return;
    if (!context.mounted) return;

    String? password;
    if (auth.hasPasswordProvider) {
      final controller = TextEditingController();
      final value = await showDialog<String>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(
            Tr.of(context, ar: 'تأكيد الهوية', en: 'Confirm identity'),
          ),
          content: TextField(
            controller: controller,
            obscureText: true,
            decoration: InputDecoration(
              labelText: Tr.of(
                context,
                ar: 'كلمة المرور الحالية',
                en: 'Current password',
              ),
            ),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: Text(Tr.of(context, ar: 'إلغاء', en: 'Cancel')),
            ),
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(controller.text),
              child: Text(Tr.of(context, ar: 'متابعة', en: 'Continue')),
            ),
          ],
        ),
      );
      controller.dispose();
      if (value == null) return;
      if (value.trim().isEmpty) {
        if (context.mounted) {
          context.showSnack(
            Tr.of(
              context,
              ar: 'أدخل كلمة المرور الحالية للتأكيد.',
              en: 'Enter your current password to confirm.',
            ),
            isError: true,
          );
        }
        return;
      }
      password = value;
    } else {
      // Google-only account: Firebase needs a fresh Google credential, which
      // the app requests right before deleting.
      final proceed = await WingsDialog.confirm(
        context,
        title: Tr.of(context, ar: 'تأكيد هوية جوجل', en: 'Confirm with Google'),
        message: Tr.of(
          context,
          ar: 'ستظهر نافذة جوجل لتأكيد الحساب قبل الحذف. اختر نفس الحساب المسجّل هنا.',
          en: 'Google will ask you to confirm the account before deletion. Pick the same account you are signed in with.',
        ),
        confirmLabel: Tr.of(context, ar: 'متابعة', en: 'Continue'),
        destructive: true,
      );
      if (!proceed || !context.mounted) return;
    }

    // The deletion runs behind a blocking window that reports progress, then
    // shows the green check and «تم الحذف» before fading into the sign-in
    // screen the router redirect has already placed underneath.
    if (!context.mounted) return;
    final error = await showAccountDeletionOverlay(
      context,
      () => ref.read(authProvider.notifier).deleteAccount(password: password),
    );
    if (!context.mounted) return;
    if (error != null) {
      context.showSnack(authErrorText(context, error), isError: true);
    }
  }
}

String _countryName(String code) {
  for (final item in kCountries) {
    if (item.$1 == code) return item.$2;
  }
  return code;
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
