import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';

import '../../app/providers.dart';
import '../../app/router/route_paths.dart';
import '../../app/theme/app_tokens.dart';
import '../../app/theme/context_ext.dart';
import '../../core/errors/user_facing_error.dart';
import '../../core/utils/formatters.dart';
import '../../core/utils/tr.dart';
import '../../data/models/chat.dart';
import '../../data/models/community.dart';
import '../auth/sign_in_prompt.dart';
import '../chat/share_to_chat_sheet.dart';
import '../profile/avatar_view.dart';
import '../social/user_handle.dart';
import 'community_providers.dart';
import 'community_video.dart';
import 'post_card.dart' show postShareLink;
import 'reels_provider.dart';
import 'report_sheet.dart';
import 'social_text.dart';

/// Full-screen vertical Reels, laid out like the video apps members already
/// know: the clip fills the screen, the author and caption sit at the bottom,
/// and likes, comments, sharing, saving and the video settings live in a rail
/// on the side. Exactly one player runs at a time, and the player is disposed
/// with its page.
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
    final uid = ref.watch(authProvider)?.id;

    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        bottom: false,
        child: Stack(
          children: <Widget>[
            if (uid == null)
              _SignedOutReels()
            else if (state.loading && state.posts.isEmpty)
              const Center(child: CircularProgressIndicator(strokeWidth: 2))
            else if (state.error != null && state.posts.isEmpty)
              _ReelsError(
                error: state.error!,
                onRetry: () => controller.load(refresh: true),
              )
            else if (state.posts.isEmpty)
              _EmptyReels(onCreate: _create)
            else
              PageView.builder(
                controller: _pages,
                scrollDirection: Axis.vertical,
                allowImplicitScrolling: true,
                itemCount: state.posts.length,
                onPageChanged: (index) {
                  setState(() => _index = index);
                  if (index >= state.posts.length - 2) {
                    unawaited(controller.loadMore());
                  }
                },
                itemBuilder: (context, index) {
                  final post = state.posts[index];
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
                  _RoundButton(
                    icon: Icons.refresh_rounded,
                    onTap: () => controller.load(refresh: true),
                  ),
                  const SizedBox(width: Space.xs),
                  _RoundButton(
                    icon: Icons.add_rounded,
                    tooltip: Tr.of(context, ar: 'ريل جديد', en: 'New reel'),
                    onTap: _create,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _create() async {
    if (ref.read(authProvider) == null) {
      showSignInPrompt(
        context,
        message: Tr.of(
          context,
          ar: 'سجّل الدخول لنشر ريل.',
          en: 'Sign in to publish a reel.',
        ),
      );
      return;
    }
    final post = await context.push<Post>(RoutePaths.communityReelCompose);
    if (post == null || !mounted) return;
    await ref.read(reelsProvider.notifier).load(refresh: true);
    if (!mounted) return;
    if (_pages.hasClients) _pages.jumpToPage(0);
    setState(() => _index = 0);
    context.showSnack(
      Tr.of(context, ar: 'تم نشر الريل.', en: 'Your reel is live.'),
    );
  }
}

class _SignedOutReels extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(Space.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const Icon(
              Icons.movie_filter_outlined,
              color: Colors.white70,
              size: 34,
            ),
            const SizedBox(height: Space.sm),
            Text(
              Tr.of(
                context,
                ar: 'سجّل الدخول لمشاهدة الريلز والتفاعل معها.',
                en: 'Sign in to watch Reels and interact with them.',
              ),
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white70, fontSize: 12),
            ),
            const SizedBox(height: Space.md),
            FilledButton(
              onPressed: () => showSignInPrompt(
                context,
                message: Tr.of(
                  context,
                  ar: 'حسابك في Wings يفتح الريلز والمجتمع.',
                  en: 'Your Wings account opens Reels and the community.',
                ),
              ),
              child: Text(Tr.of(context, ar: 'تسجيل الدخول', en: 'Sign in')),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyReels extends StatelessWidget {
  const _EmptyReels({required this.onCreate});

  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(Space.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const Icon(
              Icons.movie_filter_outlined,
              color: Colors.white70,
              size: 32,
            ),
            const SizedBox(height: Space.sm),
            Text(
              Tr.of(
                context,
                ar: 'لا ريلز بعد. كن أول من ينشر مقطعًا.',
                en: 'No reels yet. Be the first to post one.',
              ),
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white70, fontSize: 12),
            ),
            const SizedBox(height: Space.md),
            FilledButton.icon(
              onPressed: onCreate,
              icon: const Icon(Icons.add_rounded, size: 18),
              label: Text(Tr.of(context, ar: 'إنشاء ريل', en: 'Create a reel')),
            ),
          ],
        ),
      ),
    );
  }
}

class _ReelsError extends StatelessWidget {
  const _ReelsError({required this.error, required this.onRetry});

  final Object error;
  final VoidCallback onRetry;

  bool get _permission {
    if (error is FirebaseException) {
      final code = (error as FirebaseException).code;
      return code == 'permission-denied' || code == 'unauthenticated';
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(Space.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(
              _permission
                  ? Icons.lock_outline_rounded
                  : Icons.cloud_off_rounded,
              color: Colors.white70,
              size: 30,
            ),
            const SizedBox(height: Space.sm),
            Text(
              _permission
                  ? Tr.of(
                      context,
                      ar: 'تحتاج إلى تسجيل الدخول لعرض الريلز.',
                      en: 'Sign in to see Reels.',
                    )
                  : Tr.of(
                      context,
                      ar: 'تعذّر تحميل الريلز. تحقق من اتصالك ثم أعد المحاولة.',
                      en: 'Reels could not load. Check your connection and retry.',
                    ),
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white70, fontSize: 12),
            ),
            const SizedBox(height: Space.md),
            if (_permission)
              FilledButton(
                onPressed: () => showSignInPrompt(
                  context,
                  message: Tr.of(
                    context,
                    ar: 'سجّل الدخول لمشاهدة الريلز.',
                    en: 'Sign in to watch Reels.',
                  ),
                ),
                child: Text(Tr.of(context, ar: 'تسجيل الدخول', en: 'Sign in')),
              )
            else
              OutlinedButton(
                onPressed: onRetry,
                child: Text(
                  Tr.of(context, ar: 'إعادة المحاولة', en: 'Retry'),
                  style: const TextStyle(color: Colors.white),
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
  double _speed = 1;

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
                  rate: _speed,
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
        IgnorePointer(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: <Color>[
                  Colors.black.withValues(alpha: 0.32),
                  Colors.transparent,
                  Colors.transparent,
                  Colors.black.withValues(alpha: 0.82),
                ],
                stops: const <double>[0, 0.18, 0.52, 1],
              ),
            ),
          ),
        ),
        PositionedDirectional(
          start: Space.md,
          end: 82,
          bottom: MediaQuery.paddingOf(context).bottom + Space.lg,
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
                      size: 36,
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
              if (post.category.isNotEmpty) ...<Widget>[
                const SizedBox(height: Space.xs),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: Space.sm,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    post.category,
                    style: const TextStyle(color: Colors.white70, fontSize: 9),
                  ),
                ),
              ],
              if (post.text.trim().isNotEmpty) ...<Widget>[
                const SizedBox(height: Space.sm),
                SocialText(
                  text: post.text,
                  mentions: post.mentions,
                  animeRefs: post.animeRefs,
                  maxLines: 3,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    height: 1.5,
                  ),
                ),
              ],
              if (post.repostedFrom.isNotEmpty) ...<Widget>[
                const SizedBox(height: 3),
                Text(
                  Tr.of(
                    context,
                    ar: 'أعيد نشره من المجتمع',
                    en: 'Reposted from the community',
                  ),
                  style: const TextStyle(color: Colors.white54, fontSize: 9),
                ),
              ],
              const SizedBox(height: Space.sm),
              Row(
                children: <Widget>[
                  const Icon(
                    Icons.music_note_rounded,
                    size: 12,
                    color: Colors.white70,
                  ),
                  const SizedBox(width: 4),
                  Flexible(
                    child: Text(
                      '${post.soundTitle.isNotEmpty ? post.soundTitle : post.authorName}'
                      ' · ${Tr.of(context, ar: 'الصوت الأصلي', en: 'Original sound')}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 10,
                      ),
                    ),
                  ),
                ],
              ),
              if ((_views ?? 0) > 0) ...<Widget>[
                const SizedBox(height: 3),
                Row(
                  children: <Widget>[
                    const Icon(
                      Icons.visibility_outlined,
                      size: 11,
                      color: Colors.white54,
                    ),
                    const SizedBox(width: 3),
                    Text(
                      '${formatCount(_views!)} '
                      '${Tr.of(context, ar: 'مشاهدة', en: 'views')}',
                      style: const TextStyle(
                        color: Colors.white54,
                        fontSize: 9,
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
          bottom: MediaQuery.paddingOf(context).bottom + Space.xl,
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
                onTap: post.allowComments ? _openComments : null,
              ),
              _ReelAction(
                icon: Icons.ios_share_rounded,
                label: Tr.of(context, ar: 'مشاركة', en: 'Share'),
                onTap: _share,
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
                icon: Icons.tune_rounded,
                label: Tr.of(context, ar: 'الإعدادات', en: 'Settings'),
                onTap: () => _openSettings(isMine),
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
    final shareContext = context;
    final payload = ChatShare(
      kind: ChatShareKind.reel,
      id: post.id,
      title: post.authorName.isNotEmpty
          ? post.authorName
          : '@${post.authorUsername}',
      subtitle: post.text.trim(),
      imageKey: post.videoThumbnailKey ?? '',
      route: RoutePaths.communityPost(post.id),
      extraId: post.authorUid,
    );
    await showModalBottomSheet<void>(
      context: shareContext,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            ListTile(
              leading: const Icon(Icons.chat_bubble_outline_rounded),
              title: Text(
                Tr.of(sheetContext, ar: 'إرسال إلى محادثة', en: 'Send to chat'),
              ),
              onTap: () {
                Navigator.of(sheetContext).pop();
                unawaited(shareToChats(shareContext, ref, payload));
              },
            ),
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
            if (post.allowRepost)
              ListTile(
                leading: const Icon(Icons.repeat_rounded),
                title: Text(
                  Tr.of(context, ar: 'إعادة نشر الريل', en: 'Repost this reel'),
                ),
                onTap: () {
                  Navigator.of(context).pop();
                  unawaited(_repost());
                },
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _openComments() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _CommentsSheet(post: post),
    );
  }

  Future<void> _openSettings(bool isMine) async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => _ReelSettingsSheet(
        post: post,
        speed: _speed,
        onSpeed: (value) {
          Navigator.of(context).pop();
          setState(() => _speed = value);
        },
        onDownload: _download,
        onRepost: _repost,
        onDelete: isMine ? _delete : null,
        onProfile: () => context.push(RoutePaths.publicProfile(post.authorUid)),
        onReport: () => showReportSheet(
          context,
          ref,
          targetType: 'post',
          targetId: post.id,
          targetUid: post.authorUid,
          preview: post.text,
        ),
        onHide: _hide,
        onBlock: _block,
      ),
    );
  }

  Future<void> _download() async {
    if (!post.allowDownload) return;
    final url = _url;
    if (url == null || url.isEmpty) {
      context.showSnack(
        Tr.of(
          context,
          ar: 'الفيديو لم يُحمّل بعد. أعد المحاولة بعد لحظة.',
          en: 'The video is not ready yet. Try again in a moment.',
        ),
      );
      return;
    }
    final progress = ValueNotifier<double?>(null);
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    unawaited(
      showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          title: Text(Tr.of(context, ar: 'تنزيل الريل', en: 'Download reel')),
          content: ValueListenableBuilder<double?>(
            valueListenable: progress,
            builder: (context, value, _) => Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                LinearProgressIndicator(value: value),
                const SizedBox(height: Space.sm),
                Text(
                  value == null
                      ? Tr.of(context, ar: 'جارٍ التنزيل…', en: 'Downloading…')
                      : '${(value * 100).round()}%',
                  style: const TextStyle(fontSize: 11),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    try {
      final file = await ref
          .read(communityMediaProvider)
          .downloadVideo(
            url,
            fileName: 'wings-reel-${post.id}.mp4',
            onProgress: (received, total) {
              if (total > 0) {
                progress.value = (received / total).clamp(0.0, 1.0);
              }
            },
          );
      navigator.pop();
      await SharePlus.instance.share(
        ShareParams(
          files: <XFile>[XFile(file.path, mimeType: 'video/mp4')],
          text: postShareLink(post.id),
          subject: post.authorName,
        ),
      );
    } on Object catch (error) {
      navigator.pop();
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text(userFacingError(context, error))),
      );
    } finally {
      progress.dispose();
    }
  }

  Future<void> _repost() async {
    if (!post.allowRepost) return;
    final profile = ref.read(profileProvider);
    if (profile == null) {
      context.showSnack(
        Tr.of(
          context,
          ar: 'سجّل الدخول لإعادة النشر.',
          en: 'Sign in to repost.',
        ),
      );
      return;
    }
    try {
      await ref
          .read(communityRepositoryProvider)
          .createPost(
            author: profile,
            text: post.text,
            kind: PostKind.reel,
            videoKey: post.videoKey,
            videoThumbnailKey: post.videoThumbnailKey,
            videoDurationMs: post.videoDurationMs,
            videoWidth: post.videoWidth,
            videoHeight: post.videoHeight,
            animeRefs: post.animeRefs,
            allowComments: post.allowComments,
            allowDownload: post.allowDownload,
            allowRepost: post.allowRepost,
            category: post.category,
            soundTitle: post.soundTitle,
            repostedFrom: post.id,
          );
      if (!mounted) return;
      context.showSnack(
        Tr.of(
          context,
          ar: 'تمت إعادة نشر الريل في حسابك.',
          en: 'The reel was reposted to your account.',
        ),
      );
      await ref.read(reelsProvider.notifier).load(refresh: true);
    } on Object catch (error) {
      if (mounted) {
        context.showSnack(userFacingError(context, error), isError: true);
      }
    }
  }

  Future<void> _hide() async {
    final uid = _uid;
    if (uid == null) return;
    try {
      await ref
          .read(communityRepositoryProvider)
          .hidePost(uid: uid, postId: post.id);
      if (mounted) {
        ref.read(reelsProvider.notifier).rerank();
        Navigator.of(context).maybePop();
      }
    } on Object catch (error) {
      if (mounted) {
        context.showSnack(userFacingError(context, error), isError: true);
      }
    }
  }

  Future<void> _block() async {
    final uid = _uid;
    if (uid == null) return;
    try {
      await ref
          .read(communityRepositoryProvider)
          .block(uid: uid, target: post.authorUid);
      if (mounted) {
        ref.read(reelsProvider.notifier).rerank();
        Navigator.of(context).maybePop();
      }
    } on Object catch (error) {
      if (mounted) {
        context.showSnack(userFacingError(context, error), isError: true);
      }
    }
  }

  Future<void> _delete() async {
    final uid = _uid;
    if (uid == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(Tr.of(context, ar: 'حذف الريل؟', en: 'Delete this reel?')),
        content: Text(
          Tr.of(
            context,
            ar: 'سيُحذف الريل وإعجاباته وتعليقاته نهائيًا.',
            en: 'The reel, its likes and its comments will be removed.',
          ),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(context.l10n.commonCancel),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(Tr.of(context, ar: 'حذف', en: 'Delete')),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await ref
          .read(communityRepositoryProvider)
          .deletePost(postId: post.id, uid: uid);
      final keys = <String>[
        if (post.hasVideo) post.videoKey!,
        if ((post.videoThumbnailKey ?? '').isNotEmpty) post.videoThumbnailKey!,
      ];
      if (keys.isNotEmpty) {
        // A repost references the original author's object, which this account
        // may not delete; the Worker refuses it, and that must not turn a
        // successful post deletion into an error.
        try {
          await ref.read(communityMediaProvider).deleteObjects(keys);
        } on Object {
          // Best effort.
        }
      }
      ref.read(reelsProvider.notifier).rerank();
      if (mounted) Navigator.of(context).maybePop();
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
  final VoidCallback? onTap;
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
            Icon(icon, color: onTap == null ? Colors.white38 : color, size: 26),
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
  const _RoundButton({required this.icon, required this.onTap, this.tooltip});

  final IconData icon;
  final VoidCallback onTap;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final button = Material(
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
    return tooltip == null ? button : Tooltip(message: tooltip!, child: button);
  }
}

/// The Reel's own settings: the source quality, playback speed, a real
/// download, and a repost that points at the same object instead of uploading
/// the video twice.
class _ReelSettingsSheet extends StatelessWidget {
  const _ReelSettingsSheet({
    required this.post,
    required this.speed,
    required this.onSpeed,
    required this.onDownload,
    required this.onRepost,
    required this.onDelete,
    required this.onProfile,
    required this.onReport,
    required this.onHide,
    required this.onBlock,
  });

  final Post post;
  final double speed;
  final ValueChanged<double> onSpeed;
  final VoidCallback onDownload;
  final VoidCallback onRepost;
  final VoidCallback? onDelete;
  final VoidCallback onProfile;
  final VoidCallback onReport;
  final VoidCallback onHide;
  final VoidCallback onBlock;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final resolution = post.videoWidth > 0 && post.videoHeight > 0
        ? '${post.videoWidth}×${post.videoHeight}'
        : Tr.of(context, ar: 'الأصلية', en: 'Original');
    return SafeArea(
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Padding(
              padding: const EdgeInsetsDirectional.fromSTEB(
                Space.lg,
                0,
                Space.lg,
                Space.xs,
              ),
              child: Text(
                Tr.of(context, ar: 'إعدادات الريل', en: 'Reel settings'),
                style: context.text.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.hd_outlined),
              title: Text(Tr.of(context, ar: 'الجودة', en: 'Quality')),
              subtitle: Text(
                '${Tr.of(context, ar: 'المصدر المرفوع', en: 'Uploaded source')} · $resolution',
                style: const TextStyle(fontSize: 11),
              ),
              trailing: Chip(
                label: Text(
                  Tr.of(context, ar: 'تلقائي', en: 'Auto'),
                  style: const TextStyle(fontSize: 10),
                ),
                visualDensity: VisualDensity.compact,
                side: BorderSide(color: palette.border),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: Space.lg),
              child: Text(
                Tr.of(
                  context,
                  ar: 'يعرض Wings الجودة المرفوعة كما هي. يتبدّل المقاس تلقائيًا حسب الشاشة والاتصال.',
                  en: 'Wings plays the uploaded quality as-is; size adapts to the screen and connection.',
                ),
                style: context.text.labelSmall?.copyWith(
                  color: palette.textMuted,
                  fontSize: 10,
                  height: 1.5,
                ),
              ),
            ),
            const SizedBox(height: Space.sm),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: Space.lg),
              child: Text(
                Tr.of(context, ar: 'سرعة الفيديو', en: 'Playback speed'),
                style: context.text.labelSmall?.copyWith(
                  color: palette.textSecondary,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                Space.lg,
                Space.xs,
                Space.lg,
                Space.sm,
              ),
              child: Wrap(
                spacing: 6,
                children: <Widget>[
                  for (final value in <double>[0.75, 1, 1.25, 1.5, 2])
                    ChoiceChip(
                      label: Text(value == 1 ? '1×' : '$value×'),
                      selected: speed == value,
                      onSelected: (_) => onSpeed(value),
                      labelStyle: const TextStyle(fontSize: 10),
                      visualDensity: VisualDensity.compact,
                    ),
                ],
              ),
            ),
            if (post.allowDownload)
              ListTile(
                leading: const Icon(Icons.download_outlined),
                title: Text(
                  Tr.of(context, ar: 'تنزيل الفيديو', en: 'Download'),
                ),
                subtitle: Text(
                  Tr.of(
                    context,
                    ar: 'يحفظ نسخة ثم يفتح خيارات المشاركة والحفظ',
                    en: 'Saves a copy, then opens share/save options',
                  ),
                  style: const TextStyle(fontSize: 10),
                ),
                onTap: () {
                  Navigator.of(context).pop();
                  onDownload();
                },
              ),
            if (post.allowRepost)
              ListTile(
                leading: const Icon(Icons.repeat_rounded),
                title: Text(Tr.of(context, ar: 'إعادة النشر', en: 'Repost')),
                subtitle: Text(
                  Tr.of(
                    context,
                    ar: 'ينشر الريل مرة أخرى في حسابك',
                    en: 'Posts the reel again on your account',
                  ),
                  style: const TextStyle(fontSize: 10),
                ),
                onTap: () {
                  Navigator.of(context).pop();
                  onRepost();
                },
              ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.person_outline_rounded),
              title: Text(Tr.of(context, ar: 'عرض الملف', en: 'View profile')),
              onTap: onProfile,
            ),
            if (onDelete != null)
              ListTile(
                leading: Icon(
                  Icons.delete_outline_rounded,
                  color: palette.danger,
                ),
                title: Text(
                  Tr.of(context, ar: 'حذف الريل', en: 'Delete reel'),
                  style: TextStyle(color: palette.danger),
                ),
                onTap: () {
                  Navigator.of(context).pop();
                  onDelete!();
                },
              )
            else ...<Widget>[
              ListTile(
                leading: const Icon(Icons.visibility_off_outlined),
                title: Text(Tr.of(context, ar: 'إخفاء', en: 'Hide')),
                onTap: () {
                  Navigator.of(context).pop();
                  onHide();
                },
              ),
              ListTile(
                leading: const Icon(Icons.flag_outlined),
                title: Text(Tr.of(context, ar: 'إبلاغ', en: 'Report')),
                onTap: () {
                  Navigator.of(context).pop();
                  onReport();
                },
              ),
              ListTile(
                leading: const Icon(Icons.block_rounded),
                title: Text(Tr.of(context, ar: 'حظر', en: 'Block')),
                onTap: () {
                  Navigator.of(context).pop();
                  onBlock();
                },
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Comments under the Reel, in the same bottom sheet pattern as the big video
/// apps. It reads the same comment documents as the rest of Wings.
class _CommentsSheet extends ConsumerStatefulWidget {
  const _CommentsSheet({required this.post});

  final Post post;

  @override
  ConsumerState<_CommentsSheet> createState() => _CommentsSheetState();
}

class _CommentsSheetState extends ConsumerState<_CommentsSheet> {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focus = FocusNode();

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final state = ref.watch(postCommentsProvider(widget.post.id));
    final controller = ref.read(postCommentsProvider(widget.post.id).notifier);
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: Container(
        height: MediaQuery.sizeOf(context).height * 0.78,
        decoration: BoxDecoration(
          color: palette.background,
          borderRadius: const BorderRadius.vertical(
            top: Radius.circular(Radii.xl),
          ),
        ),
        child: Column(
          children: <Widget>[
            Container(
              width: 36,
              height: 4,
              margin: const EdgeInsets.only(top: Space.sm),
              decoration: BoxDecoration(
                color: palette.border,
                borderRadius: BorderRadius.circular(99),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(Space.md),
              child: Text(
                '${Tr.of(context, ar: 'التعليقات', en: 'Comments')} · ${formatCount(widget.post.commentCount)}',
                style: context.text.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            Divider(height: 1, color: palette.border),
            Expanded(
              child: state.loading && state.comments.isEmpty
                  ? const Center(
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : state.comments.isEmpty
                  ? Center(
                      child: Text(
                        state.error == null
                            ? Tr.of(
                                context,
                                ar: 'لا تعليقات بعد. ابدأ النقاش.',
                                en: 'No comments yet. Start the conversation.',
                              )
                            : loadFailedText(context),
                        style: context.text.labelSmall?.copyWith(
                          color: palette.textMuted,
                        ),
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.all(Space.md),
                      itemCount:
                          state.comments.length + (state.hasMore ? 1 : 0),
                      itemBuilder: (context, index) {
                        if (index >= state.comments.length) {
                          unawaited(controller.loadMore());
                          return const Padding(
                            padding: EdgeInsets.all(Space.md),
                            child: Center(
                              child: SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              ),
                            ),
                          );
                        }
                        final comment = state.comments[index];
                        return Padding(
                          padding: const EdgeInsets.only(bottom: Space.md),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              UserAvatar(
                                uid: comment.authorUid,
                                photoVersion: comment.photoVersion,
                                name: comment.authorName,
                                size: 30,
                              ),
                              const SizedBox(width: Space.sm),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: <Widget>[
                                    Row(
                                      children: <Widget>[
                                        Flexible(
                                          child: UserHandle(
                                            uid: comment.authorUid,
                                            username: comment.authorUsername,
                                            badges: comment.badges,
                                            style: context.text.labelSmall
                                                ?.copyWith(
                                                  fontWeight: FontWeight.w700,
                                                ),
                                          ),
                                        ),
                                        const SizedBox(width: 6),
                                        Text(
                                          relativeTime(
                                            comment.createdAt,
                                            context.l10n,
                                          ),
                                          style: context.text.labelSmall
                                              ?.copyWith(
                                                color: palette.textMuted,
                                                fontSize: 9,
                                              ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      comment.text,
                                      style: context.text.bodySmall?.copyWith(
                                        height: 1.5,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
            ),
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                  Space.md,
                  Space.sm,
                  Space.md,
                  Space.sm,
                ),
                child: Row(
                  children: <Widget>[
                    Expanded(
                      child: TextField(
                        controller: _controller,
                        focusNode: _focus,
                        maxLength: 1000,
                        minLines: 1,
                        maxLines: 3,
                        style: context.text.bodySmall,
                        decoration: InputDecoration(
                          hintText: Tr.of(
                            context,
                            ar: 'أضف تعليقًا…',
                            en: 'Add a comment…',
                          ),
                          counterText: '',
                          filled: true,
                          fillColor: palette.surfaceAlt,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: Space.md,
                            vertical: Space.sm,
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(Radii.pill),
                            borderSide: BorderSide.none,
                          ),
                        ),
                        onSubmitted: (_) => _send(controller),
                      ),
                    ),
                    const SizedBox(width: Space.xs),
                    IconButton(
                      onPressed: state.sending ? null : () => _send(controller),
                      icon: state.sending
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Icon(Icons.send_rounded, color: palette.primary),
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

  Future<void> _send(PostCommentsController controller) async {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    final sent = await controller.add(text);
    if (!mounted) return;
    if (sent) {
      _controller.clear();
      _focus.unfocus();
    } else if (ref.read(authProvider) == null) {
      context.showSnack(
        Tr.of(context, ar: 'سجّل الدخول للتعليق.', en: 'Sign in to comment.'),
      );
    } else {
      context.showSnack(
        Tr.of(
          context,
          ar: 'تعذّر إرسال التعليق. تحقق من اتصالك.',
          en: 'The comment could not be sent. Check your connection.',
        ),
        isError: true,
      );
    }
  }
}
