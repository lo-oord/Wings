import 'dart:async';

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../app/theme/app_tokens.dart';
import '../../app/theme/context_ext.dart';
import '../../core/utils/tr.dart';
import '../../core/widgets/wings_buttons.dart';
import '../../data/models/social.dart';
import '../profile/avatar_view.dart';
import 'username_text.dart';

/// YouTube-inspired interaction area for a single episode.
///
/// Only the visible episode's newest comment page is listened to; older pages
/// are fetched with a cursor on demand and the listeners are disposed with the
/// screen, so the player's playback is never blocked by social data.
class EpisodeSocialSection extends ConsumerStatefulWidget {
  const EpisodeSocialSection({
    super.key,
    required this.episodeId,
    required this.episodeTitle,
    this.embedded = false,
    this.savedToLibrary = false,
    this.onDownload,
    this.onToggleSave,
  });

  final String episodeId;
  final String episodeTitle;

  /// Embedded mode is the YouTube-style layout under the player: the action
  /// buttons, the composer and the comments flow with the page instead of
  /// living inside a fixed-height sheet.
  final bool embedded;

  /// Library state for the save button; ignored when [onToggleSave] is null.
  final bool savedToLibrary;
  final VoidCallback? onDownload;
  final VoidCallback? onToggleSave;

  @override
  ConsumerState<EpisodeSocialSection> createState() =>
      _EpisodeSocialSectionState();
}

class _EpisodeSocialSectionState extends ConsumerState<EpisodeSocialSection> {
  final TextEditingController _composer = TextEditingController();
  final FocusNode _composerFocus = FocusNode();
  ReactionType? _reaction;
  EpisodeCounts _counts = EpisodeCounts.zero;
  bool _countsLoading = true;
  bool _sending = false;
  bool _loadingMore = false;
  bool _hasMore = false;
  DocumentSnapshot<Map<String, dynamic>>? _cursor;
  final List<EpisodeComment> _older = <EpisodeComment>[];

  @override
  void initState() {
    super.initState();
    _loadCounts();
    _loadReaction();
  }

  @override
  void dispose() {
    _composer.dispose();
    _composerFocus.dispose();
    super.dispose();
  }

  Future<void> _loadCounts() async {
    try {
      final counts = await ref
          .read(socialRepositoryProvider)
          .counts(widget.episodeId);
      if (!mounted) return;
      setState(() {
        _counts = counts;
        _countsLoading = false;
      });
    } on Object {
      if (mounted) setState(() => _countsLoading = false);
    }
  }

  Future<void> _loadReaction() async {
    final user = ref.read(authProvider);
    if (user == null) return;
    try {
      final reaction = await ref
          .read(socialRepositoryProvider)
          .myReaction(widget.episodeId, user.id);
      if (mounted) setState(() => _reaction = reaction);
    } on Object {
      // A missing or unreadable reaction simply shows as "no reaction".
    }
  }

  Future<void> _toggleReaction(ReactionType type) async {
    final user = ref.read(authProvider);
    if (user == null) {
      _requireSignIn();
      return;
    }
    final previous = _reaction;
    final next = previous == type ? null : type;
    setState(() {
      _reaction = next;
      _counts = EpisodeCounts(
        likes:
            _counts.likes -
            (previous == ReactionType.like ? 1 : 0) +
            (next == ReactionType.like ? 1 : 0),
        dislikes:
            _counts.dislikes -
            (previous == ReactionType.dislike ? 1 : 0) +
            (next == ReactionType.dislike ? 1 : 0),
        comments: _counts.comments,
      );
    });
    try {
      await ref
          .read(socialRepositoryProvider)
          .setReaction(episodeId: widget.episodeId, uid: user.id, type: next);
      unawaited(_loadCounts());
    } on Object {
      if (!mounted) return;
      setState(() {
        _reaction = previous;
      });
      unawaited(_loadCounts());
    }
  }

  Future<void> _share() async {
    final text = Tr.of(
      context,
      ar: 'شاهد ${widget.episodeTitle} على Wings',
      en: 'Watch ${widget.episodeTitle} on Wings',
    );
    await ref
        .read(shareServiceProvider)
        .shareText(text, subject: widget.episodeTitle);
  }

  Future<void> _send(String text, {String? parentId}) async {
    final user = ref.read(authProvider);
    final profile = ref.read(profileProvider);
    if (user == null) {
      _requireSignIn();
      return;
    }
    if (profile == null) {
      context.showSnack(
        Tr.of(
          context,
          ar: 'لم يتم تحميل ملفك الشخصي بعد. حاول بعد لحظة.',
          en: 'Your profile is still loading. Try again in a moment.',
        ),
        isError: true,
      );
      return;
    }
    if (text.trim().isEmpty) return;
    setState(() => _sending = true);
    try {
      await ref
          .read(socialRepositoryProvider)
          .addComment(
            episodeId: widget.episodeId,
            author: profile,
            text: text,
            parentId: parentId,
          );
      if (!mounted) return;
      if (parentId == null) _composer.clear();
      unawaited(_loadCounts());
    } on Object {
      if (mounted) {
        context.showSnack(
          Tr.of(
            context,
            ar: 'تعذر إرسال التعليق. تحقق من الاتصال وحاول مرة أخرى.',
            en: 'Could not post the comment. Check your connection and try again.',
          ),
          isError: true,
        );
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _loadMore() async {
    if (_loadingMore) return;
    setState(() => _loadingMore = true);
    try {
      final page = await ref
          .read(socialRepositoryProvider)
          .page(widget.episodeId, after: _cursor);
      if (!mounted) return;
      setState(() {
        _older.addAll(page.items);
        _cursor = page.cursor;
        _hasMore = page.hasMore;
        _loadingMore = false;
      });
    } on Object {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  void _requireSignIn() {
    context.showSnack(
      Tr.of(
        context,
        ar: 'سجّل الدخول للتفاعل مع الحلقات.',
        en: 'Sign in to interact with episodes.',
      ),
      isError: true,
    );
  }

  Widget _actionBar() {
    return _ActionBar(
      scrollable: widget.embedded,
      children: <Widget>[
        _ReactionButton(
          icon: _reaction == ReactionType.like
              ? Icons.thumb_up_alt_rounded
              : Icons.thumb_up_alt_outlined,
          count: _counts.likes,
          active: _reaction == ReactionType.like,
          expanded: !widget.embedded,
          onTap: () => _toggleReaction(ReactionType.like),
        ),
        _ReactionButton(
          icon: _reaction == ReactionType.dislike
              ? Icons.thumb_down_alt_rounded
              : Icons.thumb_down_alt_outlined,
          count: _counts.dislikes,
          active: _reaction == ReactionType.dislike,
          expanded: !widget.embedded,
          onTap: () => _toggleReaction(ReactionType.dislike),
        ),
        _ReactionButton(
          icon: Icons.ios_share_rounded,
          label: Tr.of(context, ar: 'مشاركة', en: 'Share'),
          expanded: !widget.embedded,
          onTap: _share,
        ),
        if (widget.onDownload != null)
          _ReactionButton(
            icon: Icons.download_rounded,
            label: Tr.of(context, ar: 'تنزيل', en: 'Download'),
            expanded: !widget.embedded,
            onTap: widget.onDownload,
          ),
        if (widget.onToggleSave != null)
          _ReactionButton(
            icon: widget.savedToLibrary
                ? Icons.bookmark_rounded
                : Icons.bookmark_border_rounded,
            label: Tr.of(
              context,
              ar: widget.savedToLibrary ? 'محفوظ' : 'حفظ',
              en: widget.savedToLibrary ? 'Saved' : 'Save',
            ),
            active: widget.savedToLibrary,
            expanded: !widget.embedded,
            onTap: widget.onToggleSave,
          ),
        _ReactionButton(
          icon: Icons.mode_comment_outlined,
          count: _countsLoading ? null : _counts.comments,
          label: Tr.of(context, ar: 'تعليقات', en: 'Comments'),
          expanded: !widget.embedded,
          onTap: widget.embedded ? _focusComposer : () {},
        ),
      ],
    );
  }

  /// Inline comments already sit under the buttons, so the counter button
  /// simply brings the composer into view.
  void _focusComposer() {
    final focused = _composerFocus.hasFocus;
    if (focused) {
      _composerFocus.unfocus();
    } else {
      _composerFocus.requestFocus();
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final user = ref.watch(authProvider);

    if (widget.embedded) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          _actionBar(),
          Divider(height: 1, color: palette.border),
          if (user == null)
            _SignInPrompt(onSignIn: () => context.push('/login'))
          else ...<Widget>[
            _Composer(
              controller: _composer,
              focusNode: _composerFocus,
              sending: _sending,
              onSend: _send,
            ),
            _CommentList(
              episodeId: widget.episodeId,
              older: _older,
              composer: _composer,
              sending: _sending,
              hasMore: _hasMore,
              loadingMore: _loadingMore,
              onSend: _send,
              onLoadMore: _loadMore,
              onReply: (commentId, text) => _send(text, parentId: commentId),
              scrollable: false,
            ),
          ],
        ],
      );
    }

    return Material(
      color: palette.background,
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            _actionBar(),
            Divider(height: 1, color: palette.border),
            Expanded(
              child: user == null
                  ? _SignInPrompt(onSignIn: () => context.push('/login'))
                  : _CommentList(
                      episodeId: widget.episodeId,
                      older: _older,
                      composer: _composer,
                      sending: _sending,
                      hasMore: _hasMore,
                      loadingMore: _loadingMore,
                      onSend: _send,
                      onLoadMore: _loadMore,
                      onReply: (commentId, text) =>
                          _send(text, parentId: commentId),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Action bar under a video. In embedded mode the buttons scroll horizontally
/// like the YouTube app, so download, save and share sit next to the reactions.
class _ActionBar extends StatelessWidget {
  const _ActionBar({required this.children, required this.scrollable});

  final List<Widget> children;
  final bool scrollable;

  @override
  Widget build(BuildContext context) {
    if (!scrollable) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(Space.md, Space.sm, Space.md, 0),
        child: Row(children: children),
      );
    }
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(
        Space.lg,
        Space.xs,
        Space.lg,
        Space.xs,
      ),
      child: Row(
        children: <Widget>[
          for (var index = 0; index < children.length; index++) ...<Widget>[
            children[index],
            if (index != children.length - 1) const SizedBox(width: Space.xs),
          ],
        ],
      ),
    );
  }
}

class _ReactionButton extends StatelessWidget {
  const _ReactionButton({
    required this.icon,
    this.count,
    this.label,
    this.active = false,
    this.expanded = true,
    this.onTap,
  });

  final IconData icon;
  final int? count;
  final String? label;
  final bool active;

  /// Expanded rows fill the sheet width; pills size themselves.
  final bool expanded;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final color = active ? palette.primary : palette.textSecondary;
    final content = Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: Space.md,
        vertical: Space.sm,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          Icon(icon, size: 18, color: color),
          if (label != null || count != null) ...<Widget>[
            const SizedBox(width: 4),
            Text(
              label ?? '$count',
              style: context.text.labelSmall?.copyWith(color: color),
            ),
          ],
        ],
      ),
    );

    if (expanded) {
      return Expanded(
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(Radii.sm),
          child: content,
        ),
      );
    }

    // Pill used by the horizontal bar under the player.
    return Material(
      color: active
          ? palette.primary.withValues(alpha: 0.12)
          : palette.surfaceAlt,
      borderRadius: BorderRadius.circular(Radii.pill),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(Radii.pill),
        child: content,
      ),
    );
  }
}

class _SignInPrompt extends StatelessWidget {
  const _SignInPrompt({required this.onSignIn});

  final VoidCallback onSignIn;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(Space.lg),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(
            Icons.forum_outlined,
            size: 28,
            color: context.palette.textMuted,
          ),
          const SizedBox(height: Space.sm),
          Text(
            Tr.of(
              context,
              ar: 'سجّل الدخول للمشاركة في التعليقات والإعجابات.',
              en: 'Sign in to join the comments and reactions.',
            ),
            textAlign: TextAlign.center,
            style: context.text.bodySmall?.copyWith(
              color: context.palette.textSecondary,
            ),
          ),
          const SizedBox(height: Space.md),
          WingsButton(
            label: Tr.of(context, ar: 'تسجيل الدخول', en: 'Sign in'),
            onPressed: onSignIn,
          ),
        ],
      ),
    ),
  );
}

class _CommentList extends ConsumerWidget {
  const _CommentList({
    required this.episodeId,
    required this.older,
    required this.composer,
    required this.sending,
    required this.hasMore,
    required this.loadingMore,
    required this.onSend,
    required this.onLoadMore,
    required this.onReply,
    this.scrollable = true,
  });

  final String episodeId;
  final List<EpisodeComment> older;
  final TextEditingController composer;
  final bool sending;
  final bool hasMore;
  final bool loadingMore;
  final Future<void> Function(String text, {String? parentId}) onSend;
  final VoidCallback onLoadMore;
  final void Function(String commentId, String text) onReply;

  /// When false the comments are laid out as a plain column so they can live
  /// inside the page scroll under the player instead of a nested list.
  final bool scrollable;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.palette;
    return StreamBuilder<List<EpisodeComment>>(
      stream: ref.read(socialRepositoryProvider).watchLatest(episodeId),
      builder: (context, snapshot) {
        final live = snapshot.data ?? const <EpisodeComment>[];
        final seen = <String>{};
        final merged = <EpisodeComment>[
          for (final comment in <EpisodeComment>[...live, ...older])
            if (seen.add(comment.id)) comment,
        ]..sort((a, b) => b.createdAt.compareTo(a.createdAt));

        if (snapshot.connectionState == ConnectionState.waiting &&
            merged.isEmpty) {
          return const Padding(
            padding: EdgeInsets.all(Space.lg),
            child: Center(
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          );
        }
        if (merged.isEmpty) {
          return Padding(
            padding: const EdgeInsets.all(Space.lg),
            child: Center(
              child: Text(
                Tr.of(
                  context,
                  ar: 'لا توجد تعليقات بعد. كن أول من يعلّق!',
                  en: 'No comments yet. Be the first to comment!',
                ),
                textAlign: TextAlign.center,
                style: context.text.bodySmall?.copyWith(
                  color: palette.textMuted,
                ),
              ),
            ),
          );
        }

        final tiles = <Widget>[
          for (final comment in merged)
            _CommentTile(
              comment: comment,
              onReply: (text) => onReply(comment.id, text),
            ),
          if (hasMore)
            Center(
              child: TextButton(
                onPressed: loadingMore ? null : onLoadMore,
                child: loadingMore
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text(
                        Tr.of(
                          context,
                          ar: 'عرض تعليقات أقدم',
                          en: 'Load older comments',
                        ),
                      ),
              ),
            ),
        ];

        if (!scrollable) {
          return Column(children: tiles);
        }

        return Column(
          children: <Widget>[
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(vertical: Space.sm),
                children: tiles,
              ),
            ),
            Divider(height: 1, color: palette.border),
            _Composer(controller: composer, sending: sending, onSend: onSend),
          ],
        );
      },
    );
  }
}

class _Composer extends StatelessWidget {
  const _Composer({
    required this.controller,
    required this.sending,
    required this.onSend,
    this.focusNode,
  });

  final TextEditingController controller;
  final bool sending;
  final Future<void> Function(String text, {String? parentId}) onSend;
  final FocusNode? focusNode;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        Space.md,
        Space.sm,
        Space.md,
        Space.sm + MediaQuery.viewInsetsOf(context).bottom * 0,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: <Widget>[
          Expanded(
            child: TextField(
              controller: controller,
              focusNode: focusNode,
              minLines: 1,
              maxLines: 4,
              maxLength: 1000,
              textInputAction: TextInputAction.newline,
              decoration: InputDecoration(
                hintText: Tr.of(
                  context,
                  ar: 'أضف تعليقًا…',
                  en: 'Add a comment…',
                ),
                counterText: '',
              ),
            ),
          ),
          const SizedBox(width: Space.sm),
          WingsIconButton(
            icon: Icons.send_rounded,
            filled: true,
            onPressed: sending
                ? null
                : () {
                    final text = controller.text;
                    if (text.trim().isEmpty) return;
                    controller.clear();
                    onSend(text);
                  },
          ),
        ],
      ),
    );
  }
}

class _CommentTile extends ConsumerStatefulWidget {
  const _CommentTile({required this.comment, required this.onReply});

  final EpisodeComment comment;
  final void Function(String text) onReply;

  @override
  ConsumerState<_CommentTile> createState() => _CommentTileState();
}

class _CommentTileState extends ConsumerState<_CommentTile> {
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
          Space.md,
          Space.sm,
          Space.md,
          Space.sm,
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
                size: 34,
              ),
            ),
            const SizedBox(width: Space.sm),
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
                        _relative(context, comment.createdAt),
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
                  const SizedBox(height: 2),
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
                      height: 1.5,
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
                        return Column(
                          children: <Widget>[
                            for (final reply in replies)
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

  String _relative(BuildContext context, DateTime time) {
    final diff = DateTime.now().difference(time);
    if (diff.inMinutes < 1) return Tr.of(context, ar: 'الآن', en: 'now');
    if (diff.inMinutes < 60) return '${diff.inMinutes}m';
    if (diff.inHours < 24) return '${diff.inHours}h';
    if (diff.inDays < 30) return '${diff.inDays}d';
    return '${diff.inDays ~/ 30}mo';
  }
}
