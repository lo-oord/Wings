import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme/app_tokens.dart';
import '../../app/theme/context_ext.dart';
import '../../core/errors/user_facing_error.dart';
import '../../core/utils/tr.dart';
import '../../core/widgets/wings_feedback.dart';
import 'community_providers.dart';
import 'post_card.dart';

/// The posts of one account, used by both the public profile and the signed-in
/// member's own profile. Both pages read the same `posts` collection with the
/// same cursor, so a post can never appear on one profile and be missing from
/// the other.
class ProfilePostsSection extends ConsumerWidget {
  const ProfilePostsSection({super.key, required this.uid, this.flat = true});

  final String uid;
  final bool flat;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.palette;
    final key = 'user:$uid';
    final state = ref.watch(postsPageProvider(key));
    final controller = ref.read(postsPageProvider(key).notifier);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Padding(
          padding: const EdgeInsetsDirectional.fromSTEB(
            Space.lg,
            0,
            Space.lg,
            Space.md,
          ),
          child: Row(
            children: <Widget>[
              Icon(
                Icons.dynamic_feed_rounded,
                size: 17,
                color: palette.primary,
              ),
              const SizedBox(width: 6),
              Text(
                Tr.of(context, ar: 'المنشورات', en: 'Posts'),
                style: context.text.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const Spacer(),
              if (state.posts.isNotEmpty)
                Text(
                  '${state.posts.length}${state.hasMore ? '+' : ''}',
                  style: context.text.labelSmall?.copyWith(
                    color: palette.textMuted,
                  ),
                ),
            ],
          ),
        ),
        if (state.loading && state.posts.isEmpty)
          const Padding(
            padding: EdgeInsets.all(Space.lg),
            child: WingsLoading(),
          )
        else if (state.error != null && state.posts.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: Space.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  loadFailedText(context),
                  style: context.text.labelSmall?.copyWith(
                    color: palette.textMuted,
                  ),
                ),
                TextButton(
                  onPressed: controller.load,
                  child: Text(
                    Tr.of(context, ar: 'إعادة المحاولة', en: 'Retry'),
                  ),
                ),
              ],
            ),
          )
        else if (state.posts.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: Space.lg),
            child: Text(
              Tr.of(context, ar: 'لا منشورات بعد.', en: 'No posts yet.'),
              style: context.text.labelSmall?.copyWith(
                color: palette.textMuted,
              ),
            ),
          )
        else ...<Widget>[
          for (final post in state.posts)
            PostCard(
              key: ValueKey<String>(post.id),
              post: post,
              flat: flat,
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
