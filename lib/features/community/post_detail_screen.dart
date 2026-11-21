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
import '../../core/widgets/wings_layout.dart';
import '../../data/models/admin_models.dart' show StaffRole;
import '../../data/models/social.dart';
import '../admin/admin_providers.dart';
import '../admin/owner_guard.dart';
import '../profile/avatar_view.dart';
import '../social/comment_composer.dart';
import 'social_text.dart';
import '../social/user_handle.dart';
import 'community_providers.dart';
import 'post_card.dart';
import 'report_sheet.dart';

/// A post and its thread. The comment documents are the same ones episode
/// threads use, and the composer is the same widget, so posting a comment feels
/// identical everywhere in Wings.
class PostDetailScreen extends ConsumerStatefulWidget {
  const PostDetailScreen({super.key, required this.postId});

  final String postId;

  @override
  ConsumerState<PostDetailScreen> createState() => _PostDetailScreenState();
}

class _PostDetailScreenState extends ConsumerState<PostDetailScreen> {
  final TextEditingController _composer = TextEditingController();

  @override
  void dispose() {
    _composer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final post = ref.watch(postProvider(widget.postId));
    final comments = ref.watch(postCommentsProvider(widget.postId));
    final uid = ref.watch(authProvider)?.id;

    return Scaffold(
      backgroundColor: palette.background,
      appBar: WingsAppBar(
        showBack: true,
        title: Text(Tr.of(context, ar: 'المنشور', en: 'Post')),
      ),
      body: Column(
        children: <Widget>[
          Expanded(
            child: post.when(
              loading: () => const WingsLoading(),
              error: (error, stack) => WingsEmptyState(
                icon: Icons.cloud_off_rounded,
                title: AppLocalizations.of(context).commonErrorTitle,
                message: loadFailedText(context),
                actionLabel: AppLocalizations.of(context).commonRetry,
                onAction: () => ref.invalidate(postProvider(widget.postId)),
              ),
              data: (value) {
                if (value == null) {
                  return WingsEmptyState(
                    icon: Icons.delete_outline_rounded,
                    title: Tr.of(
                      context,
                      ar: 'المنشور غير موجود',
                      en: 'This post is gone',
                    ),
                    message: Tr.of(
                      context,
                      ar: 'ربما حذفه صاحبه.',
                      en: 'Its author may have deleted it.',
                    ),
                  );
                }
                return ListView(
                  padding: const EdgeInsets.only(bottom: Space.lg),
                  children: <Widget>[
                    PostCard(
                      post: value,
                      onChanged: (updated) =>
                          ref.invalidate(postProvider(widget.postId)),
                      onDeleted: () {
                        if (context.canPop()) context.pop();
                      },
                    ),
                    const SizedBox(height: Space.xs),
                    Padding(
                      padding: const EdgeInsetsDirectional.fromSTEB(
                        Space.lg,
                        0,
                        Space.lg,
                        Space.xs,
                      ),
                      child: Text(
                        Tr.of(
                          context,
                          ar: 'التعليقات (${comments.comments.length})',
                          en: 'Comments (${comments.comments.length})',
                        ),
                        style: context.text.labelMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    if (comments.loading && comments.comments.isEmpty)
                      const Padding(
                        padding: EdgeInsets.all(Space.xl),
                        child: WingsLoading(),
                      )
                    else if (comments.comments.isEmpty)
                      Padding(
                        padding: const EdgeInsets.all(Space.xl),
                        child: Text(
                          Tr.of(
                            context,
                            ar: 'لا تعليقات بعد. ابدأ النقاش.',
                            en: 'No comments yet. Start the conversation.',
                          ),
                          textAlign: TextAlign.center,
                          style: context.text.bodySmall?.copyWith(
                            color: palette.textMuted,
                          ),
                        ),
                      )
                    else
                      for (final comment in comments.comments)
                        _PostCommentTile(
                          postId: widget.postId,
                          comment: comment,
                          uid: uid,
                        ),
                    if (comments.hasMore)
                      TextButton(
                        onPressed: () => ref
                            .read(postCommentsProvider(widget.postId).notifier)
                            .loadMore(),
                        child: Text(
                          Tr.of(
                            context,
                            ar: 'عرض تعليقات أقدم',
                            en: 'Show older comments',
                          ),
                        ),
                      ),
                  ],
                );
              },
            ),
          ),
          if (uid != null)
            SafeArea(
              top: false,
              child: CommentComposer(
                controller: _composer,
                sending: comments.sending,
                onSend: (text, _, mentions, animeRefs) => ref
                    .read(postCommentsProvider(widget.postId).notifier)
                    .add(text, mentions: mentions, animeRefs: animeRefs),
              ),
            ),
        ],
      ),
    );
  }
}

class _PostCommentTile extends ConsumerStatefulWidget {
  const _PostCommentTile({
    required this.postId,
    required this.comment,
    required this.uid,
  });

  final String postId;
  final EpisodeComment comment;
  final String? uid;

  @override
  ConsumerState<_PostCommentTile> createState() => _PostCommentTileState();
}

class _PostCommentTileState extends ConsumerState<_PostCommentTile> {
  bool _showReplies = false;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final comment = widget.comment;
    final mine = widget.uid != null && widget.uid == comment.authorUid;
    final staff =
        (ref.watch(staffRoleProvider).value ?? StaffRole.user) !=
        StaffRole.user;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        InkWell(
          onLongPress: widget.uid == null ? null : () => _actions(mine, staff),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              Space.lg,
              Space.sm,
              Space.lg,
              Space.sm,
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                GestureDetector(
                  onTap: () =>
                      context.push(RoutePaths.publicProfile(comment.authorUid)),
                  child: UserAvatar(
                    uid: comment.authorUid,
                    photoVersion: comment.photoVersion,
                    name: comment.authorName,
                    size: 34,
                  ),
                ),
                const SizedBox(width: Space.sm + 2),
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
                              onTap: () => context.push(
                                RoutePaths.publicProfile(comment.authorUid),
                              ),
                              style: context.text.labelSmall,
                            ),
                          ),
                          if (comment.edited)
                            Text(
                              Tr.of(context, ar: ' · معدّل', en: ' · edited'),
                              style: context.text.labelSmall?.copyWith(
                                color: palette.textMuted,
                                fontSize: 10,
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      if (comment.pinned)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 3),
                          child: Row(
                            children: <Widget>[
                              Icon(
                                Icons.push_pin_rounded,
                                size: 11,
                                color: palette.primary,
                              ),
                              const SizedBox(width: 3),
                              Text(
                                Tr.of(context, ar: 'مثبت', en: 'Pinned'),
                                style: context.text.labelSmall?.copyWith(
                                  color: palette.primary,
                                  fontSize: 9,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                        ),
                      SocialText(
                        text: comment.text,
                        mentions: comment.mentions,
                        animeRefs: comment.animeRefs,
                        hashtags: comment.hashtags,
                        showAnimeChips: false,
                        linkColor: palette.success,
                        style: context.text.bodySmall?.copyWith(height: 1.55),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: <Widget>[
                          if (widget.uid != null)
                            InkWell(
                              onTap: () => _reply(),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 2,
                                  horizontal: 2,
                                ),
                                child: Text(
                                  Tr.of(context, ar: 'رد', en: 'Reply'),
                                  style: context.text.labelSmall?.copyWith(
                                    color: palette.primary,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ),
                          if (comment.replyCount > 0) ...<Widget>[
                            const SizedBox(width: Space.md),
                            InkWell(
                              onTap: () =>
                                  setState(() => _showReplies = !_showReplies),
                              child: Text(
                                _showReplies
                                    ? Tr.of(
                                        context,
                                        ar: 'إخفاء الردود',
                                        en: 'Hide replies',
                                      )
                                    : Tr.of(
                                        context,
                                        ar: 'عرض الردود (${comment.replyCount})',
                                        en: 'Show replies (${comment.replyCount})',
                                      ),
                                style: context.text.labelSmall?.copyWith(
                                  color: palette.textSecondary,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        if (_showReplies)
          _Replies(
            postId: widget.postId,
            commentId: comment.id,
            uid: widget.uid,
          ),
      ],
    );
  }

  Future<void> _reply() async {
    final draft = await showCommentComposerDialog(
      context,
      title: Tr.of(context, ar: 'رد على التعليق', en: 'Reply to the comment'),
    );
    if (draft == null || !mounted) return;
    final ok = await ref
        .read(postCommentsProvider(widget.postId).notifier)
        .add(
          draft.trimmedText,
          parentId: widget.comment.id,
          mentions: draft.mentions,
          animeRefs: draft.animeRefs,
        );
    if (!mounted) return;
    if (!ok) {
      context.showSnack(
        Tr.of(context, ar: 'تعذر إرسال الرد.', en: 'The reply was not sent.'),
        isError: true,
      );
      return;
    }
    setState(() => _showReplies = true);
  }

  Future<void> _actions(bool mine, bool staff) async {
    final isOwner = ref.read(isOwnerAccountProvider(widget.comment.authorUid));
    final post = ref.read(postProvider(widget.postId)).value;
    // The Owner pins any comment; the post author pins a comment on their own
    // post. The rules enforce the same rule on the write itself.
    final canPin =
        ref.read(isOwnerProvider) ||
        (post != null && post.authorUid == widget.uid);
    final choice = await WingsPopup.show<String>(
      context: context,
      heightFactor: 0.72,
      builder: (context) => SafeArea(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              ListTile(
                leading: const Icon(Icons.person_outline_rounded),
                title: Text(
                  Tr.of(context, ar: 'عرض الملف', en: 'View profile'),
                ),
                onTap: () => Navigator.of(context).pop('profile'),
              ),
              if (canPin)
                ListTile(
                  leading: Icon(
                    widget.comment.pinned
                        ? Icons.push_pin_outlined
                        : Icons.push_pin_rounded,
                  ),
                  title: Text(
                    widget.comment.pinned
                        ? Tr.of(
                            context,
                            ar: 'إلغاء التثبيت',
                            en: 'Unpin comment',
                          )
                        : Tr.of(
                            context,
                            ar: 'تثبيت التعليق',
                            en: 'Pin comment',
                          ),
                  ),
                  onTap: () => Navigator.of(context).pop('pin'),
                ),
              if (mine)
                ListTile(
                  leading: const Icon(Icons.edit_outlined),
                  title: Text(Tr.of(context, ar: 'تعديل', en: 'Edit')),
                  onTap: () => Navigator.of(context).pop('edit'),
                ),
              if (mine)
                ListTile(
                  leading: const Icon(Icons.delete_outline_rounded),
                  title: Text(Tr.of(context, ar: 'حذف', en: 'Delete')),
                  onTap: () => Navigator.of(context).pop('delete'),
                ),
              if (!mine && !isOwner)
                ListTile(
                  leading: const Icon(Icons.flag_outlined),
                  title: Text(Tr.of(context, ar: 'إبلاغ', en: 'Report')),
                  onTap: () => Navigator.of(context).pop('report'),
                ),
              if (!mine && staff)
                ListTile(
                  leading: const Icon(Icons.gavel_rounded),
                  title: Text(
                    Tr.of(context, ar: 'إزالة (إدارة)', en: 'Remove (staff)'),
                  ),
                  onTap: () => Navigator.of(context).pop('staff-delete'),
                ),
              const SizedBox(height: Space.sm),
            ],
          ),
        ),
      ),
    );
    if (choice == null || !mounted) return;
    final controller = ref.read(postCommentsProvider(widget.postId).notifier);
    switch (choice) {
      case 'profile':
        context.push(RoutePaths.publicProfile(widget.comment.authorUid));
      case 'pin':
        try {
          await ref
              .read(communityRepositoryProvider)
              .setPinnedComment(
                postId: widget.postId,
                commentId: widget.comment.id,
                parentId: widget.comment.parentId,
                pinned: !widget.comment.pinned,
              );
          await controller.load();
          if (mounted) {
            context.showSnack(
              widget.comment.pinned
                  ? Tr.of(
                      context,
                      ar: 'تم إلغاء التثبيت.',
                      en: 'Comment unpinned.',
                    )
                  : Tr.of(
                      context,
                      ar: 'تم تثبيت التعليق أولًا.',
                      en: 'Comment pinned to the top.',
                    ),
            );
          }
        } on Object catch (error) {
          if (mounted) {
            context.showSnack(userFacingError(context, error), isError: true);
          }
        }
      case 'edit':
        final text = await _askText(
          title: Tr.of(context, ar: 'تعديل التعليق', en: 'Edit comment'),
          confirm: context.l10n.commonSave,
          initial: widget.comment.text,
        );
        if (text == null) return;
        try {
          await controller.edit(widget.comment, text);
        } on Object catch (error) {
          if (mounted) {
            context.showSnack(userFacingError(context, error), isError: true);
          }
        }
      case 'delete':
        final confirmed = await WingsDialog.confirm(
          context,
          title: Tr.of(context, ar: 'حذف التعليق؟', en: 'Delete this comment?'),
          message: Tr.of(
            context,
            ar: 'سيختفي التعليق وردوده.',
            en: 'The comment and its replies will be removed.',
          ),
          confirmLabel: context.l10n.commonDelete,
          destructive: true,
        );
        if (!confirmed) return;
        await controller.delete(widget.comment);
      case 'report':
        await showReportSheet(
          context,
          ref,
          targetType: 'comment',
          targetId: widget.comment.id,
          targetUid: widget.comment.authorUid,
          preview: widget.comment.text,
        );
      case 'staff-delete':
        await controller.delete(widget.comment);
    }
  }

  Future<String?> _askText({
    required String title,
    required String confirm,
    String initial = '',
  }) async {
    final controller = TextEditingController(text: initial);
    final value = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          autofocus: true,
          minLines: 2,
          maxLines: 5,
          maxLength: 1000,
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(context.l10n.commonCancel),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(controller.text),
            child: Text(confirm),
          ),
        ],
      ),
    );
    controller.dispose();
    if (value == null || value.trim().isEmpty) return null;
    return value;
  }
}

class _Replies extends ConsumerWidget {
  const _Replies({
    required this.postId,
    required this.commentId,
    required this.uid,
  });

  final String postId;
  final String commentId;
  final String? uid;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.palette;
    final replies = ref.watch(
      postRepliesProvider((postId: postId, commentId: commentId)),
    );
    return replies.when(
      loading: () => const Padding(
        padding: EdgeInsets.all(Space.sm),
        child: WingsLoading(size: 16),
      ),
      error: (error, stack) => const SizedBox.shrink(),
      data: (items) => Column(
        children: <Widget>[
          for (final reply in items)
            Padding(
              padding: const EdgeInsetsDirectional.fromSTEB(
                Space.xxxl + Space.sm,
                Space.xxs,
                Space.lg,
                Space.sm,
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Container(
                    width: 2,
                    height: 30,
                    margin: const EdgeInsetsDirectional.only(end: Space.sm),
                    color: palette.border,
                  ),
                  GestureDetector(
                    onTap: () =>
                        context.push(RoutePaths.publicProfile(reply.authorUid)),
                    child: UserAvatar(
                      uid: reply.authorUid,
                      photoVersion: reply.photoVersion,
                      name: reply.authorName,
                      size: 26,
                    ),
                  ),
                  const SizedBox(width: Space.sm),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        UserHandle(
                          uid: reply.authorUid,
                          username: reply.authorUsername,
                          badges: reply.badges,
                          style: context.text.labelSmall,
                          onTap: () => context.push(
                            RoutePaths.publicProfile(reply.authorUid),
                          ),
                        ),
                        const SizedBox(height: 2),
                        SocialText(
                          text: reply.text,
                          mentions: reply.mentions,
                          animeRefs: reply.animeRefs,
                          showAnimeChips: false,
                          linkColor: palette.success,
                          style: context.text.bodySmall?.copyWith(height: 1.5),
                        ),
                      ],
                    ),
                  ),
                  if (uid != null && uid == reply.authorUid)
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      icon: Icon(
                        Icons.delete_outline_rounded,
                        size: 16,
                        color: palette.textMuted,
                      ),
                      onPressed: () => ref
                          .read(postCommentsProvider(postId).notifier)
                          .delete(reply),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
