import 'dart:async';

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../app/theme/app_tokens.dart';
import '../../app/theme/context_ext.dart';
import '../../core/services/app_feedback.dart';
import '../../core/utils/tr.dart';
import '../../core/widgets/wings_layout.dart';
import '../../data/models/social.dart';
import '../profile/avatar_view.dart';
import '../stickers/comment_draft.dart';
import '../stickers/sticker_view.dart';
import 'comment_composer.dart';
import 'user_handle.dart';

/// One comment and its replies, shared by the player preview and the full
/// comments page so the two never drift apart.
class CommentTile extends ConsumerStatefulWidget {
  const CommentTile({
    super.key,
    required this.comment,
    required this.onReply,
    this.maxReplyPreview = 3,
    this.rank,
  });

  final EpisodeComment comment;

  /// Called with the reply text and the optional sticker id.
  final void Function(String text, String? stickerId) onReply;

  /// Position in the list, used for the medal on the first three comments.
  final int? rank;

  /// Replies shown inline before the rest move to the comments page.
  final int maxReplyPreview;

  @override
  ConsumerState<CommentTile> createState() => _CommentTileState();
}

class _CommentTileState extends ConsumerState<CommentTile> {
  bool _showReplies = false;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final comment = widget.comment;
    final mine = ref.watch(authProvider)?.id == comment.authorUid;

    return InkWell(
      onLongPress: () => _showActions(mine),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          Space.lg,
          Space.sm + 2,
          Space.lg,
          Space.sm + 2,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            GestureDetector(
              onTap: () => context.push('/user/${comment.authorUid}'),
              child: UserAvatar(
                uid: comment.authorUid,
                photoVersion: comment.photoVersion,
                name: comment.authorName,
                size: 36,
              ),
            ),
            const SizedBox(width: Space.md),
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
                          onTap: () =>
                              context.push('/user/${comment.authorUid}'),
                          style: context.text.labelSmall,
                        ),
                      ),
                      if (widget.rank != null && widget.rank! <= 3) ...<Widget>[
                        const SizedBox(width: 4),
                        _Medal(rank: widget.rank!),
                      ],
                      const SizedBox(width: Space.xs),
                      Text(
                        relativeCommentTime(context, comment.createdAt),
                        style: context.text.labelSmall?.copyWith(
                          color: palette.textMuted,
                          fontSize: 10,
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
                  const SizedBox(height: 3),
                  if (comment.text.isNotEmpty)
                    Text(
                      comment.text,
                      style: context.text.bodySmall?.copyWith(
                        color: palette.textPrimary,
                        height: 1.55,
                      ),
                    ),
                  if (comment.stickerId case final stickerId?)
                    Padding(
                      padding: EdgeInsets.only(
                        top: comment.text.isEmpty ? 0 : Space.xs,
                      ),
                      child: StickerMessage(stickerId: stickerId),
                    ),
                  Row(
                    children: <Widget>[
                      TextButton(
                        onPressed: () => _replyDialog(context),
                        style: TextButton.styleFrom(
                          minimumSize: Size.zero,
                          padding: const EdgeInsets.symmetric(
                            horizontal: Space.sm,
                            vertical: 2,
                          ),
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        child: Text(
                          Tr.of(context, ar: 'رد', en: 'Reply'),
                          style: context.text.labelSmall?.copyWith(
                            color: palette.textSecondary,
                          ),
                        ),
                      ),
                      if (comment.replyCount > 0)
                        TextButton(
                          onPressed: () =>
                              setState(() => _showReplies = !_showReplies),
                          style: TextButton.styleFrom(
                            minimumSize: Size.zero,
                            padding: const EdgeInsets.symmetric(
                              horizontal: Space.sm,
                              vertical: 2,
                            ),
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                          child: Text(
                            Tr.of(
                              context,
                              ar: '${comment.replyCount} ردود',
                              en: '${comment.replyCount} replies',
                            ),
                            style: context.text.labelSmall?.copyWith(
                              color: palette.primary,
                            ),
                          ),
                        ),
                    ],
                  ),
                  if (_showReplies)
                    StreamBuilder<List<EpisodeComment>>(
                      stream: ref
                          .read(socialRepositoryProvider)
                          .watchReplies(comment.episodeId, comment.id),
                      builder: (context, snapshot) {
                        final replies =
                            snapshot.data ?? const <EpisodeComment>[];
                        if (replies.isEmpty) return const SizedBox.shrink();
                        final visible = replies
                            .take(widget.maxReplyPreview)
                            .toList(growable: false);
                        return Column(
                          children: <Widget>[
                            for (final reply in visible)
                              Padding(
                                padding: const EdgeInsets.only(
                                  top: Space.xs,
                                  left: Space.md,
                                ),
                                child: GestureDetector(
                                  onLongPress:
                                      reply.authorUid ==
                                          ref.read(authProvider)?.id
                                      ? () => _deleteReply(comment, reply)
                                      : null,
                                  child: Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: <Widget>[
                                      UserAvatar(
                                        uid: reply.authorUid,
                                        photoVersion: reply.photoVersion,
                                        name: reply.authorName,
                                        size: 24,
                                      ),
                                      const SizedBox(width: Space.xs + 2),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: <Widget>[
                                            UserHandle(
                                              uid: reply.authorUid,
                                              username: reply.authorUsername,
                                              badges: reply.badges,
                                              style: context.text.labelSmall,
                                              onTap: () => context.push(
                                                '/user/${reply.authorUid}',
                                              ),
                                            ),
                                            if (reply.text.isNotEmpty)
                                              Text(
                                                reply.text,
                                                style: context.text.bodySmall
                                                    ?.copyWith(
                                                      color:
                                                          palette.textSecondary,
                                                    ),
                                              ),
                                            if (reply.stickerId
                                                case final stickerId?)
                                              Padding(
                                                padding: EdgeInsets.only(
                                                  top: reply.text.isEmpty
                                                      ? 0
                                                      : Space.xxs,
                                                ),
                                                child: StickerMessage(
                                                  stickerId: stickerId,
                                                  size: 92,
                                                  compact: true,
                                                ),
                                              ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                          ],
                        );
                      },
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Long-pressing your own reply removes it, with the same quiet cue the
  /// comment delete uses.
  Future<void> _deleteReply(EpisodeComment parent, EpisodeComment reply) async {
    final user = ref.read(authProvider);
    if (user == null) return;
    final confirmed = await WingsDialog.confirm(
      context,
      title: Tr.of(context, ar: 'حذف الرد', en: 'Delete reply'),
      message: Tr.of(
        context,
        ar: 'سيختفي ردك نهائيًا. لا يمكن التراجع.',
        en: 'Your reply will disappear for good. This cannot be undone.',
      ),
      confirmLabel: Tr.of(context, ar: 'حذف', en: 'Delete'),
      destructive: true,
    );
    if (!confirmed) return;
    try {
      await ref
          .read(socialRepositoryProvider)
          .deleteComment(
            episodeId: parent.episodeId,
            commentId: reply.id,
            uid: user.id,
            parentId: parent.id,
          );
      unawaited(AppFeedback.remove());
      if (mounted) {
        context.showSnack(
          Tr.of(context, ar: 'تم حذف الرد', en: 'Reply deleted'),
        );
      }
    } on Object {
      if (mounted) {
        context.showSnack(
          Tr.of(
            context,
            ar: 'تعذر حذف الرد. حاول مجددًا.',
            en: 'Could not delete the reply. Try again.',
          ),
          isError: true,
        );
      }
    }
  }

  Future<void> _replyDialog(BuildContext context) async {
    final draft = await showDialog<CommentDraft>(
      context: context,
      builder: (dialogContext) => const _ReplyDialog(),
    );
    if (draft != null && draft.canSend) {
      widget.onReply(draft.trimmedText, draft.normalizedStickerId);
    }
  }

  Future<void> _showActions(bool mine) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            if (widget.comment.text.isNotEmpty)
              ListTile(
                leading: const Icon(Icons.copy_rounded),
                title: Text(Tr.of(context, ar: 'نسخ النص', en: 'Copy text')),
                onTap: () => Navigator.of(sheetContext).pop('copy'),
              ),
            if (mine)
              ListTile(
                leading: const Icon(Icons.edit_outlined),
                title: Text(Tr.of(context, ar: 'تعديل', en: 'Edit')),
                onTap: () => Navigator.of(sheetContext).pop('edit'),
              ),
            if (mine)
              ListTile(
                leading: const Icon(Icons.delete_outline_rounded),
                title: Text(Tr.of(context, ar: 'حذف', en: 'Delete')),
                onTap: () => Navigator.of(sheetContext).pop('delete'),
              ),
            if (!mine)
              ListTile(
                leading: const Icon(Icons.flag_outlined),
                title: Text(Tr.of(context, ar: 'إبلاغ', en: 'Report')),
                onTap: () => Navigator.of(sheetContext).pop('report'),
              ),
          ],
        ),
      ),
    );
    if (!mounted || action == null) return;
    final repository = ref.read(socialRepositoryProvider);
    final user = ref.read(authProvider);
    switch (action) {
      case 'copy':
        await Clipboard.setData(ClipboardData(text: widget.comment.text));
        if (mounted) {
          context.showSnack(Tr.of(context, ar: 'تم نسخ النص', en: 'Copied'));
        }
        break;
      case 'edit':
        final controller = TextEditingController(text: widget.comment.text);
        final text = await showDialog<String>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: Text(
              Tr.of(context, ar: 'تعديل التعليق', en: 'Edit comment'),
            ),
            content: TextField(
              controller: controller,
              autofocus: true,
              maxLines: 4,
              maxLength: 1000,
            ),
            actions: <Widget>[
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: Text(Tr.of(context, ar: 'إلغاء', en: 'Cancel')),
              ),
              TextButton(
                onPressed: () =>
                    Navigator.of(dialogContext).pop(controller.text),
                child: Text(Tr.of(context, ar: 'حفظ', en: 'Save')),
              ),
            ],
          ),
        );
        controller.dispose();
        if (text != null && text.trim().isNotEmpty) {
          await repository.editComment(
            episodeId: widget.comment.episodeId,
            commentId: widget.comment.id,
            path:
                'episodes/${widget.comment.episodeId}/comments/${widget.comment.id}',
            text: text,
          );
          unawaited(AppFeedback.tap());
        }
        break;
      case 'delete':
        if (user == null || !mounted) return;
        final confirmed = await WingsDialog.confirm(
          context,
          title: Tr.of(context, ar: 'حذف التعليق', en: 'Delete comment'),
          message: Tr.of(
            context,
            ar: 'سيختفي التعليق نهائيًا مع كل الردود الموجودة تحته. لا يمكن التراجع.',
            en: 'The comment and every reply under it will disappear for good. This cannot be undone.',
          ),
          confirmLabel: Tr.of(context, ar: 'حذف', en: 'Delete'),
          destructive: true,
        );
        if (!confirmed) return;
        try {
          await repository.deleteComment(
            episodeId: widget.comment.episodeId,
            commentId: widget.comment.id,
            uid: user.id,
          );
          unawaited(AppFeedback.remove());
          if (mounted) {
            context.showSnack(
              Tr.of(context, ar: 'تم حذف التعليق', en: 'Deleted'),
            );
          }
        } on Object {
          if (mounted) {
            context.showSnack(
              Tr.of(
                context,
                ar: 'تعذر حذف التعليق. تحقق من الاتصال وحاول مجددًا.',
                en: 'Could not delete the comment. Check your connection and try again.',
              ),
              isError: true,
            );
          }
        }
        break;
      case 'report':
        if (user == null) return;
        await repository.report(
          reporterUid: user.id,
          targetType: 'comment',
          reason: 'inappropriate',
          episodeId: widget.comment.episodeId,
          commentId: widget.comment.id,
        );
        if (mounted) {
          context.showSnack(
            Tr.of(
              context,
              ar: 'تم إرسال البلاغ للمراجعة',
              en: 'Report sent for review',
            ),
          );
        }
        break;
    }
  }
}

/// Reply form with the same sticker support as the main composer. It returns
/// the draft through `Navigator.pop`, and never sends anything itself.
class _ReplyDialog extends StatefulWidget {
  const _ReplyDialog();

  @override
  State<_ReplyDialog> createState() => _ReplyDialogState();
}

class _ReplyDialogState extends State<_ReplyDialog> {
  final TextEditingController _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(Tr.of(context, ar: 'رد على التعليق', en: 'Reply')),
      contentPadding: const EdgeInsets.fromLTRB(
        Space.md,
        Space.md,
        Space.md,
        0,
      ),
      content: SizedBox(
        width: double.maxFinite,
        child: CommentComposer(
          controller: _controller,
          sending: false,
          onSend: (text, stickerId) async {
            final draft = CommentDraft(text: text, stickerId: stickerId);
            if (!draft.canSend) return false;
            Navigator.of(context).pop(draft);
            return true;
          },
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(Tr.of(context, ar: 'إلغاء', en: 'Cancel')),
        ),
      ],
    );
  }
}

/// Gold, silver and bronze medal for the first three comments.
class _Medal extends StatelessWidget {
  const _Medal({required this.rank});

  final int rank;

  static const List<String> _badges = <String>['🥇', '🥈', '🥉'];

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0.5, end: 1),
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOutBack,
      builder: (context, value, child) => Transform.scale(
        scale: value,
        child: Opacity(opacity: value.clamp(0, 1), child: child),
      ),
      child: Text(
        _badges[(rank - 1).clamp(0, 2)],
        style: const TextStyle(fontSize: 12),
      ),
    );
  }
}

/// Compact "3m / 2h / 5d" timestamp used by both comment views.
String relativeCommentTime(BuildContext context, DateTime time) {
  final diff = DateTime.now().difference(time);
  if (diff.inMinutes < 1) return Tr.of(context, ar: 'الآن', en: 'now');
  if (diff.inMinutes < 60) return '${diff.inMinutes}m';
  if (diff.inHours < 24) return '${diff.inHours}h';
  if (diff.inDays < 30) return '${diff.inDays}d';
  if (diff.inDays < 365) return '${diff.inDays ~/ 30}mo';
  return '${diff.inDays ~/ 365}y';
}

/// Firestore cursor wrapper used by the paginated comments page.
typedef CommentCursor = DocumentSnapshot<Map<String, dynamic>>;
