import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../app/theme/app_tokens.dart';
import '../../app/theme/context_ext.dart';
import '../../core/services/app_feedback.dart';
import '../../core/utils/formatters.dart';
import '../../core/utils/tr.dart';
import '../../core/widgets/wings_buttons.dart';
import '../../data/models/social.dart';
import 'comment_tile.dart';

/// YouTube-inspired interaction area under the player.
///
/// The block shows what a viewer needs at a glance — reactions, share,
/// download, save and a short preview of the newest comments — and hands the
/// rest to [EpisodeCommentsScreen] through a single "all comments" action.
/// Only one listener (the newest page) and a cached count are used here.
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

  /// Embedded mode flows with the page under the player; the other mode fills
  /// a bottom sheet.
  final bool embedded;

  /// True when the episode itself is bookmarked in «حلقاتي».
  final bool savedToLibrary;
  final VoidCallback? onDownload;
  final VoidCallback? onToggleSave;

  @override
  ConsumerState<EpisodeSocialSection> createState() =>
      _EpisodeSocialSectionState();
}

class _EpisodeSocialSectionState extends ConsumerState<EpisodeSocialSection> {
  ReactionType? _reaction;
  EpisodeCounts _counts = EpisodeCounts.zero;
  bool _countsLoading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final repository = ref.read(socialRepositoryProvider);
      final user = ref.read(authProvider);
      final results = await Future.wait<Object?>(<Future<Object?>>[
        repository.counts(widget.episodeId),
        if (user != null)
          repository.myReaction(widget.episodeId, user.id)
        else
          Future<Object?>.value(),
      ]);
      if (!mounted) return;
      setState(() {
        _counts = results[0] as EpisodeCounts;
        _reaction = results.length > 1 ? results[1] as ReactionType? : null;
        _countsLoading = false;
      });
    } on Object {
      if (mounted) setState(() => _countsLoading = false);
    }
  }

  Future<void> _toggleReaction(ReactionType type) async {
    final user = ref.read(authProvider);
    if (user == null) {
      context.push('/login');
      return;
    }
    final previous = _reaction;
    final next = previous == type ? null : type;
    // A single soft click and light pulse per change; removing a reaction is
    // deliberately quieter than adding one.
    if (next == null) {
      unawaited(AppFeedback.reactionRemoved());
    } else {
      unawaited(AppFeedback.reaction());
    }
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
    } on Object {
      if (!mounted) return;
      setState(() => _reaction = previous);
      unawaited(_load());
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

  void _openComments() {
    context.push(
      '/episode/${Uri.encodeComponent(widget.episodeId)}/comments',
      extra: widget.episodeTitle,
    );
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final user = ref.watch(authProvider);

    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        _ActionBar(
          reaction: _reaction,
          counts: _counts,
          countsLoading: _countsLoading,
          savedToLibrary: widget.savedToLibrary,
          onReaction: _toggleReaction,
          onShare: _share,
          onDownload: widget.onDownload,
          onToggleSave: widget.onToggleSave,
          onComments: _openComments,
        ),
        Divider(height: 1, color: palette.border),
        if (user == null)
          _SignInPrompt(onSignIn: () => context.push('/login'))
        else ...<Widget>[
          _Composer(onOpenAll: _openComments),
          _CommentPreview(
            episodeId: widget.episodeId,
            count: _counts.comments,
            onOpenAll: _openComments,
          ),
        ],
      ],
    );

    if (widget.embedded) return content;

    return Material(
      color: palette.background,
      child: SafeArea(top: false, child: SingleChildScrollView(child: content)),
    );
  }
}

/// Row of actions under the video. The reaction pair shares one segmented pill
/// while every other action is its own pill, with a comfortable gap and a
/// vertical rhythm instead of a cramped line of icons.
class _ActionBar extends StatelessWidget {
  const _ActionBar({
    required this.reaction,
    required this.counts,
    required this.countsLoading,
    required this.savedToLibrary,
    required this.onReaction,
    required this.onShare,
    required this.onDownload,
    required this.onToggleSave,
    required this.onComments,
  });

  final ReactionType? reaction;
  final EpisodeCounts counts;
  final bool countsLoading;
  final bool savedToLibrary;
  final void Function(ReactionType type) onReaction;
  final VoidCallback onShare;
  final VoidCallback? onDownload;
  final VoidCallback? onToggleSave;
  final VoidCallback onComments;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(
        Space.lg,
        Space.md,
        Space.lg,
        Space.md,
      ),
      child: Row(
        children: <Widget>[
          Container(
            decoration: BoxDecoration(
              color: palette.surfaceAlt,
              borderRadius: BorderRadius.circular(Radii.pill),
              border: Border.all(color: palette.border),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                _ReactionButton(
                  icon: reaction == ReactionType.like
                      ? Icons.thumb_up_alt_rounded
                      : Icons.thumb_up_alt_outlined,
                  count: countsLoading ? null : counts.likes,
                  active: reaction == ReactionType.like,
                  onTap: () => onReaction(ReactionType.like),
                ),
                Container(width: 1, height: 20, color: palette.border),
                _ReactionButton(
                  icon: reaction == ReactionType.dislike
                      ? Icons.thumb_down_alt_rounded
                      : Icons.thumb_down_alt_outlined,
                  count: countsLoading ? null : counts.dislikes,
                  active: reaction == ReactionType.dislike,
                  onTap: () => onReaction(ReactionType.dislike),
                ),
              ],
            ),
          ),
          const SizedBox(width: Space.sm),
          _PillAction(
            icon: Icons.ios_share_rounded,
            label: Tr.of(context, ar: 'مشاركة', en: 'Share'),
            onTap: onShare,
          ),
          if (onDownload != null) ...<Widget>[
            const SizedBox(width: Space.sm),
            _PillAction(
              icon: Icons.download_rounded,
              label: Tr.of(context, ar: 'تنزيل', en: 'Download'),
              onTap: onDownload!,
            ),
          ],
          if (onToggleSave != null) ...<Widget>[
            const SizedBox(width: Space.sm),
            _PillAction(
              icon: savedToLibrary
                  ? Icons.bookmark_rounded
                  : Icons.bookmark_border_rounded,
              label: Tr.of(
                context,
                ar: savedToLibrary ? 'محفوظة' : 'حفظ الحلقة',
                en: savedToLibrary ? 'Saved' : 'Save episode',
              ),
              active: savedToLibrary,
              onTap: onToggleSave!,
            ),
          ],
          const SizedBox(width: Space.sm),
          _PillAction(
            icon: Icons.mode_comment_outlined,
            label: Tr.of(context, ar: 'تعليقات', en: 'Comments'),
            onTap: onComments,
          ),
        ],
      ),
    );
  }
}

class _ReactionButton extends StatefulWidget {
  const _ReactionButton({
    required this.icon,
    this.count,
    this.active = false,
    required this.onTap,
  });

  final IconData icon;
  final int? count;
  final bool active;
  final VoidCallback onTap;

  @override
  State<_ReactionButton> createState() => _ReactionButtonState();
}

class _ReactionButtonState extends State<_ReactionButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _bounce = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 260),
    value: 1,
  );
  late final Animation<double> _scale = TweenSequence<double>(
    <TweenSequenceItem<double>>[
      TweenSequenceItem(tween: Tween<double>(begin: 1, end: 1.28), weight: 40),
      TweenSequenceItem(
        tween: Tween<double>(
          begin: 1.28,
          end: 1,
        ).chain(CurveTween(curve: Curves.easeOutBack)),
        weight: 60,
      ),
    ],
  ).animate(_bounce);

  @override
  void didUpdateWidget(_ReactionButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    // The icon pops only when the reaction actually turns on, never on every
    // rebuild, so the row stays calm.
    if (widget.active && !oldWidget.active) _bounce.forward(from: 0);
  }

  @override
  void dispose() {
    _bounce.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final color = widget.active ? palette.primary : palette.textSecondary;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    return InkWell(
      onTap: () {
        widget.onTap();
        if (!widget.active && !reduceMotion) _bounce.forward(from: 0);
      },
      borderRadius: BorderRadius.circular(Radii.pill),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: Space.md,
          vertical: Space.sm + 1,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            ScaleTransition(
              scale: _scale,
              child: Icon(widget.icon, size: 17, color: color),
            ),
            if (widget.count != null && widget.count! > 0) ...<Widget>[
              const SizedBox(width: 5),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 180),
                transitionBuilder: (child, animation) => FadeTransition(
                  opacity: animation,
                  child: SizeTransition(
                    sizeFactor: animation,
                    axis: Axis.horizontal,
                    child: child,
                  ),
                ),
                child: Text(
                  formatCount(widget.count),
                  key: ValueKey<int>(widget.count!),
                  style: context.text.labelSmall?.copyWith(color: color),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _PillAction extends StatelessWidget {
  const _PillAction({
    required this.icon,
    required this.label,
    required this.onTap,
    this.active = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final color = active ? palette.primary : palette.textSecondary;
    return Material(
      color: active
          ? palette.primary.withValues(alpha: 0.12)
          : palette.surfaceAlt,
      borderRadius: BorderRadius.circular(Radii.pill),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(Radii.pill),
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: Space.md,
            vertical: Space.sm + 1,
          ),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(Radii.pill),
            border: Border.all(
              color: active ? Colors.transparent : palette.border,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(icon, size: 17, color: color),
              const SizedBox(width: 6),
              Text(
                label,
                style: context.text.labelSmall?.copyWith(color: color),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SignInPrompt extends StatelessWidget {
  const _SignInPrompt({required this.onSignIn});

  final VoidCallback onSignIn;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(Space.lg),
    child: Column(
      children: <Widget>[
        Icon(Icons.forum_outlined, size: 26, color: context.palette.textMuted),
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
  );
}

/// Short preview: only three comments are streamed on the player screen; the
/// rest wait behind the "all comments" action so the page stays cheap.
class _CommentPreview extends ConsumerWidget {
  const _CommentPreview({
    required this.episodeId,
    required this.count,
    required this.onOpenAll,
  });

  final String episodeId;
  final int count;
  final VoidCallback onOpenAll;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.palette;
    final ranks =
        ref.watch(topCommentRanksProvider(episodeId)).asData?.value ??
        const <String, int>{};

    return StreamBuilder<List<EpisodeComment>>(
      stream: ref
          .read(socialRepositoryProvider)
          .watchLatest(episodeId, limit: 3),
      builder: (context, snapshot) {
        final comments = snapshot.data ?? const <EpisodeComment>[];
        final total = count > comments.length ? count : comments.length;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(
                Space.lg,
                Space.md,
                Space.sm,
                Space.xs,
              ),
              child: Row(
                children: <Widget>[
                  Text(
                    Tr.of(context, ar: 'التعليقات', en: 'Comments'),
                    style: context.text.titleSmall,
                  ),
                  const SizedBox(width: Space.sm),
                  Text(
                    formatCount(total),
                    style: context.text.labelSmall?.copyWith(
                      color: palette.textMuted,
                    ),
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: onOpenAll,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        Text(
                          Tr.of(context, ar: 'عرض الكل', en: 'View all'),
                          style: context.text.labelSmall?.copyWith(
                            color: palette.primary,
                          ),
                        ),
                        Icon(
                          context.isRtl
                              ? Icons.chevron_left_rounded
                              : Icons.chevron_right_rounded,
                          size: 16,
                          color: palette.primary,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            if (comments.isEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  Space.lg,
                  0,
                  Space.lg,
                  Space.md,
                ),
                child: Text(
                  Tr.of(
                    context,
                    ar: 'لا توجد تعليقات بعد. كن أول من يعلّق!',
                    en: 'No comments yet. Be the first to comment!',
                  ),
                  style: context.text.bodySmall?.copyWith(
                    color: palette.textMuted,
                  ),
                ),
              )
            else
              for (var index = 0; index < comments.length; index++) ...<Widget>[
                CommentTile(
                  comment: comments[index],
                  rank: ranks[comments[index].id],
                  maxReplyPreview: 1,
                  onReply: (_) => onOpenAll(),
                ),
                if (index != comments.length - 1)
                  Divider(
                    height: 1,
                    color: palette.border,
                    indent: Space.lg + 36 + Space.md,
                    endIndent: Space.lg,
                  ),
              ],
            if (comments.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  Space.lg,
                  Space.xs,
                  Space.lg,
                  Space.sm,
                ),
                child: OutlinedButton.icon(
                  onPressed: onOpenAll,
                  icon: const Icon(Icons.forum_outlined, size: 16),
                  label: Text(
                    total > comments.length
                        ? Tr.of(
                            context,
                            ar: 'كل التعليقات (${formatCount(total)})',
                            en: 'All comments (${formatCount(total)})',
                          )
                        : Tr.of(
                            context,
                            ar: 'فتح صفحة التعليقات',
                            en: 'Open the comments page',
                          ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

/// Looks like the YouTube composer but does not open a keyboard: writing a
/// comment happens on the dedicated comments page, so the player screen stays
/// free of a second text input and a second listener.
class _Composer extends StatelessWidget {
  const _Composer({required this.onOpenAll});

  final VoidCallback onOpenAll;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        Space.lg,
        Space.sm,
        Space.lg,
        Space.xs,
      ),
      child: Material(
        color: palette.surfaceAlt,
        borderRadius: BorderRadius.circular(Radii.pill),
        child: InkWell(
          onTap: onOpenAll,
          borderRadius: BorderRadius.circular(Radii.pill),
          child: Container(
            padding: const EdgeInsets.symmetric(
              horizontal: Space.md + 2,
              vertical: Space.sm + 2,
            ),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(Radii.pill),
              border: Border.all(color: palette.border),
            ),
            child: Row(
              children: <Widget>[
                Icon(Icons.edit_outlined, size: 16, color: palette.textMuted),
                const SizedBox(width: Space.sm),
                Expanded(
                  child: Text(
                    Tr.of(context, ar: 'أضف تعليقًا…', en: 'Add a comment…'),
                    style: context.text.bodySmall?.copyWith(
                      color: palette.textMuted,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
