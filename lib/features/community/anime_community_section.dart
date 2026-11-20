import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/router/route_paths.dart';
import '../../app/theme/app_tokens.dart';
import '../../app/theme/context_ext.dart';
import '../../core/utils/tr.dart';
import '../../core/widgets/wings_feedback.dart';
import '../../data/models/anime.dart';
import '../../data/models/community.dart';
import 'community_providers.dart';
import 'post_card.dart';

/// The social side of an anime, inside the existing details page.
///
/// It reads `posts` by `animeIds`, the same documents the feed shows and the
/// same ids the hashtag picker stores, so a post about this anime is one post
/// everywhere. Pages with a time cursor; no per-anime collection, no full scan.
class AnimeCommunitySection extends ConsumerWidget {
  const AnimeCommunitySection({super.key, required this.anime});

  final Anime anime;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.palette;
    final key = 'anime:${anime.id}';
    final state = ref.watch(postsPageProvider(key));
    final controller = ref.read(postsPageProvider(key).notifier);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Padding(
          padding: const EdgeInsetsDirectional.fromSTEB(
            Space.lg,
            Space.xl,
            Space.lg,
            Space.sm,
          ),
          child: Row(
            children: <Widget>[
              Icon(Icons.forum_outlined, size: 18, color: palette.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  Tr.of(
                    context,
                    ar: 'منشورات المجتمع عن ${anime.title}',
                    en: 'Community posts about ${anime.title}',
                  ),
                  style: context.text.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ),
        if (state.loading)
          const Padding(
            padding: EdgeInsets.all(Space.lg),
            child: WingsLoading(),
          )
        else if (state.error != null && state.posts.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: Space.lg),
            child: Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    Tr.of(
                      context,
                      ar: 'تعذّر تحميل منشورات المجتمع.',
                      en: 'Community posts could not be loaded.',
                    ),
                    style: context.text.labelSmall?.copyWith(
                      color: palette.textMuted,
                    ),
                  ),
                ),
                TextButton(
                  onPressed: controller.load,
                  child: Text(Tr.of(context, ar: 'إعادة', en: 'Retry')),
                ),
              ],
            ),
          )
        else if (state.posts.isEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(Space.lg, 0, Space.lg, Space.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  Tr.of(
                    context,
                    ar: 'لا منشورات عن هذا الأنمي بعد. كن أول من يشارك رأيه.',
                    en: 'No posts about this anime yet. Be the first to share.',
                  ),
                  style: context.text.labelSmall?.copyWith(
                    color: palette.textMuted,
                    height: 1.6,
                  ),
                ),
                const SizedBox(height: Space.xs),
                TextButton.icon(
                  onPressed: () => context.push(RoutePaths.communityCompose),
                  icon: const Icon(Icons.edit_outlined, size: 16),
                  label: Text(
                    Tr.of(context, ar: 'اكتب منشورًا', en: 'Write a post'),
                  ),
                ),
              ],
            ),
          )
        else ...<Widget>[
          for (final post in state.posts)
            PostCard(
              key: ValueKey<String>(post.id),
              post: post,
              flat: true,
              onChanged: controller.replace,
              onDeleted: () => controller.remove(post.id),
            ),
          if (state.hasMore)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                Space.lg,
                0,
                Space.lg,
                Space.lg,
              ),
              child: SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: state.loadingMore ? null : controller.loadMore,
                  child: state.loadingMore
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text(Tr.of(context, ar: 'عرض المزيد', en: 'Load more')),
                ),
              ),
            ),
        ],
      ],
    );
  }
}

/// Small helper so the post composer can open already pointed at an anime.
String animeHashtag(Anime anime) => '#${anime.title}';

AnimeRef animeRefOf(Anime anime) =>
    AnimeRef(id: anime.id, title: anime.title, imageUrl: anime.imageUrl ?? '');
