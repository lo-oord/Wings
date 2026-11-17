import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../app/theme/app_tokens.dart';
import '../../app/theme/context_ext.dart';
import '../../core/utils/tr.dart';
import '../../data/models/social.dart';
import '../profile/avatar_view.dart';
import 'username_text.dart';

/// One comment and its replies, shared by the player preview and the full
/// comments page so the two never drift apart.
class CommentTile extends ConsumerStatefulWidget {
  const CommentTile({
    super.key,
    required this.comment,
    required this.onReply,
    this.maxReplyPreview = 3,
  });

  final EpisodeComment comment;
  final void Function(String text) onReply;

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
                        child: UsernameText(
                          username: comment.authorUsername,
                          badges: comment.badges,
                          onTap: () =>
                              context.push('/user/${comment.authorUid}'),
                          style: context.text.labelSmall,
                        ),
                      ),
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
                  Text(
                    comment.isDeleted
                        ? Tr.of(
                            context,
                            ar: 'تم حذف هذا التعليق.',
                            en: 'This comment was deleted.',
                          )
                        : comment.text,
                    style: context.text.bodySmall?.copyWith(
                      color: comment.isDeleted
                          ? palette.textMuted
                          : palette.textPrimary,
                      fontStyle: comment.isDeleted
                          ? FontStyle.italic
                          : FontStyle.normal,
                      height: 1.55,
                    ),
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
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
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
                                          UsernameText(
                                            username: reply.authorUsername,
                                            badges: reply.badges,
                                            style: context.text.labelSmall,
                                            onTap: () => context.push(
                                              '/user/${reply.authorUid}',
                                            ),
                                          ),
                                          Text(
                                            reply.isDeleted
                                                ? Tr.of(
                                                    context,
                                                    ar: 'تم حذف هذا الرد.',
                                                    en: 'This reply was deleted.',
                                                  )
                                                : reply.text,
                                            style: context.text.bodySmall
                                                ?.copyWith(
                                                  color: reply.isDeleted
                                                      ? palette.textMuted
                                                      : palette.textSecondary,
                                                ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
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

  Future<void> _replyDialog(BuildContext context) async {
    final controller = TextEditingController();
    final text = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(Tr.of(context, ar: 'رد على التعليق', en: 'Reply')),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLines: 4,
          maxLength: 1000,
          decoration: InputDecoration(
            hintText: Tr.of(context, ar: 'اكتب ردك…', en: 'Write your reply…'),
          ),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text(Tr.of(context, ar: 'إلغاء', en: 'Cancel')),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(controller.text),
            child: Text(Tr.of(context, ar: 'إرسال', en: 'Send')),
          ),
        ],
      ),
    );
    controller.dispose();
    if (text != null && text.trim().isNotEmpty) widget.onReply(text);
  }

  Future<void> _showActions(bool mine) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
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
        }
        break;
      case 'delete':
        if (user == null) return;
        await repository.deleteComment(
          episodeId: widget.comment.episodeId,
          commentId: widget.comment.id,
          uid: user.id,
        );
        if (mounted) {
          context.showSnack(
            Tr.of(context, ar: 'تم حذف التعليق', en: 'Deleted'),
          );
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
