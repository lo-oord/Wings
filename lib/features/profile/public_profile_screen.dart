import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/localization/app_localizations.dart';
import '../../app/providers.dart';
import '../../app/theme/app_tokens.dart';
import '../../app/theme/context_ext.dart';
import '../../core/utils/tr.dart';
import '../../core/widgets/wings_layout.dart';
import '../../data/models/user_profile.dart';
import '../social/username_text.dart';
import 'avatar_view.dart';

/// Profile of another user.
///
/// Everything here comes from `profiles/{uid}`, the public mirror that only
/// contains fields its owner allowed. Nothing private can be read and then
/// hidden: the fields are simply absent.
class PublicProfileScreen extends ConsumerWidget {
  const PublicProfileScreen({super.key, required this.uid});

  final String uid;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final palette = context.palette;
    final profile = ref.watch(publicProfileProvider(uid));

    return Scaffold(
      appBar: WingsAppBar(showBack: true, title: Text(l10n.profileTitle)),
      body: profile.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stack) => Center(
          child: Padding(
            padding: const EdgeInsets.all(Space.lg),
            child: Text(
              Tr.of(
                context,
                ar: 'تعذر تحميل الملف الشخصي.',
                en: 'Could not load this profile.',
              ),
              style: context.text.bodyMedium?.copyWith(
                color: palette.textSecondary,
              ),
            ),
          ),
        ),
        data: (value) => value == null
            ? Center(
                child: Text(
                  Tr.of(
                    context,
                    ar: 'هذا الملف غير موجود أو خاص.',
                    en: 'This profile does not exist or is private.',
                  ),
                  style: context.text.bodyMedium,
                ),
              )
            : _Body(profile: value),
      ),
    );
  }
}

class _Body extends StatelessWidget {
  const _Body({required this.profile});

  final UserProfile profile;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final stats = profile.stats;

    return ListView(
      padding: const EdgeInsets.only(bottom: Space.xxl),
      children: <Widget>[
        // Cover
        Container(
          height: 132,
          margin: const EdgeInsets.fromLTRB(Space.md, 0, Space.md, 0),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(Radii.md),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: <Color>[
                palette.primary.withValues(alpha: 0.85),
                palette.primary.withValues(alpha: 0.35),
              ],
            ),
          ),
        ),
        Transform.translate(
          offset: const Offset(0, -34),
          child: Column(
            children: <Widget>[
              Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: palette.background, width: 3),
                ),
                child: UserAvatar(
                  uid: profile.uid,
                  photoVersion: profile.photoVersion,
                  name: profile.displayName,
                  size: 84,
                ),
              ),
              const SizedBox(height: Space.sm),
              UsernameText(
                username: profile.username,
                badges: profile.badges,
                style: context.text.labelMedium,
              ),
              const SizedBox(height: 2),
              Text(
                profile.displayName.isEmpty
                    ? profile.username
                    : profile.displayName,
                style: context.text.titleLarge,
                textAlign: TextAlign.center,
              ),
              if (profile.bio.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    Space.xl,
                    Space.xs,
                    Space.xl,
                    0,
                  ),
                  child: Text(
                    profile.bio,
                    textAlign: TextAlign.center,
                    style: context.text.bodySmall?.copyWith(
                      color: palette.textSecondary,
                      height: 1.6,
                    ),
                  ),
                ),
              const SizedBox(height: Space.md),
              Wrap(
                spacing: Space.sm,
                runSpacing: Space.xs,
                alignment: WrapAlignment.center,
                children: <Widget>[
                  if (profile.country.isNotEmpty)
                    _Pill(icon: Icons.public_rounded, label: profile.country),
                  if (profile.ageGroup.isNotEmpty)
                    _Pill(icon: Icons.cake_outlined, label: profile.ageGroup),
                ],
              ),
              const SizedBox(height: Space.lg),
              if (stats.animeWatched > 0 ||
                  stats.episodesWatched > 0 ||
                  stats.favorites > 0)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: Space.lg),
                  child: Row(
                    children: <Widget>[
                      _Stat(
                        label: Tr.of(
                          context,
                          ar: 'أنمي مشاهَد',
                          en: 'Anime watched',
                        ),
                        value: '${stats.animeWatched}',
                      ),
                      _Stat(
                        label: Tr.of(
                          context,
                          ar: 'حلقات مشاهدة',
                          en: 'Episodes watched',
                        ),
                        value: '${stats.episodesWatched}',
                      ),
                      if (profile.privacy.favorites)
                        _Stat(
                          label: Tr.of(context, ar: 'مفضلة', en: 'Favorites'),
                          value: '${stats.favorites}',
                        ),
                    ],
                  ),
                )
              else
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: Space.lg),
                  child: Text(
                    Tr.of(
                      context,
                      ar: 'لم يشارك هذا المستخدم إحصائياته.',
                      en: 'This user does not share statistics.',
                    ),
                    style: context.text.labelSmall?.copyWith(
                      color: palette.textMuted,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: Space.sm + 2,
        vertical: 4,
      ),
      decoration: BoxDecoration(
        color: palette.surfaceAlt,
        borderRadius: BorderRadius.circular(Radii.pill),
        border: Border.all(color: palette.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(icon, size: 12, color: palette.textSecondary),
          const SizedBox(width: 4),
          Text(
            label,
            style: context.text.labelSmall?.copyWith(
              color: palette.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Expanded(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 3),
        padding: const EdgeInsets.symmetric(vertical: Space.sm),
        decoration: BoxDecoration(
          color: palette.surface,
          borderRadius: BorderRadius.circular(Radii.sm),
          border: Border.all(color: palette.border),
        ),
        child: Column(
          children: <Widget>[
            Text(
              value,
              style: context.text.titleMedium?.copyWith(color: palette.primary),
            ),
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
