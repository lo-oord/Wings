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
import '../../core/widgets/wings_image.dart';
import '../../core/widgets/wings_layout.dart';
import '../../data/models/community.dart';
import '../../data/models/admin_models.dart' show StaffRole;
import '../../data/models/chat.dart';
import '../admin/admin_providers.dart';
import '../admin/owner_guard.dart';
import '../chat/share_to_chat_sheet.dart';
import '../profile/avatar_view.dart';
import '../social/user_handle.dart';
import 'community_providers.dart';
import 'community_video.dart';
import 'report_sheet.dart';
import 'social_text.dart';

/// One post, shared by the feed, the public profile and the saved list so the
/// three can never drift apart.
class PostCard extends ConsumerStatefulWidget {
  const PostCard({
    super.key,
    required this.post,
    this.onChanged,
    this.onDeleted,
    this.showFollow = false,
    this.flat = false,
  });

  final Post post;

  /// Called with the updated post after an edit, like or save.
  final ValueChanged<Post>? onChanged;

  final VoidCallback? onDeleted;

  /// Show a follow button next to the author (used on the community feed).
  final bool showFollow;

  /// Borderless variant used on the profile and the anime feed, where posts are
  /// separated by one hairline divider instead of a box each.
  final bool flat;

  @override
  ConsumerState<PostCard> createState() => _PostCardState();
}

class _PostCardState extends ConsumerState<PostCard> {
  bool? _liked;
  bool? _saved;
  int? _likeCount;
  bool _busyLike = false;
  bool _busySave = false;
  bool _busyFollow = false;
  bool? _following;

  String? get _uid => ref.read(authProvider)?.id;

  bool get _mine => _uid == widget.post.authorUid;

  Post get post => widget.post;

  bool get _isStaff =>
      (ref.watch(staffRoleProvider).value ?? StaffRole.user) != StaffRole.user;

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
    final count = _likeCount ?? post.likeCount;
    final follows = _following ?? following.contains(post.authorUid);

    final card = Container(
      margin: widget.flat
          ? EdgeInsets.zero
          : const EdgeInsets.fromLTRB(Space.lg, 0, Space.lg, Space.md),
      decoration: widget.flat
          ? null
          : BoxDecoration(
              color: palette.surface,
              borderRadius: BorderRadius.circular(Radii.lg),
              border: Border.all(color: palette.border),
              boxShadow: <BoxShadow>[
                BoxShadow(
                  color: palette.overlay.withValues(alpha: 0.05),
                  blurRadius: 14,
                  offset: const Offset(0, 5),
                ),
              ],
            ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(
              Space.md,
              Space.md,
              Space.xs,
              Space.xs,
            ),
            child: Row(
              children: <Widget>[
                GestureDetector(
                  onTap: () =>
                      context.push(RoutePaths.publicProfile(post.authorUid)),
                  child: UserAvatar(
                    uid: post.authorUid,
                    photoVersion: post.photoVersion,
                    name: post.authorName,
                    size: 40,
                  ),
                ),
                const SizedBox(width: Space.sm + 2),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      UserHandle(
                        uid: post.authorUid,
                        username: post.authorUsername,
                        badges: post.badges,
                        onTap: () => context.push(
                          RoutePaths.publicProfile(post.authorUid),
                        ),
                        style: context.text.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Row(
                        children: <Widget>[
                          Text(
                            relativeTime(post.createdAt, context.l10n),
                            style: context.text.labelSmall?.copyWith(
                              color: palette.textMuted,
                              fontSize: 10,
                            ),
                          ),
                          if (post.edited)
                            Text(
                              Tr.of(context, ar: ' · معدّل', en: ' · edited'),
                              style: context.text.labelSmall?.copyWith(
                                color: palette.textMuted,
                                fontSize: 10,
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
                if (widget.showFollow && !_mine && uid != null)
                  _FollowButton(
                    following: follows,
                    busy: _busyFollow,
                    onTap: () => _toggleFollow(follows),
                  ),
                _menu(context, uid),
              ],
            ),
          ),
          if (post.category.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                Space.md,
                Space.sm,
                Space.md,
                0,
              ),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: Space.sm,
                  vertical: 3,
                ),
                decoration: BoxDecoration(
                  color: palette.primary.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(Radii.pill),
                ),
                child: Text(
                  post.category,
                  style: context.text.labelSmall?.copyWith(
                    color: palette.primary,
                    fontWeight: FontWeight.w700,
                    fontSize: 10,
                  ),
                ),
              ),
            ),
          if (post.text.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                Space.md,
                Space.sm,
                Space.md,
                0,
              ),
              child: SocialText(
                text: post.text,
                mentions: post.mentions,
                animeRefs: post.animeRefs,
                style: context.text.bodyMedium?.copyWith(height: 1.7),
              ),
            ),
          if (post.animeRefs.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                Space.md,
                Space.sm,
                Space.md,
                0,
              ),
              child: Wrap(
                spacing: 6,
                runSpacing: 6,
                children: <Widget>[
                  for (final anime in post.animeRefs.take(3))
                    InkWell(
                      onTap: () => context.push(RoutePaths.anime(anime.id)),
                      borderRadius: BorderRadius.circular(Radii.pill),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: Space.sm,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: palette.surfaceAlt,
                          borderRadius: BorderRadius.circular(Radii.pill),
                          border: Border.all(color: palette.border),
                        ),
                        child: Text(
                          '#${anime.title}',
                          style: context.text.labelSmall?.copyWith(
                            color: palette.textSecondary,
                            fontSize: 10,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          if (post.hasVideo)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                Space.md,
                Space.sm + 2,
                Space.md,
                0,
              ),
              child: _PostVideo(post: post),
            ),
          if (post.hasImages)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                Space.md,
                Space.sm + 2,
                Space.md,
                0,
              ),
              child: _PostImages(post: post),
            ),
          Container(
            margin: const EdgeInsets.fromLTRB(
              Space.sm,
              Space.xs + 2,
              Space.sm,
              Space.xs,
            ),
            padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
            decoration: BoxDecoration(
              color: palette.surfaceAlt.withValues(alpha: 0.42),
              borderRadius: BorderRadius.circular(Radii.pill),
              border: Border.all(color: palette.border.withValues(alpha: 0.55)),
            ),
            child: Row(
              children: <Widget>[
                Expanded(
                  child: _ActionButton(
                    icon: liked
                        ? Icons.favorite_rounded
                        : Icons.favorite_border_rounded,
                    label: formatCount(count),
                    color: liked ? palette.danger : palette.textSecondary,
                    onTap: () => _toggleLike(liked, count),
                  ),
                ),
                if (post.allowComments)
                  Expanded(
                    child: _ActionButton(
                      icon: Icons.chat_bubble_rounded,
                      label: formatCount(post.commentCount),
                      onTap: () =>
                          context.push(RoutePaths.communityPost(post.id)),
                    ),
                  ),
                Expanded(
                  child: _ActionButton(
                    icon: Icons.share_rounded,
                    label: Tr.of(context, ar: 'مشاركة', en: 'Share'),
                    onTap: _share,
                  ),
                ),
                Expanded(
                  child: _ActionButton(
                    icon: saved
                        ? Icons.bookmark_rounded
                        : Icons.bookmark_border_rounded,
                    label: saved
                        ? Tr.of(context, ar: 'محفوظ', en: 'Saved')
                        : Tr.of(context, ar: 'حفظ', en: 'Save'),
                    color: saved ? palette.primary : palette.textSecondary,
                    onTap: () => _toggleSaved(saved),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
    if (!widget.flat) return card;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        card,
        Container(
          height: 1,
          margin: const EdgeInsets.symmetric(
            horizontal: Space.lg,
            vertical: Space.md,
          ),
          // Very light and translucent, never a heavy border.
          color: palette.border.withValues(alpha: 0.55),
        ),
      ],
    );
  }

  Future<void> _share() async {
    final link = postShareLink(post.id);
    final shareContext = context;
    final sharePayload = ChatShare(
      kind: post.isReel ? ChatShareKind.reel : ChatShareKind.post,
      id: post.id,
      title: post.authorName.isNotEmpty
          ? post.authorName
          : '@${post.authorUsername}',
      subtitle: post.text.trim(),
      imageKey: post.imageKeys.isNotEmpty
          ? post.imageKeys.first
          : (post.videoThumbnailKey ?? ''),
      route: RoutePaths.communityPost(post.id),
      extraId: post.authorUid,
    );
    await WingsPopup.show<void>(
      context: shareContext,
      heightFactor: 0.72,
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
                unawaited(shareToChats(shareContext, ref, sharePayload));
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
          ],
        ),
      ),
    );
  }

  Future<void> _toggleLike(bool liked, int count) async {
    final uid = _uid;
    final profile = ref.read(profileProvider);
    if (uid == null) {
      context.showSnack(
        Tr.of(context, ar: 'سجّل الدخول للإعجاب.', en: 'Sign in to like.'),
      );
      return;
    }
    if (_busyLike || profile == null) return;
    _busyLike = true;
    // Optimistic: the heart and the counter move before the write returns.
    final next = !liked;
    setState(() {
      _liked = next;
      _likeCount = (count + (next ? 1 : -1)).clamp(0, 1 << 31);
    });
    try {
      final result = await ref
          .read(communityRepositoryProvider)
          .toggleLike(postId: post.id, uid: uid, actor: profile);
      if (!mounted) return;
      setState(() {
        _liked = result;
        _likeCount = null;
      });
      widget.onChanged?.call(
        post.copyWith(likeCount: (count + (result ? 1 : -1)).clamp(0, 1 << 31)),
      );
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _liked = liked;
        _likeCount = count;
      });
      context.showSnack(userFacingError(context, error), isError: true);
    } finally {
      _busyLike = false;
    }
  }

  Future<void> _toggleSaved(bool saved) async {
    final uid = _uid;
    if (uid == null) {
      context.showSnack(
        Tr.of(
          context,
          ar: 'سجّل الدخول لحفظ المنشورات.',
          en: 'Sign in to save posts.',
        ),
      );
      return;
    }
    if (_busySave) return;
    _busySave = true;
    setState(() => _saved = !saved);
    try {
      await ref
          .read(communityRepositoryProvider)
          .toggleSaved(uid: uid, postId: post.id);
    } on Object catch (error) {
      if (!mounted) return;
      setState(() => _saved = saved);
      context.showSnack(userFacingError(context, error), isError: true);
    } finally {
      _busySave = false;
    }
  }

  Future<void> _toggleFollow(bool following) async {
    final profile = ref.read(profileProvider);
    if (profile == null || _busyFollow) return;
    _busyFollow = true;
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
      _busyFollow = false;
    }
  }

  /// Removes the post pictures from Tigris once the post itself is gone.
  /// Best effort: the bucket is private and the keys are unreachable without
  /// the post, so a failed cleanup costs storage, never privacy.
  Future<void> _deletePictures() async {
    final keys = <String>[
      ...post.imageKeys,
      if (post.hasVideo) post.videoKey!,
      if ((post.videoThumbnailKey ?? '').isNotEmpty) post.videoThumbnailKey!,
    ];
    if (keys.isEmpty) return;
    try {
      await ref.read(communityMediaProvider).deleteObjects(keys);
    } on Object {
      // Offline or the media API is not configured; nothing else to do.
    }
  }

  Widget _menu(BuildContext context, String? uid) {
    final isOwnerAuthor = ref.watch(isOwnerAccountProvider(post.authorUid));
    final savedIds = uid == null
        ? const <String>{}
        : ref.watch(savedPostIdsProvider(uid)).value ?? const <String>{};
    final saved = _saved ?? savedIds.contains(post.id);
    return PopupMenuButton<String>(
      icon: Icon(
        Icons.more_horiz_rounded,
        size: 20,
        color: context.palette.textMuted,
      ),
      tooltip: Tr.of(context, ar: 'خيارات', en: 'Options'),
      onSelected: (value) => _onMenu(value, uid),
      itemBuilder: (context) => <PopupMenuEntry<String>>[
        PopupMenuItem<String>(
          value: 'profile',
          child: Text(Tr.of(context, ar: 'عرض الملف', en: 'View profile')),
        ),
        if (_mine)
          PopupMenuItem<String>(
            value: 'edit',
            child: Text(Tr.of(context, ar: 'تعديل المنشور', en: 'Edit post')),
          ),
        if (_mine)
          PopupMenuItem<String>(
            value: 'delete',
            child: Text(Tr.of(context, ar: 'حذف المنشور', en: 'Delete post')),
          ),
        PopupMenuItem<String>(
          value: saved ? 'unsave' : 'save',
          child: Text(
            saved
                ? Tr.of(context, ar: 'إلغاء الحفظ', en: 'Remove from saved')
                : Tr.of(context, ar: 'حفظ المنشور', en: 'Save post'),
          ),
        ),
        if (post.text.trim().isNotEmpty)
          PopupMenuItem<String>(
            value: 'copy',
            child: Text(Tr.of(context, ar: 'نسخ النص', en: 'Copy text')),
          ),
        PopupMenuItem<String>(
          value: 'link',
          child: Text(Tr.of(context, ar: 'نسخ الرابط', en: 'Copy link')),
        ),
        if (!_mine)
          PopupMenuItem<String>(
            value: 'hide',
            child: Text(Tr.of(context, ar: 'إخفاء المنشور', en: 'Hide post')),
          ),
        if (!_mine && !isOwnerAuthor)
          PopupMenuItem<String>(
            value: 'report',
            child: Text(Tr.of(context, ar: 'إبلاغ', en: 'Report')),
          ),
        if (!_mine && !isOwnerAuthor)
          PopupMenuItem<String>(
            value: 'block',
            child: Text(Tr.of(context, ar: 'حظر المستخدم', en: 'Block user')),
          ),
        if (_isStaff)
          PopupMenuItem<String>(
            value: 'staff-delete',
            child: Text(
              Tr.of(context, ar: 'إزالة (إدارة)', en: 'Remove (staff)'),
            ),
          ),
      ],
    );
  }

  Future<void> _onMenu(String value, String? uid) async {
    switch (value) {
      case 'profile':
        context.push(RoutePaths.publicProfile(post.authorUid));
      case 'edit':
        final text = await showDialog<String>(
          context: context,
          builder: (context) => _EditPostDialog(initial: post.text),
        );
        if (text == null || !mounted) return;
        try {
          await ref
              .read(communityRepositoryProvider)
              .updatePost(postId: post.id, uid: _uid ?? '', text: text);
          widget.onChanged?.call(
            post.copyWith(text: text.trim(), edited: true),
          );
          if (mounted) {
            context.showSnack(
              Tr.of(context, ar: 'تم تحديث المنشور.', en: 'Post updated.'),
            );
          }
        } on Object catch (error) {
          if (mounted) {
            context.showSnack(userFacingError(context, error), isError: true);
          }
        }
      case 'delete':
        final confirmed = await WingsDialog.confirm(
          context,
          title: Tr.of(context, ar: 'حذف المنشور؟', en: 'Delete this post?'),
          message: Tr.of(
            context,
            ar: 'سيُحذف المنشور وإعجاباته وتعليقاته.',
            en: 'The post, its likes and its comments will be removed.',
          ),
          confirmLabel: Tr.of(context, ar: 'حذف', en: 'Delete'),
          destructive: true,
        );
        if (!confirmed || !mounted) return;
        try {
          await ref
              .read(communityRepositoryProvider)
              .deletePost(postId: post.id, uid: _uid ?? '');
          await _deletePictures();
          widget.onDeleted?.call();
          if (mounted) {
            context.showSnack(
              Tr.of(context, ar: 'تم حذف المنشور.', en: 'Post deleted.'),
            );
          }
        } on Object catch (error) {
          if (mounted) {
            context.showSnack(userFacingError(context, error), isError: true);
          }
        }
      case 'save':
        await _toggleSaved(false);
      case 'unsave':
        await _toggleSaved(true);
      case 'copy':
        await Clipboard.setData(ClipboardData(text: post.text));
        if (mounted) {
          context.showSnack(
            Tr.of(context, ar: 'تم نسخ النص.', en: 'Text copied.'),
          );
        }
      case 'link':
        await Clipboard.setData(ClipboardData(text: postShareLink(post.id)));
        if (mounted) {
          context.showSnack(
            Tr.of(context, ar: 'تم نسخ الرابط.', en: 'Link copied.'),
          );
        }
      case 'hide':
        if (uid == null) return;
        try {
          await ref
              .read(communityRepositoryProvider)
              .hidePost(uid: uid, postId: post.id);
          widget.onDeleted?.call();
          if (mounted) {
            context.showSnack(
              Tr.of(context, ar: 'تم إخفاء المنشور.', en: 'Post hidden.'),
            );
          }
        } on Object catch (error) {
          if (mounted) {
            context.showSnack(userFacingError(context, error), isError: true);
          }
        }
      case 'report':
        if (uid == null || ref.read(isOwnerAccountProvider(post.authorUid))) {
          return;
        }
        await showReportSheet(
          context,
          ref,
          targetType: 'post',
          targetId: post.id,
          targetUid: post.authorUid,
          preview: post.text,
        );
      case 'block':
        if (uid == null || ref.read(isOwnerAccountProvider(post.authorUid))) {
          return;
        }
        final confirmed = await WingsDialog.confirm(
          context,
          title: Tr.of(context, ar: 'حظر المستخدم؟', en: 'Block this user?'),
          message: Tr.of(
            context,
            ar: 'لن تظهر منشوراته أو تعليقاته لك، ولن يستطيع التفاعل معك.',
            en: 'Their posts and comments stay out of your view and they cannot interact with you.',
          ),
          confirmLabel: Tr.of(context, ar: 'حظر', en: 'Block'),
          destructive: true,
        );
        if (!confirmed || !mounted) return;
        try {
          await ref
              .read(communityRepositoryProvider)
              .block(uid: uid, target: post.authorUid);
          widget.onDeleted?.call();
          if (mounted) {
            context.showSnack(
              Tr.of(context, ar: 'تم الحظر.', en: 'User blocked.'),
            );
          }
        } on Object catch (error) {
          if (mounted) {
            context.showSnack(userFacingError(context, error), isError: true);
          }
        }
      case 'staff-delete':
        try {
          await ref.read(communityRepositoryProvider).removeAsStaff(post.id);
          widget.onDeleted?.call();
          if (mounted) {
            context.showSnack(
              Tr.of(context, ar: 'تمت إزالة المنشور.', en: 'Post removed.'),
            );
          }
        } on Object catch (error) {
          if (mounted) {
            context.showSnack(userFacingError(context, error), isError: true);
          }
        }
    }
  }
}

class _FollowButton extends StatelessWidget {
  const _FollowButton({
    required this.following,
    required this.busy,
    required this.onTap,
  });

  final bool following;
  final bool busy;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Padding(
      padding: const EdgeInsetsDirectional.only(end: Space.xs),
      child: SizedBox(
        height: 30,
        child: TextButton(
          onPressed: busy ? null : onTap,
          style: TextButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: Space.sm + 2),
            minimumSize: Size.zero,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            foregroundColor: following
                ? palette.textSecondary
                : palette.primary,
          ),
          child: Text(
            following
                ? Tr.of(context, ar: 'متابَع', en: 'Following')
                : Tr.of(context, ar: 'متابعة', en: 'Follow'),
            style: context.text.labelSmall?.copyWith(
              fontWeight: FontWeight.w700,
              color: following ? palette.textSecondary : palette.primary,
            ),
          ),
        ),
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.color,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final tint = color ?? palette.textSecondary;
    return Tooltip(
      message: label,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(Radii.pill),
        child: SizedBox(
          height: 36,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              Icon(icon, size: 17, color: tint),
              if (label.isNotEmpty) ...<Widget>[
                const SizedBox(width: 5),
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: context.text.labelSmall?.copyWith(
                      color: tint,
                      fontSize: 10.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// The stable, human-facing link of a post. It always points at the post id,
/// never at a signed media URL, and opening it inside Wings respects privacy,
/// blocking and the account state exactly like the in-app route.
String postShareLink(String postId) =>
    'https://wings.app${RoutePaths.communityPost(postId)}';

/// Video inside a normal post: resolved from the private bucket and paused
/// while it is out of view.
class _PostVideo extends ConsumerStatefulWidget {
  const _PostVideo({required this.post});

  final Post post;

  @override
  ConsumerState<_PostVideo> createState() => _PostVideoState();
}

class _PostVideoState extends ConsumerState<_PostVideo> {
  String? _url;
  String? _poster;
  bool _failed = false;
  bool _playing = false;

  @override
  void initState() {
    super.initState();
    unawaited(_resolve());
  }

  Future<void> _resolve() async {
    final service = ref.read(communityMediaProvider);
    final key = widget.post.videoKey;
    if (!service.available || key == null) {
      if (mounted) setState(() => _failed = true);
      return;
    }
    try {
      final keys = <String>[
        key,
        if ((widget.post.videoThumbnailKey ?? '').isNotEmpty)
          widget.post.videoThumbnailKey!,
      ];
      final urls = await service.downloadUrls(keys);
      if (!mounted) return;
      setState(() {
        _url = urls[key];
        _poster = urls[widget.post.videoThumbnailKey];
        _failed = (_url ?? '').isEmpty;
      });
    } on Object {
      if (mounted) setState(() => _failed = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_failed) {
      return Container(
        height: 140,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: context.palette.surfaceAlt,
          borderRadius: BorderRadius.circular(Radii.sm),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(
              Icons.videocam_off_outlined,
              size: 20,
              color: context.palette.textMuted,
            ),
            const SizedBox(height: Space.xs),
            Text(
              Tr.of(
                context,
                ar: 'الفيديو غير متاح الآن',
                en: 'The video is unavailable right now',
              ),
              style: context.text.labelSmall?.copyWith(
                color: context.palette.textMuted,
              ),
            ),
            TextButton(
              onPressed: () {
                setState(() => _failed = false);
                unawaited(_resolve());
              },
              child: Text(Tr.of(context, ar: 'إعادة المحاولة', en: 'Retry')),
            ),
          ],
        ),
      );
    }
    if (_url == null) {
      return AspectRatio(
        aspectRatio: widget.post.videoAspectRatio ?? 16 / 9,
        child: Container(
          color: Colors.black,
          alignment: Alignment.center,
          child: const CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }
    // Nothing in the feed starts playing on its own. The cover stays visible
    // until the member taps it, so scrolling a feed never costs a decoder and
    // never plays sound unexpectedly. Full-screen autoplay belongs to Reels.
    final ratio = widget.post.videoAspectRatio ?? 16 / 9;
    if (_playing) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(Radii.sm),
        child: CommunityVideo(
          url: _url,
          posterUrl: _poster,
          aspectRatio: ratio,
          showChrome: true,
        ),
      );
    }
    final duration = widget.post.videoDurationMs;
    final label = duration <= 0
        ? ''
        : '${duration ~/ 60000}:'
              '${((duration ~/ 1000) % 60).toString().padLeft(2, '0')}';
    return GestureDetector(
      onTap: () => setState(() => _playing = true),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(Radii.sm),
        child: AspectRatio(
          aspectRatio: ratio,
          child: Stack(
            fit: StackFit.expand,
            children: <Widget>[
              if ((_poster ?? '').isNotEmpty)
                Image.network(
                  _poster!,
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) =>
                      const ColoredBox(color: Colors.black),
                )
              else
                const ColoredBox(color: Colors.black),
              const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: <Color>[Colors.transparent, Colors.black54],
                  ),
                ),
              ),
              const Center(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: Colors.black54,
                    shape: BoxShape.circle,
                  ),
                  child: Padding(
                    padding: EdgeInsets.all(12),
                    child: Icon(
                      Icons.play_arrow_rounded,
                      color: Colors.white,
                      size: 30,
                    ),
                  ),
                ),
              ),
              if (label.isNotEmpty)
                PositionedDirectional(
                  end: 8,
                  bottom: 8,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.65),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      label,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Post pictures.
///
/// The bucket is private, so a key is exchanged for a signed URL by the media
/// Worker. When the Worker is not reachable the card shows the branded
/// placeholder instead of a broken image, which is exactly what a member would
/// see while offline.
class _PostImages extends ConsumerStatefulWidget {
  const _PostImages({required this.post});

  final Post post;

  @override
  ConsumerState<_PostImages> createState() => _PostImagesState();
}

class _PostImagesState extends ConsumerState<_PostImages> {
  Map<String, String> _urls = const <String, String>{};
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    unawaited(_resolve());
  }

  Future<void> _resolve() async {
    final service = ref.read(communityMediaProvider);
    if (!service.available) {
      if (mounted) setState(() => _failed = true);
      return;
    }
    try {
      final urls = await service.downloadUrls(widget.post.imageKeys);
      if (!mounted) return;
      setState(() => _urls = urls);
    } on Object {
      if (mounted) setState(() => _failed = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final keys = widget.post.imageKeys;
    if (keys.isEmpty) return const SizedBox.shrink();
    if (_failed) {
      return Container(
        height: 120,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: context.palette.surfaceAlt,
          borderRadius: BorderRadius.circular(Radii.sm),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(
              Icons.image_not_supported_outlined,
              size: 18,
              color: context.palette.textMuted,
            ),
            const SizedBox(width: Space.sm),
            Text(
              Tr.of(
                context,
                ar: 'الصور غير متاحة الآن',
                en: 'Pictures are unavailable right now',
              ),
              style: context.text.labelSmall?.copyWith(
                color: context.palette.textMuted,
              ),
            ),
          ],
        ),
      );
    }
    if (keys.length == 1) {
      return AspectRatio(
        aspectRatio: 4 / 3,
        child: WingsImage(
          url: _urls[keys.first],
          borderRadius: BorderRadius.circular(Radii.sm),
        ),
      );
    }
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: Space.xs,
      crossAxisSpacing: Space.xs,
      children: <Widget>[
        for (final key in keys.take(4))
          AspectRatio(
            aspectRatio: 1,
            child: WingsImage(
              url: _urls[key],
              borderRadius: BorderRadius.circular(Radii.xs),
            ),
          ),
      ],
    );
  }
}

class _EditPostDialog extends StatefulWidget {
  const _EditPostDialog({required this.initial});

  final String initial;

  @override
  State<_EditPostDialog> createState() => _EditPostDialogState();
}

class _EditPostDialogState extends State<_EditPostDialog> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.initial,
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(Tr.of(context, ar: 'تعديل المنشور', en: 'Edit post')),
      content: TextField(
        controller: _controller,
        maxLines: 6,
        minLines: 3,
        maxLength: 2000,
        textInputAction: TextInputAction.newline,
        decoration: InputDecoration(
          hintText: Tr.of(context, ar: 'نص المنشور', en: 'Post text'),
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(context.l10n.commonCancel),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(_controller.text),
          child: Text(context.l10n.commonSave),
        ),
      ],
    );
  }
}
