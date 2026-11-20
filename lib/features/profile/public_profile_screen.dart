import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/localization/app_localizations.dart';
import '../../app/providers.dart';
import '../../app/router/route_paths.dart';
import '../../app/theme/app_tokens.dart';
import '../../app/theme/context_ext.dart';
import '../../core/errors/user_facing_error.dart';
import '../../core/utils/tr.dart';
import '../../core/widgets/wings_feedback.dart';
import '../../core/widgets/wings_image.dart';
import '../../core/widgets/wings_layout.dart';
import '../../data/models/admin_models.dart' show StaffRole;
import '../../data/models/user_profile.dart';
import '../../data/models/community.dart';
import '../admin/admin_providers.dart';
import '../community/community_providers.dart';
import '../community/post_card.dart';
import '../community/report_sheet.dart';
import '../social/username_text.dart';
import 'avatar_view.dart';

/// Staff may open a private profile: the private account document is readable
/// for them, and the Owner's access is recorded by the admin screen.
final _staffProfileProvider = FutureProvider.autoDispose
    .family<UserProfile?, String>((ref, uid) async {
      final role = await ref.watch(staffRoleProvider.future);
      if (role == StaffRole.user) return null;
      return ref.watch(userRepositoryProvider).fetch(uid);
    });

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
    final isStaff =
        (ref.watch(staffRoleProvider).value ?? StaffRole.user) !=
        StaffRole.user;
    final revealed = ref.watch(_staffProfileProvider(uid)).value;

    final viewerUid = ref.watch(authProvider)?.id;
    final canModerate = viewerUid != null && viewerUid != uid;

    return Scaffold(
      appBar: WingsAppBar(
        showBack: true,
        title: Text(l10n.profileTitle),
        actions: canModerate
            ? <Widget>[
                PopupMenuButton<String>(
                  icon: Icon(
                    Icons.more_horiz_rounded,
                    size: 20,
                    color: palette.textMuted,
                  ),
                  onSelected: (value) => _profileMenu(context, ref, value),
                  itemBuilder: (context) => <PopupMenuEntry<String>>[
                    PopupMenuItem<String>(
                      value: 'report',
                      child: Text(
                        Tr.of(
                          context,
                          ar: 'إبلاغ عن الحساب',
                          en: 'Report account',
                        ),
                      ),
                    ),
                    PopupMenuItem<String>(
                      value: 'block',
                      child: Text(
                        Tr.of(context, ar: 'حظر المستخدم', en: 'Block user'),
                      ),
                    ),
                  ],
                ),
              ]
            : null,
      ),
      body: profile.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stack) => _Notice(
          icon: Icons.cloud_off_rounded,
          title: Tr.of(
            context,
            ar: 'تعذر تحميل الملف الشخصي',
            en: 'Could not load this profile',
          ),
          body: Tr.of(
            context,
            ar: 'تحقق من اتصالك ثم حاول مرة أخرى.',
            en: 'Check your connection and try again.',
          ),
        ),
        data: (value) =>
            value == null ||
                (value.profileHidden && isStaff && revealed == null)
            ? _Notice(
                icon: Icons.person_off_outlined,
                title: value != null && isStaff
                    ? Tr.of(
                        context,
                        ar: 'جارٍ عرض الملف',
                        en: 'Opening the profile',
                      )
                    : Tr.of(
                        context,
                        ar: 'الحساب غير متاح',
                        en: 'Account unavailable',
                      ),
                body: value != null && isStaff
                    ? Tr.of(context, ar: 'لحظة…', en: 'One moment…')
                    : Tr.of(
                        context,
                        ar: 'هذا الملف لم يعد موجودًا أو أنه خاص.',
                        en: 'This profile no longer exists or is private.',
                      ),
              )
            : value.profileHidden && isStaff
            ? _Body(profile: revealed!, staffView: true)
            : _Body(profile: value),
      ),
      backgroundColor: palette.background,
    );
  }

  Future<void> _profileMenu(
    BuildContext context,
    WidgetRef ref,
    String value,
  ) async {
    final viewer = ref.read(authProvider)?.id;
    if (viewer == null) return;
    if (value == 'report') {
      await showReportSheet(
        context,
        ref,
        targetType: 'user',
        targetId: uid,
        targetUid: uid,
      );
      return;
    }
    final confirmed = await WingsDialog.confirm(
      context,
      title: Tr.of(context, ar: 'حظر المستخدم؟', en: 'Block this user?'),
      message: Tr.of(
        context,
        ar: 'لن ترى منشوراته أو تعليقاته، ولن يستطيع التفاعل معك.',
        en: 'You will not see their posts or comments, and they cannot interact with you.',
      ),
      confirmLabel: Tr.of(context, ar: 'حظر', en: 'Block'),
      destructive: true,
    );
    if (!confirmed || !context.mounted) return;
    try {
      await ref
          .read(communityRepositoryProvider)
          .block(uid: viewer, target: uid);
      if (context.mounted) {
        context.showSnack(Tr.of(context, ar: 'تم الحظر.', en: 'User blocked.'));
      }
    } on Object catch (error) {
      if (context.mounted) {
        context.showSnack(userFacingError(context, error), isError: true);
      }
    }
  }
}

class _Body extends ConsumerWidget {
  const _Body({required this.profile, this.staffView = false});

  final UserProfile profile;

  /// Staff opened a private profile; the content is shown with a clear banner
  /// instead of the lock card.
  final bool staffView;

  bool get _showCommunity => !profile.profileHidden || staffView;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ListView(
      padding: const EdgeInsets.only(bottom: Space.huge),
      children: <Widget>[
        _Hero(profile: profile),
        const SizedBox(height: Space.xl),
        if (staffView) ...<Widget>[
          Container(
            margin: const EdgeInsets.symmetric(horizontal: Space.lg),
            padding: const EdgeInsets.all(Space.md),
            decoration: BoxDecoration(
              color: context.palette.surfaceAlt,
              borderRadius: BorderRadius.circular(Radii.sm),
              border: Border.all(color: context.palette.border),
            ),
            child: Text(
              Tr.of(
                context,
                ar: 'ملف خاص — تعرضه الآن بصلاحية الإدارة.',
                en: 'Private profile — you are viewing it with staff access.',
              ),
              style: context.text.labelSmall?.copyWith(
                color: context.palette.textSecondary,
                height: 1.5,
              ),
            ),
          ),
          const SizedBox(height: Space.lg),
        ],
        if (profile.profileHidden && !staffView)
          const _PrivateCard()
        else ...<Widget>[
          if (profile.bio.isNotEmpty) ...<Widget>[
            _Panel(
              icon: Icons.format_quote_rounded,
              title: Tr.of(context, ar: 'نبذة', en: 'About'),
              child: Text(
                profile.bio,
                style: context.text.bodySmall?.copyWith(
                  color: context.palette.textSecondary,
                  height: 1.75,
                ),
              ),
            ),
            const SizedBox(height: Space.lg),
          ],
          if (_showCommunity) ...<Widget>[
            _CommunityBar(profile: profile),
            const SizedBox(height: Space.lg),
          ],
          _StatsCard(profile: profile),
          if (profile.favorites.isNotEmpty) ...<Widget>[
            const SizedBox(height: Space.xl),
            _FavoritesSection(favorites: profile.favorites),
          ],
          if (_showCommunity) ...<Widget>[
            const SizedBox(height: Space.xl),
            _ProfilePosts(profile: profile),
          ],
        ],
      ],
    );
  }
}

/// Followers / following / posts of the same public profile.
///
/// These numbers are counts over the relationship documents, never a field a
/// client can set, and they open the same [PeopleScreen] the rest of the app
/// uses.
class _CommunityBar extends ConsumerStatefulWidget {
  const _CommunityBar({required this.profile});

  final UserProfile profile;

  @override
  ConsumerState<_CommunityBar> createState() => _CommunityBarState();
}

class _CommunityBarState extends ConsumerState<_CommunityBar> {
  bool? _following;
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final profile = widget.profile;
    final viewer = ref.watch(authProvider)?.id;
    final counts =
        ref.watch(communityCountsProvider(profile.uid)).value ??
        CommunityCounts.zero;
    final followingIds = viewer == null
        ? const <String>{}
        : ref.watch(followingIdsProvider(viewer)).value ?? const <String>{};
    final following = _following ?? followingIds.contains(profile.uid);
    final isMe = viewer == profile.uid;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: Space.lg),
      padding: const EdgeInsets.symmetric(
        horizontal: Space.lg,
        vertical: Space.md,
      ),
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: BorderRadius.circular(Radii.md),
        border: Border.all(color: palette.border),
      ),
      child: Row(
        children: <Widget>[
          Expanded(
            child: _CountTile(
              value: counts.posts,
              label: Tr.of(context, ar: 'منشور', en: 'Posts'),
            ),
          ),
          Container(width: 1, height: 34, color: palette.border),
          Expanded(
            child: InkWell(
              onTap: () => context.push(RoutePaths.followers(profile.uid)),
              child: _CountTile(
                value: counts.followers,
                label: Tr.of(context, ar: 'متابع', en: 'Followers'),
              ),
            ),
          ),
          Container(width: 1, height: 34, color: palette.border),
          Expanded(
            child: InkWell(
              onTap: () => context.push(RoutePaths.following(profile.uid)),
              child: _CountTile(
                value: counts.following,
                label: Tr.of(context, ar: 'يتابع', en: 'Following'),
              ),
            ),
          ),
          if (!isMe && viewer != null) ...<Widget>[
            const SizedBox(width: Space.sm),
            SizedBox(
              height: 34,
              child: FilledButton(
                onPressed: _busy ? null : () => _toggle(following),
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: Space.md),
                  backgroundColor: following
                      ? palette.surfaceHigh
                      : palette.primary,
                  foregroundColor: following
                      ? palette.textPrimary
                      : palette.onPrimary,
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: Text(
                  following
                      ? Tr.of(context, ar: 'متابَع', en: 'Following')
                      : Tr.of(context, ar: 'متابعة', en: 'Follow'),
                  style: context.text.labelSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: following ? palette.textPrimary : palette.onPrimary,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _toggle(bool following) async {
    final actor = ref.read(profileProvider);
    if (actor == null || _busy) return;
    _busy = true;
    setState(() => _following = !following);
    try {
      await ref
          .read(communityRepositoryProvider)
          .setFollowing(
            actor: actor,
            target: widget.profile.uid,
            follow: !following,
          );
      ref.invalidate(communityCountsProvider(widget.profile.uid));
    } on Object catch (error) {
      if (!mounted) return;
      setState(() => _following = following);
      context.showSnack(userFacingError(context, error), isError: true);
    } finally {
      _busy = false;
    }
  }
}

class _CountTile extends StatelessWidget {
  const _CountTile({required this.value, required this.label});

  final int value;
  final String label;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Column(
      children: <Widget>[
        Text(
          '$value',
          style: context.text.titleSmall?.copyWith(
            color: palette.textPrimary,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 1),
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
    );
  }
}

/// The account's latest posts, inside the same public profile page. There is
/// no separate community profile.
class _ProfilePosts extends ConsumerWidget {
  const _ProfilePosts({required this.profile});

  final UserProfile profile;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.palette;
    final posts = ref.watch(profilePostsProvider(profile.uid));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Padding(
          padding: const EdgeInsetsDirectional.fromSTEB(
            Space.lg,
            0,
            Space.lg,
            Space.md,
          ),
          child: Row(
            children: <Widget>[
              Icon(Icons.forum_outlined, size: 17, color: palette.primary),
              const SizedBox(width: 6),
              Text(
                Tr.of(context, ar: 'المنشورات', en: 'Posts'),
                style: context.text.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
        posts.when(
          loading: () => const Padding(
            padding: EdgeInsets.all(Space.lg),
            child: WingsLoading(),
          ),
          error: (error, stack) => Padding(
            padding: const EdgeInsets.symmetric(horizontal: Space.lg),
            child: Text(
              loadFailedText(context),
              style: context.text.labelSmall?.copyWith(
                color: palette.textMuted,
              ),
            ),
          ),
          data: (items) => items.isEmpty
              ? Padding(
                  padding: const EdgeInsets.symmetric(horizontal: Space.lg),
                  child: Text(
                    Tr.of(context, ar: 'لا منشورات بعد.', en: 'No posts yet.'),
                    style: context.text.labelSmall?.copyWith(
                      color: palette.textMuted,
                    ),
                  ),
                )
              : Column(
                  children: <Widget>[
                    for (final post in items)
                      PostCard(
                        post: post,
                        onChanged: (_) =>
                            ref.invalidate(profilePostsProvider(profile.uid)),
                        onDeleted: () =>
                            ref.invalidate(profilePostsProvider(profile.uid)),
                      ),
                  ],
                ),
        ),
      ],
    );
  }
}

/// Cover, avatar, handle, name and the marks that make this account official.
class _Hero extends StatelessWidget {
  const _Hero({required this.profile});

  final UserProfile profile;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final name = profile.displayName.isEmpty
        ? profile.username
        : profile.displayName;
    final meta = <Widget>[
      if (!profile.profileHidden && profile.country.isNotEmpty)
        _Pill(icon: Icons.public_rounded, label: profile.country),
      if (!profile.profileHidden && profile.ageGroup.isNotEmpty)
        _Pill(icon: Icons.cake_outlined, label: profile.ageGroup),
      if (profile.badges.verified)
        _Pill(
          icon: Icons.verified_rounded,
          label: Tr.of(context, ar: 'موثّق', en: 'Verified'),
          color: BrandColors.gold,
        ),
      if (profile.badges.developer)
        _Pill(
          icon: Icons.terminal_rounded,
          label: Tr.of(context, ar: 'مطوّر', en: 'Developer'),
          color: BrandColors.developerBlue,
        ),
    ];

    return Column(
      children: <Widget>[
        SizedBox(
          height: 214,
          child: Stack(
            clipBehavior: Clip.none,
            alignment: Alignment.topCenter,
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: Space.md),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(Radii.lg),
                  child: Stack(
                    children: <Widget>[
                      UserCover(
                        uid: profile.uid,
                        coverVersion: profile.coverVersion,
                        height: 186,
                      ),
                      Positioned.fill(
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: <Color>[
                                Colors.transparent,
                                palette.background.withValues(alpha: 0.55),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              Positioned(
                bottom: 0,
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: palette.background,
                    boxShadow: <BoxShadow>[
                      BoxShadow(
                        color: palette.overlay.withValues(alpha: 0.35),
                        blurRadius: 18,
                        offset: const Offset(0, 6),
                      ),
                    ],
                  ),
                  child: ProfileAvatarFrame(
                    badges: profile.badges,
                    padding: 3,
                    child: UserAvatar(
                      uid: profile.uid,
                      photoVersion: profile.photoVersion,
                      name: name,
                      size: 96,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: Space.xl),
        Text(
          name,
          textAlign: TextAlign.center,
          style: context.text.titleLarge?.copyWith(
            fontWeight: FontWeight.w700,
            color: palette.textPrimary,
          ),
        ),
        const SizedBox(height: Space.xxs),
        UsernameText(
          username: profile.username,
          badges: profile.badges,
          style: context.text.labelMedium,
        ),
        if (meta.isNotEmpty) ...<Widget>[
          const SizedBox(height: Space.md),
          Wrap(
            spacing: Space.sm,
            runSpacing: Space.sm,
            alignment: WrapAlignment.center,
            children: meta,
          ),
        ],
      ],
    );
  }
}

/// Counters the owner agreed to publish, in one card instead of loose numbers.
class _StatsCard extends StatelessWidget {
  const _StatsCard({required this.profile});

  final UserProfile profile;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final stats = profile.stats;
    final tiles = <Widget>[
      if (stats.animeWatched > 0)
        _StatTile(
          icon: Icons.local_movies_outlined,
          value: '${stats.animeWatched}',
          label: Tr.of(context, ar: 'أنمي مشاهَد', en: 'Anime watched'),
        ),
      if (stats.episodesWatched > 0)
        _StatTile(
          icon: Icons.play_circle_outline_rounded,
          value: '${stats.episodesWatched}',
          label: Tr.of(context, ar: 'حلقات مشاهدة', en: 'Episodes watched'),
        ),
      if (profile.privacy.favorites && stats.favorites > 0)
        _StatTile(
          icon: Icons.favorite_border_rounded,
          value: '${stats.favorites}',
          label: Tr.of(context, ar: 'مفضلة', en: 'Favourites'),
        ),
    ];

    return _Panel(
      icon: Icons.insights_rounded,
      title: Tr.of(context, ar: 'الإحصائيات', en: 'Statistics'),
      child: tiles.isEmpty
          ? Row(
              children: <Widget>[
                Icon(
                  Icons.visibility_off_outlined,
                  size: 14,
                  color: palette.textMuted,
                ),
                const SizedBox(width: 6),
                Expanded(
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
            )
          : Row(
              children: <Widget>[
                for (var i = 0; i < tiles.length; i++) ...<Widget>[
                  if (i > 0)
                    Container(width: 1, height: 38, color: palette.border),
                  Expanded(child: tiles[i]),
                ],
              ],
            ),
    );
  }
}

/// Favourite titles the owner chose to publish. Only the title and artwork are
/// shared; progress, history and the rest of the library stay private.
class _FavoritesSection extends StatelessWidget {
  const _FavoritesSection({required this.favorites});

  final List<ProfileFavorite> favorites;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Padding(
          padding: const EdgeInsetsDirectional.only(
            start: Space.lg,
            end: Space.lg,
            bottom: Space.md,
          ),
          child: Row(
            children: <Widget>[
              Icon(
                Icons.bookmark_border_rounded,
                size: 17,
                color: palette.primary,
              ),
              const SizedBox(width: 6),
              Text(
                Tr.of(context, ar: 'المفضلة', en: 'Favourites'),
                style: context.text.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                '${favorites.length}',
                style: context.text.labelSmall?.copyWith(
                  color: palette.textMuted,
                ),
              ),
            ],
          ),
        ),
        SizedBox(
          height: 196,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: Space.lg),
            itemCount: favorites.length,
            separatorBuilder: (context, index) =>
                const SizedBox(width: Space.md),
            itemBuilder: (context, index) {
              final item = favorites[index];
              // A favourite opens its title, so the section is a real shortcut
              // into the work rather than a picture.
              return SizedBox(
                width: 112,
                child: InkWell(
                  borderRadius: BorderRadius.circular(Radii.md),
                  onTap: item.animeId.isEmpty
                      ? null
                      : () => context.push(RoutePaths.anime(item.animeId)),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      ClipRRect(
                        borderRadius: BorderRadius.circular(Radii.md),
                        child: WingsImage(
                          url: item.imageUrl,
                          width: 112,
                          height: 152,
                        ),
                      ),
                      const SizedBox(height: Space.sm),
                      Text(
                        item.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: context.text.labelSmall?.copyWith(
                          color: palette.textSecondary,
                          height: 1.4,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

/// A titled card: the building block of the page.
class _Panel extends StatelessWidget {
  const _Panel({required this.icon, required this.title, required this.child});

  final IconData icon;
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: Space.lg),
      padding: const EdgeInsets.all(Space.lg),
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: BorderRadius.circular(Radii.md),
        border: Border.all(color: palette.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(icon, size: 16, color: palette.primary),
              const SizedBox(width: 6),
              Text(
                title,
                style: context.text.labelMedium?.copyWith(
                  color: palette.textSecondary,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: Space.md),
          child,
        ],
      ),
    );
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile({
    required this.icon,
    required this.value,
    required this.label,
  });

  final IconData icon;
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Column(
      children: <Widget>[
        Icon(icon, size: 16, color: palette.textMuted),
        const SizedBox(height: 6),
        Text(
          value,
          style: context.text.titleLarge?.copyWith(
            color: palette.primary,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: context.text.labelSmall?.copyWith(
            color: palette.textMuted,
            fontSize: 10,
          ),
        ),
      ],
    );
  }
}

class _PrivateCard extends StatelessWidget {
  const _PrivateCard();

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: Space.lg),
      padding: const EdgeInsets.all(Space.xl),
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: BorderRadius.circular(Radii.md),
        border: Border.all(color: palette.border),
      ),
      child: Column(
        children: <Widget>[
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: palette.surfaceAlt,
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.lock_outline_rounded,
              size: 20,
              color: palette.textMuted,
            ),
          ),
          const SizedBox(height: Space.md),
          Text(
            Tr.of(
              context,
              ar: 'هذا المستخدم لا يشارك ملفه',
              en: 'This user keeps their profile private',
            ),
            textAlign: TextAlign.center,
            style: context.text.labelMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: Space.xs),
          Text(
            Tr.of(
              context,
              ar: 'يظهر اسم المستخدم وشاراته فقط، ويمكنك رؤية تعليقاته في الحلقات.',
              en: 'Only the handle and its marks are visible; their comments stay readable on episodes.',
            ),
            textAlign: TextAlign.center,
            style: context.text.bodySmall?.copyWith(
              color: palette.textSecondary,
              height: 1.6,
            ),
          ),
        ],
      ),
    );
  }
}

/// Full-page message for a missing or unreadable profile.
class _Notice extends StatelessWidget {
  const _Notice({required this.icon, required this.title, required this.body});

  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(Space.xxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(icon, size: 34, color: palette.textMuted),
            const SizedBox(height: Space.md),
            Text(
              title,
              textAlign: TextAlign.center,
              style: context.text.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: Space.xs),
            Text(
              body,
              textAlign: TextAlign.center,
              style: context.text.bodySmall?.copyWith(
                color: palette.textSecondary,
                height: 1.6,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.icon, required this.label, this.color});

  final IconData icon;
  final String label;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final tint = color ?? palette.textSecondary;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: Space.sm + 2,
        vertical: 5,
      ),
      decoration: BoxDecoration(
        color: color == null
            ? palette.surfaceAlt
            : color!.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(Radii.pill),
        border: Border.all(
          color: color == null
              ? palette.border
              : color!.withValues(alpha: 0.45),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(icon, size: 12, color: tint),
          const SizedBox(width: 4),
          Text(
            label,
            style: context.text.labelSmall?.copyWith(
              color: tint,
              fontWeight: color == null ? FontWeight.w500 : FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}
