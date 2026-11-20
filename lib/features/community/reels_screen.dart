import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../app/router/route_paths.dart';
import '../../app/theme/app_tokens.dart';
import '../../app/theme/context_ext.dart';
import '../../core/errors/user_facing_error.dart';
import '../../core/utils/formatters.dart';
import '../../core/utils/tr.dart';
import '../../data/models/admin_models.dart' show StaffRole;
import '../../data/models/community.dart';
import '../admin/admin_providers.dart';
import '../profile/avatar_view.dart';
import '../social/user_handle.dart';
import 'community_providers.dart';
import 'community_video.dart';
import 'post_card.dart' show postShareLink;
import 'reels_provider.dart';
import 'report_sheet.dart';
import 'social_text.dart';

/// Full-screen vertical Reels.
///
/// The order is personal: [reelsProvider] ranks a bounded candidate pool with
/// the viewer's library, follow graph, likes and watch log. Exactly one player
/// runs at a time because only the visible page is `active`, and every page
/// disposes its player with the widget.
class ReelsScreen extends ConsumerStatefulWidget {
  const ReelsScreen({super.key});

  @override
  ConsumerState<ReelsScreen> createState() => _ReelsScreenState();
}

class _ReelsScreenState extends ConsumerState<ReelsScreen> {
  final PageController _pages = PageController();
  int _index = 0;

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(reelsProvider);
    final controller = ref.read(reelsProvider.notifier);

    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        bottom: false,
        child: Stack(
          children: <Widget>[
            if (state.loading)
              const Center(child: CircularProgressIndicator(strokeWidth: 2))
            else if (state.error != null && state.posts.isEmpty)
              Center(
                child: Padding(
                  padding: const EdgeInsets.all(Space.xl),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      const Icon(
                        Icons.wifi_off_rounded,
                        color: Colors.white70,
                        size: 28,
                      ),
                      const SizedBox(height: Space.sm),
                      Text(
                        Tr.of(
                          context,
                          ar: 'تعذّر تحميل الريلز. تحقق من اتصالك.',
                          en: 'Reels could not load. Check your connection.',
                        ),
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 12,
                        ),
                      ),
                      const SizedBox(height: Space.sm),
                      OutlinedButton(
                        onPressed: () => controller.load(refresh: true),
                        child: Text(
                          Tr.of(context, ar: 'إعادة المحاولة', en: 'Retry'),
                          style: const TextStyle(color: Colors.white),
                        ),
                      ),
                    ],
                  ),
                ),
              )
            else if (state.posts.isEmpty)
              Center(
                child: Padding(
                  padding: const EdgeInsets.all(Space.xl),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      const Icon(
                        Icons.movie_filter_outlined,
                        color: Colors.white70,
                        size: 30,
                      ),
                      const SizedBox(height: Space.sm),
                      Text(
                        Tr.of(
                          context,
                          ar: 'لا ريلز بعد. كن أول من ينشر مقطعًا.',
                          en: 'No reels yet. Be the first to post one.',
                        ),
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 12,
                        ),
                      ),
                      const SizedBox(height: Space.sm),
                      FilledButton(
                        onPressed: () => context.push(
                          '${RoutePaths.communityCompose}?reel=1',
                        ),
                        child: Text(
                          Tr.of(context, ar: 'إنشاء ريل', en: 'Create a reel'),
                        ),
                      ),
                    ],
                  ),
                ),
              )
            else
              PageView.builder(
                controller: _pages,
                scrollDirection: Axis.vertical,
                allowImplicitScrolling: true,
                itemCount: state.posts.length,
                onPageChanged: (index) {
                  setState(() => _index = index);
                  // One page before the end is enough to fetch the next pool.
                  if (index >= state.posts.length - 2) {
                    unawaited(controller.loadMore());
                  }
                },
                itemBuilder: (context, index) {
                  final post = state.posts[index];
                  // Beyond one page away nothing is built, so at most three
                  // players exist and only the visible one plays.
                  if ((index - _index).abs() > 1) {
                    return const ColoredBox(color: Colors.black);
                  }
                  return ReelPage(
                    key: ValueKey<String>(post.id),
                    post: post,
                    active: index == _index,
                  );
                },
              ),
            PositionedDirectional(
              top: Space.xs,
              start: Space.xs,
              child: _RoundButton(
                icon: context.isRtl
                    ? Icons.arrow_forward_rounded
                    : Icons.arrow_back_rounded,
                onTap: () => Navigator.of(context).maybePop(),
              ),
            ),
            PositionedDirectional(
              top: Space.xs,
              end: Space.sm,
              child: Row(
                children: <Widget>[
                  Text(
                    Tr.of(context, ar: 'ريلز', en: 'Reels'),
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(width: Space.sm),
                  _RoundButton(
                    icon: Icons.add_rounded,
                    onTap: () =>
                        context.push('${RoutePaths.communityCompose}?reel=1'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class ReelPage extends ConsumerStatefulWidget {
  const ReelPage({super.key, required this.post, required this.active});

  final Post post;
  final bool active;

  @override
  ConsumerState<ReelPage> createState() => _ReelPageState();
}

class _ReelPageState extends ConsumerState<ReelPage> {
  String? _url;
  String? _poster;
  bool _failed = false;
  bool? _liked;
  bool? _saved;
  int? _likes;
  int? _views;
  bool? _following;
  bool _busy = false;

  Post get post => widget.post;

  String? get _uid => ref.read(authProvider)?.id;

  @override
  void initState() {
    super.initState();
    unawaited(_resolve());
    Future<void>.microtask(() async {
      final count = await ref
          .read(communityRepositoryProvider)
          .viewCount(post.id);
      if (mounted) setState(() => _views = count);
    });
  }

  Future<void> _resolve() async {
    final service = ref.read(communityMediaProvider);
    final key = post.videoKey;
    if (!service.available || key == null) {
      if (mounted) setState(() => _failed = true);
      return;
    }
    try {
      final urls = await service.downloadUrls(<String>[
        key,
        if ((post.videoThumbnailKey ?? '').isNotEmpty) post.videoThumbnailKey!,
      ]);
      if (!mounted) return;
      setState(() {
        _url = urls[key];
        _poster = urls[post.videoThumbnailKey];
        _failed = (_url ?? '').isEmpty;
      });
    } on Object {
      if (mounted) setState(() => _failed = true);
    }
  }

  Future<void> _countView() async {
    final uid = _uid;
    if (uid == null) return;
    unawaited(ref.read(reelViewsProvider.notifier).markViewed(post.id));
    await ref
        .read(communityRepositoryProvider)
        .recordView(postId: post.id, uid: uid);
    if (!mounted) return;
    setState(() => _views = (_views ?? 0) + 1);
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final uid = ref.watch(authProvider)?.id;
    final likedFromServer = uid == null
        ? false
        : ref.watch(postLikedProvider((postId: post.id, uid: uid))).value ??
              false;
    final savedIds = uid == null
        ? const <String>{}
        : ref.watch(savedPostIdsProvider(uid)).value ?? const <String>{};
    final following = uid == null
        ? const <String>{}
        : ref.watch(followingIdsProvider(uid)).value ?? const <String>{};
    final liked = _liked ?? likedFromServer;
    final saved = _saved ?? savedIds.contains(post.id);
    final follows = _following ?? following.contains(post.authorUid);
    final isMine = uid == post.authorUid;

    return Stack(
      fit: StackFit.expand,
      children: <Widget>[
        ColoredBox(
          color: Colors.black,
          child: _failed
              ? const SizedBox.shrink()
              : _url == null
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      const CircularProgressIndicator(strokeWidth: 2),
                      const SizedBox(height: Space.sm),
                      Text(
                        Tr.of(context, ar: 'جارٍ التحميل…', en: 'Loading…'),
                        style: const TextStyle(
                          color: Colors.white54,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                )
              : CommunityVideo(
                  url: _url,
                  posterUrl: _poster,
                  active: widget.active,
                  loop: true,
                  showChrome: false,
                  fit: BoxFit.contain,
                  aspectRatio: post.videoAspectRatio ?? 9 / 16,
                  onPlayedThreeSeconds: _countView,
                ),
        ),
        if (_failed)
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                const Icon(
                  Icons.videocam_off_outlined,
                  color: Colors.white70,
                  size: 30,
                ),
                const SizedBox(height: Space.sm),
                Text(
                  Tr.of(
                    context,
                    ar: 'هذا الفيديو غير متاح الآن.',
                    en: 'This video is unavailable right now.',
                  ),
                  style: const TextStyle(color: Colors.white70, fontSize: 12),
                ),
                const SizedBox(height: Space.xs),
                OutlinedButton(
                  onPressed: () {
                    setState(() => _failed = false);
                    unawaited(_resolve());
                  },
                  child: Text(
                    Tr.of(context, ar: 'إعادة المحاولة', en: 'Retry'),
                    style: const TextStyle(color: Colors.white),
                  ),
                ),
              ],
            ),
          ),
        // Readability gradient, kept low so the video stays visible.
        IgnorePointer(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: <Color>[
                  Colors.black.withValues(alpha: 0.25),
                  Colors.transparent,
                  Colors.transparent,
                  Colors.black.withValues(alpha: 0.72),
                ],
                stops: const <double>[0, 0.2, 0.55, 1],
              ),
            ),
          ),
        ),
        PositionedDirectional(
          start: Space.md,
          end: 76,
          bottom: Space.lg,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Row(
                children: <Widget>[
                  GestureDetector(
                    onTap: () =>
                        context.push(RoutePaths.publicProfile(post.authorUid)),
                    child: UserAvatar(
                      uid: post.authorUid,
                      photoVersion: post.photoVersion,
                      name: post.authorName,
                      size: 34,
                    ),
                  ),
                  const SizedBox(width: Space.sm),
                  Flexible(
                    child: UserHandle(
                      uid: post.authorUid,
                      username: post.authorUsername,
                      badges: post.badges,
                      onTap: () => context.push(
                        RoutePaths.publicProfile(post.authorUid),
                      ),
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                      ),
                    ),
                  ),
                  if (!isMine && uid != null) ...<Widget>[
                    const SizedBox(width: Space.sm),
                    TextButton(
                      onPressed: _busy ? null : () => _toggleFollow(follows),
                      style: TextButton.styleFrom(
                        minimumSize: Size.zero,
                        padding: const EdgeInsets.symmetric(
                          horizontal: Space.sm,
                          vertical: 2,
                        ),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        side: BorderSide(
                          color: follows
                              ? Colors.white38
                              : palette.primary.withValues(alpha: 0.8),
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(999),
                        ),
                      ),
                      child: Text(
                        follows
                            ? Tr.of(context, ar: 'متابَع', en: 'Following')
                            : Tr.of(context, ar: 'متابعة', en: 'Follow'),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
              if (post.text.trim().isNotEmpty) ...<Widget>[
                const SizedBox(height: Space.sm),
                SocialText(
                  text: post.text,
                  mentions: post.mentions,
                  animeRefs: post.animeRefs,
                  maxLines: 2,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    height: 1.5,
                  ),
                ),
              ],
              if ((_views ?? 0) > 0) ...<Widget>[
                const SizedBox(height: Space.xs),
                Row(
                  children: <Widget>[
                    const Icon(
                      Icons.visibility_outlined,
                      size: 12,
                      color: Colors.white54,
                    ),
                    const SizedBox(width: 3),
                    Text(
                      '${formatCount(_views!)} '
                      '${Tr.of(context, ar: 'مشاهدة', en: 'views')}',
                      style: const TextStyle(
                        color: Colors.white54,
                        fontSize: 10,
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
        PositionedDirectional(
          end: Space.sm,
          bottom: Space.xl,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              _ReelAction(
                icon: liked
                    ? Icons.favorite_rounded
                    : Icons.favorite_border_rounded,
                color: liked ? palette.danger : Colors.white,
                label: formatCount(_likes ?? post.likeCount),
                onTap: () => _toggleLike(liked),
              ),
              _ReelAction(
                icon: Icons.mode_comment_outlined,
                label: formatCount(post.commentCount),
                onTap: () => context.push(RoutePaths.communityPost(post.id)),
              ),
              _ReelAction(
                icon: saved
                    ? Icons.bookmark_rounded
                    : Icons.bookmark_border_rounded,
                color: saved ? palette.primary : Colors.white,
                label: saved
                    ? Tr.of(context, ar: 'محفوظ', en: 'Saved')
                    : Tr.of(context, ar: 'حفظ', en: 'Save'),
                onTap: () => _toggleSaved(saved),
              ),
              _ReelAction(
                icon: Icons.share_outlined,
                label: Tr.of(context, ar: 'مشاركة', en: 'Share'),
                onTap: () => _share(),
              ),
              _ReelAction(
                icon: Icons.more_horiz_rounded,
                label: '',
                onTap: () => _options(isMine),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _toggleLike(bool liked) async {
    final uid = _uid;
    final profile = ref.read(profileProvider);
    if (uid == null || profile == null || _busy) {
      if (uid == null) {
        context.showSnack(
          Tr.of(context, ar: 'سجّل الدخول للإعجاب.', en: 'Sign in to like.'),
        );
      }
      return;
    }
    final next = !liked;
    setState(() {
      _liked = next;
      _likes = ((_likes ?? post.likeCount) + (next ? 1 : -1)).clamp(0, 1 << 31);
    });
    try {
      final result = await ref
          .read(communityRepositoryProvider)
          .toggleLike(postId: post.id, uid: uid, actor: profile);
      if (!mounted) return;
      setState(() => _liked = result);
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _liked = liked;
        _likes = post.likeCount;
      });
      context.showSnack(userFacingError(context, error), isError: true);
    }
  }

  Future<void> _toggleSaved(bool saved) async {
    final uid = _uid;
    if (uid == null) {
      context.showSnack(
        Tr.of(
          context,
          ar: 'سجّل الدخول لحفظ المحتوى.',
          en: 'Sign in to save posts.',
        ),
      );
      return;
    }
    setState(() => _saved = !saved);
    try {
      await ref
          .read(communityRepositoryProvider)
          .toggleSaved(uid: uid, postId: post.id);
    } on Object catch (error) {
      if (!mounted) return;
      setState(() => _saved = saved);
      context.showSnack(userFacingError(context, error), isError: true);
    }
  }

  Future<void> _toggleFollow(bool following) async {
    final profile = ref.read(profileProvider);
    if (profile == null || _busy) return;
    _busy = true;
    setState(() => _following = !following);
    try {
      await ref
          .read(communityRepositoryProvider)
          .setFollowing(
            actor: profile,
            target: post.authorUid,
            follow: !following,
          );
    } on Object catch (error) {
      if (!mounted) return;
      setState(() => _following = following);
      context.showSnack(userFacingError(context, error), isError: true);
    } finally {
      _busy = false;
    }
  }

  Future<void> _share() async {
    final link = postShareLink(post.id);
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            ListTile(
              leading: const Icon(Icons.link_rounded),
              title: Text(Tr.of(context, ar: 'نسخ الرابط', en: 'Copy link')),
              onTap: () async {
                final messenger = ScaffoldMessenger.of(context);
                final navigator = Navigator.of(context);
                final message = Tr.of(
                  context,
                  ar: 'تم نسخ الرابط.',
                  en: 'Link copied.',
                );
                await Clipboard.setData(ClipboardData(text: link));
                navigator.pop();
                messenger.showSnackBar(SnackBar(content: Text(message)));
              },
            ),
            ListTile(
              leading: const Icon(Icons.ios_share_rounded),
              title: Text(
                Tr.of(context, ar: 'مشاركة عبر التطبيقات', en: 'Share to apps'),
              ),
              onTap: () async {
                Navigator.of(context).pop();
                await ref
                    .read(shareServiceProvider)
                    .shareText(link, subject: post.authorName);
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _options(bool isMine) async {
    final uid = _uid;
    final isStaff =
        (ref.read(staffRoleProvider).value ?? StaffRole.user) != StaffRole.user;
    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            ListTile(
              leading: const Icon(Icons.person_outline_rounded),
              title: Text(Tr.of(context, ar: 'عرض الملف', en: 'View profile')),
              onTap: () => Navigator.of(context).pop('profile'),
            ),
            if (isMine)
              ListTile(
                leading: const Icon(Icons.delete_outline_rounded),
                title: Text(Tr.of(context, ar: 'حذف الريل', en: 'Delete reel')),
                onTap: () => Navigator.of(context).pop('delete'),
              ),
            if (!isMine) ...<Widget>[
              ListTile(
                leading: const Icon(Icons.visibility_off_outlined),
                title: Text(Tr.of(context, ar: 'إخفاء', en: 'Hide')),
                onTap: () => Navigator.of(context).pop('hide'),
              ),
              ListTile(
                leading: const Icon(Icons.flag_outlined),
                title: Text(Tr.of(context, ar: 'إبلاغ', en: 'Report')),
                onTap: () => Navigator.of(context).pop('report'),
              ),
              ListTile(
                leading: const Icon(Icons.block_rounded),
                title: Text(Tr.of(context, ar: 'حظر', en: 'Block')),
                onTap: () => Navigator.of(context).pop('block'),
              ),
            ],
            if (isStaff && !isMine)
              ListTile(
                leading: const Icon(Icons.gavel_rounded),
                title: Text(
                  Tr.of(context, ar: 'إزالة (إدارة)', en: 'Remove (staff)'),
                ),
                onTap: () => Navigator.of(context).pop('staff'),
              ),
          ],
        ),
      ),
    );
    if (action == null || !mounted) return;
    if (uid == null) return;
    try {
      switch (action) {
        case 'profile':
          context.push(RoutePaths.publicProfile(post.authorUid));
        case 'delete':
          await ref
              .read(communityRepositoryProvider)
              .deletePost(postId: post.id, uid: uid);
          final keys = <String>[
            if (post.hasVideo) post.videoKey!,
            if ((post.videoThumbnailKey ?? '').isNotEmpty)
              post.videoThumbnailKey!,
          ];
          if (keys.isNotEmpty) {
            await ref.read(communityMediaProvider).deleteObjects(keys);
          }
          ref.read(reelsProvider.notifier).rerank();
          if (mounted) Navigator.of(context).maybePop();
        case 'hide':
          await ref
              .read(communityRepositoryProvider)
              .hidePost(uid: uid, postId: post.id);
          if (mounted) Navigator.of(context).maybePop();
        case 'report':
          await showReportSheet(
            context,
            ref,
            targetType: 'post',
            targetId: post.id,
            targetUid: post.authorUid,
            preview: post.text,
          );
        case 'block':
          await ref
              .read(communityRepositoryProvider)
              .block(uid: uid, target: post.authorUid);
          if (mounted) Navigator.of(context).maybePop();
        case 'staff':
          await ref.read(communityRepositoryProvider).removeAsStaff(post.id);
          if (mounted) Navigator.of(context).maybePop();
      }
    } on Object catch (error) {
      if (mounted) {
        context.showSnack(userFacingError(context, error), isError: true);
      }
    }
  }
}

class _ReelAction extends StatelessWidget {
  const _ReelAction({
    required this.icon,
    required this.label,
    required this.onTap,
    this.color = Colors.white,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: Space.md),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(Radii.sm),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(icon, color: color, size: 26),
            if (label.isNotEmpty) ...<Widget>[
              const SizedBox(height: 2),
              Text(
                label,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 9,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _RoundButton extends StatelessWidget {
  const _RoundButton({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black45,
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Icon(icon, size: 18, color: Colors.white),
        ),
      ),
    );
  }
}

/// Entry point used by the community screen so the route stays in one place.
Future<void> openReels(BuildContext context) =>
    context.push(RoutePaths.communityReels);
