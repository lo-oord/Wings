import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/localization/app_localizations.dart';
import '../../app/theme/app_tokens.dart';
import '../../app/theme/context_ext.dart';
import '../../core/errors/user_facing_error.dart';
import '../../core/utils/tr.dart';
import '../../core/widgets/wings_feedback.dart';
import '../../core/widgets/wings_layout.dart';
import 'community_providers.dart';
import 'post_card.dart';

/// Posts the signed-in member saved. The list is private: it is read from
/// `users/{uid}/savedPosts` and the rules refuse everybody else.
class SavedPostsScreen extends ConsumerWidget {
  const SavedPostsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.palette;
    final saved = ref.watch(savedPostsProvider);

    return Scaffold(
      backgroundColor: palette.background,
      appBar: WingsAppBar(
        showBack: true,
        title: Text(
          Tr.of(context, ar: 'المنشورات المحفوظة', en: 'Saved posts'),
        ),
      ),
      body: saved.when(
        loading: () => const WingsLoading(),
        error: (error, stack) => WingsEmptyState(
          icon: Icons.cloud_off_rounded,
          title: AppLocalizations.of(context).commonErrorTitle,
          message: loadFailedText(context),
          actionLabel: AppLocalizations.of(context).commonRetry,
          onAction: () => ref.invalidate(savedPostsProvider),
        ),
        data: (posts) {
          if (posts.isEmpty) {
            return WingsEmptyState(
              icon: Icons.bookmark_border_rounded,
              title: Tr.of(
                context,
                ar: 'لا منشورات محفوظة',
                en: 'Nothing saved yet',
              ),
              message: Tr.of(
                context,
                ar: 'اضغط «حفظ» على أي منشور لتعود إليه لاحقًا.',
                en: 'Tap Save on any post to keep it for later.',
              ),
            );
          }
          return RefreshIndicator(
            onRefresh: () async => ref.invalidate(savedPostsProvider),
            child: ListView.builder(
              padding: const EdgeInsets.only(top: Space.sm, bottom: Space.xxxl),
              itemCount: posts.length,
              itemBuilder: (context, index) {
                final post = posts[index];
                return PostCard(
                  post: post,
                  onDeleted: () => ref.invalidate(savedPostsProvider),
                  onChanged: (_) => ref.invalidate(savedPostsProvider),
                );
              },
            ),
          );
        },
      ),
    );
  }
}
