import 'dart:async';

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../app/theme/app_tokens.dart';
import '../../app/theme/context_ext.dart';
import '../../core/services/app_feedback.dart';
import '../../core/utils/tr.dart';
import '../../core/widgets/wings_buttons.dart';
import '../../core/widgets/wings_layout.dart';
import '../../data/models/community.dart';
import '../../data/models/social.dart';
import '../auth/sign_in_prompt.dart';
import '../stickers/comment_draft.dart';
import 'comment_composer.dart';
import 'comment_tile.dart';

/// Full comments page, modelled on YouTube: the newest page streams live, older
/// pages are fetched with a cursor as the reader scrolls, and the composer
/// stays pinned at the bottom.
///
/// Cost control: one listener, one 20-document page per scroll, and no
/// aggregation read for every new comment — the count is cached and adjusted
/// locally.
class EpisodeCommentsScreen extends ConsumerStatefulWidget {
  const EpisodeCommentsScreen({
    super.key,
    required this.episodeId,
    this.episodeTitle = '',
  });

  final String episodeId;
  final String episodeTitle;

  @override
  ConsumerState<EpisodeCommentsScreen> createState() =>
      _EpisodeCommentsScreenState();
}

class _EpisodeCommentsScreenState extends ConsumerState<EpisodeCommentsScreen> {
  final TextEditingController _composer = TextEditingController();
  final ScrollController _scroll = ScrollController();
  final List<EpisodeComment> _older = <EpisodeComment>[];
  DocumentSnapshot<Map<String, dynamic>>? _cursor;
  bool _hasMore = false;
  bool _loadingMore = false;
  bool _sending = false;
  EpisodeCounts _counts = EpisodeCounts.zero;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
    _loadCounts();
  }

  @override
  void dispose() {
    _scroll
      ..removeListener(_onScroll)
      ..dispose();
    _composer.dispose();
    super.dispose();
  }

  /// Medal ranks by comment id; medals belong to the first commenters, not to
  /// the newest comment in the list.
  Map<String, int> get _ranks =>
      ref.watch(topCommentRanksProvider(widget.episodeId)).asData?.value ??
      const <String, int>{};

  Future<void> _loadCounts() async {
    try {
      final counts = await ref
          .read(socialRepositoryProvider)
          .counts(widget.episodeId);
      if (mounted) setState(() => _counts = counts);
    } on Object {
      // The header simply shows no number when the counts cannot be read.
    }
  }

  void _onScroll() {
    if (!_scroll.hasClients) return;
    final remaining =
        _scroll.position.maxScrollExtent - _scroll.position.pixels;
    if (remaining < 600 && _hasMore && !_loadingMore) unawaited(_loadMore());
  }

  Future<void> _loadMore() async {
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

  Future<bool> _send(
    String text, {
    String? parentId,
    String? stickerId,
    List<MentionRef> mentions = const <MentionRef>[],
    List<AnimeRef> animeRefs = const <AnimeRef>[],
  }) async {
    final user = ref.read(authProvider);
    final profile = ref.read(profileProvider);
    if (user == null) {
      await showSignInPrompt(
        context,
        message: Tr.of(
          context,
          ar: 'سجّل الدخول لتتمكن من كتابة تعليق أو الرد على تعليق.',
          en: 'Sign in to write a comment or reply to one.',
        ),
      );
      return false;
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
      return false;
    }
    final draft = CommentDraft(
      text: text,
      stickerId: stickerId,
      mentions: mentions,
      animeRefs: animeRefs,
    );
    if (!draft.canSend) return false;
    setState(() => _sending = true);
    try {
      await ref
          .read(socialRepositoryProvider)
          .addComment(
            episodeId: widget.episodeId,
            author: profile,
            text: draft.trimmedText,
            parentId: parentId,
            stickerId: draft.normalizedStickerId,
            mentions: draft.mentions,
            animeRefs: draft.animeRefs,
          );
      unawaited(AppFeedback.publish());
      if (!mounted) return false;
      setState(() {
        _counts = EpisodeCounts(
          likes: _counts.likes,
          dislikes: _counts.dislikes,
          comments: _counts.comments + 1,
        );
      });
      return true;
    } on StateError catch (error) {
      if (!mounted) return false;
      context.showSnack(
        error.message == 'comment-too-fast'
            ? Tr.of(
                context,
                ar: 'انتظر لحظات قبل إرسال تعليق آخر.',
                en: 'Wait a moment before posting another comment.',
              )
            : Tr.of(
                context,
                ar: 'تعذر إرسال التعليق.',
                en: 'Could not post the comment.',
              ),
        isError: true,
      );
      return false;
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
      return false;
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final user = ref.watch(authProvider);

    return Scaffold(
      appBar: WingsAppBar(
        showBack: true,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              Tr.of(context, ar: 'التعليقات', en: 'Comments'),
              style: context.text.titleMedium,
            ),
            if (widget.episodeTitle.isNotEmpty)
              Text(
                widget.episodeTitle,
                style: context.text.labelSmall?.copyWith(
                  color: palette.textMuted,
                ),
              ),
          ],
        ),
      ),
      body: Column(
        children: <Widget>[
          Expanded(
            child: StreamBuilder<List<EpisodeComment>>(
              stream: ref
                  .read(socialRepositoryProvider)
                  .watchLatest(widget.episodeId),
              builder: (context, snapshot) {
                final live = snapshot.data ?? const <EpisodeComment>[];
                final seen = <String>{};
                final merged = <EpisodeComment>[
                  for (final comment in <EpisodeComment>[...live, ..._older])
                    if (seen.add(comment.id)) comment,
                ]..sort((a, b) => b.createdAt.compareTo(a.createdAt));

                if (snapshot.connectionState == ConnectionState.waiting &&
                    merged.isEmpty) {
                  return const Center(child: CircularProgressIndicator());
                }

                final ranks = _ranks;
                return ListView.builder(
                  controller: _scroll,
                  padding: const EdgeInsets.only(bottom: Space.lg),
                  itemCount: merged.length + 2,
                  itemBuilder: (context, index) {
                    if (index == 0) {
                      return _Header(
                        count: merged.isEmpty
                            ? _counts.comments
                            : (_counts.comments > merged.length
                                  ? _counts.comments
                                  : merged.length),
                      );
                    }
                    if (index == merged.length + 1) {
                      if (_loadingMore) {
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
                      if (!_hasMore && merged.isNotEmpty) {
                        return Padding(
                          padding: const EdgeInsets.all(Space.lg),
                          child: Center(
                            child: Text(
                              Tr.of(
                                context,
                                ar: 'لا توجد تعليقات أقدم.',
                                en: 'No older comments.',
                              ),
                              style: context.text.labelSmall?.copyWith(
                                color: palette.textMuted,
                              ),
                            ),
                          ),
                        );
                      }
                      return const SizedBox.shrink();
                    }
                    final comment = merged[index - 1];
                    return Column(
                      children: <Widget>[
                        CommentTile(
                          comment: comment,
                          rank: ranks[comment.id],
                          onReply: (text, stickerId, mentions, animeRefs) =>
                              _send(
                                text,
                                parentId: comment.id,
                                stickerId: stickerId,
                                mentions: mentions,
                                animeRefs: animeRefs,
                              ),
                        ),
                        if (index != merged.length)
                          Divider(
                            height: 1,
                            color: palette.border,
                            indent: Space.lg + 36 + Space.md,
                            endIndent: Space.lg,
                          ),
                      ],
                    );
                  },
                );
              },
            ),
          ),
          Divider(height: 1, color: palette.border),
          if (user == null)
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.all(Space.lg),
                child: WingsButton(
                  label: Tr.of(
                    context,
                    ar: 'سجّل الدخول للتعليق',
                    en: 'Sign in to comment',
                  ),
                  icon: Icons.login_rounded,
                  expand: true,
                  onPressed: () => showSignInPrompt(
                    context,
                    message: Tr.of(
                      context,
                      ar: 'سجّل الدخول لتتمكن من كتابة تعليق ومتابعة الردود.',
                      en: 'Sign in to write comments and reply to others.',
                    ),
                  ),
                ),
              ),
            )
          else
            SafeArea(
              top: false,
              child: CommentComposer(
                controller: _composer,
                sending: _sending,
                onSend: (text, stickerId, mentions, animeRefs) => _send(
                  text,
                  stickerId: stickerId,
                  mentions: mentions,
                  animeRefs: animeRefs,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        Space.lg,
        Space.md,
        Space.lg,
        Space.sm,
      ),
      child: Row(
        children: <Widget>[
          Text(
            Tr.of(context, ar: 'التعليقات', en: 'Comments'),
            style: context.text.titleSmall,
          ),
          const SizedBox(width: Space.sm),
          Text(
            '${count.clamp(0, 1 << 31)}',
            style: context.text.labelMedium?.copyWith(color: palette.textMuted),
          ),
          const Spacer(),
          Row(
            children: <Widget>[
              Icon(Icons.sort_rounded, size: 14, color: palette.textMuted),
              const SizedBox(width: 4),
              Text(
                Tr.of(context, ar: 'الأحدث', en: 'Newest'),
                style: context.text.labelSmall?.copyWith(
                  color: palette.textMuted,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
