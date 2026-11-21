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
import '../../core/widgets/wings_buttons.dart';
import '../../core/widgets/wings_feedback.dart';
import '../../core/widgets/wings_layout.dart';
import '../../data/models/community.dart';
import '../auth/sign_in_prompt.dart';
import 'community_providers.dart';
import 'post_card.dart';

/// The community home: newest posts and the posts of the accounts the member
/// follows. It is a tab inside the existing shell, not a separate app.
class CommunityScreen extends ConsumerStatefulWidget {
  const CommunityScreen({super.key});

  @override
  ConsumerState<CommunityScreen> createState() => _CommunityScreenState();
}

class _CommunityScreenState extends ConsumerState<CommunityScreen> {
  CommunityTab _tab = CommunityTab.forYou;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final uid = ref.watch(authProvider)?.id;
    // Firebase restores a saved session asynchronously; never show the sign-in
    // pitch during that first moment.
    final authResolved = ref.watch(authResolvedProvider);
    final online = ref.watch(onlineProvider).value;

    return Scaffold(
      backgroundColor: palette.background,
      appBar: WingsAppBar(
        title: Text(
          Tr.of(context, ar: 'المجتمع', en: 'Community'),
          style: context.text.titleLarge?.copyWith(fontWeight: FontWeight.w700),
        ),
        actions: <Widget>[
          WingsIconButton(
            icon: Icons.search_rounded,
            tooltip: Tr.of(context, ar: 'بحث', en: 'Search'),
            onPressed: () => context.push(RoutePaths.communitySearch),
          ),
          WingsIconButton(
            icon: Icons.movie_filter_rounded,
            tooltip: Tr.of(context, ar: 'ريلز', en: 'Reels'),
            onPressed: () => context.push(RoutePaths.communityReels),
          ),
          WingsIconButton(
            icon: Icons.autorenew_rounded,
            tooltip: Tr.of(context, ar: 'تحديث', en: 'Refresh'),
            onPressed: () => ref
                .read(communityFeedProvider(_tab).notifier)
                .load(refresh: true),
          ),
          const SizedBox(width: Space.xs),
          WingsIconButton(
            icon: Icons.bookmark_rounded,
            tooltip: Tr.of(context, ar: 'المحفوظة', en: 'Saved'),
            onPressed: () {
              if (uid == null) {
                showSignInPrompt(
                  context,
                  message: Tr.of(
                    context,
                    ar: 'سجّل الدخول لعرض منشوراتك المحفوظة',
                    en: 'Sign in to open your saved posts',
                  ),
                );
                return;
              }
              context.push(RoutePaths.communitySaved);
            },
          ),
          const SizedBox(width: Space.xs),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _compose(context),
        backgroundColor: palette.primary,
        foregroundColor: palette.onPrimary,
        icon: const Icon(Icons.edit_rounded, size: 20),
        label: Text(
          Tr.of(context, ar: 'منشور', en: 'Post'),
          style: context.text.labelMedium?.copyWith(
            color: palette.onPrimary,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      body: uid == null
          ? (authResolved
                ? const _SignedOutCommunity()
                : const Center(
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ))
          : Column(
              children: <Widget>[
                if (online == false)
                  Container(
                    width: double.infinity,
                    margin: const EdgeInsets.fromLTRB(
                      Space.lg,
                      Space.xs,
                      Space.lg,
                      0,
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: Space.sm,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: palette.surfaceAlt,
                      borderRadius: BorderRadius.circular(Radii.sm),
                      border: Border.all(color: palette.border),
                    ),
                    child: Row(
                      children: <Widget>[
                        Icon(
                          Icons.wifi_off_rounded,
                          size: 14,
                          color: palette.textMuted,
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            Tr.of(
                              context,
                              ar: 'لا يوجد اتصال. تُعرض المنشورات المحفوظة، وسيعود التحديث تلقائيًا.',
                              en: 'No connection. Cached posts are shown and refresh resumes automatically.',
                            ),
                            style: context.text.labelSmall?.copyWith(
                              color: palette.textSecondary,
                              fontSize: 9,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    Space.lg,
                    Space.xs,
                    Space.lg,
                    0,
                  ),
                  child: Row(
                    children: <Widget>[
                      Expanded(
                        child: _TabChip(
                          label: Tr.of(context, ar: 'لك', en: 'For you'),
                          icon: Icons.auto_awesome_rounded,
                          selected: _tab == CommunityTab.forYou,
                          onTap: () =>
                              setState(() => _tab = CommunityTab.forYou),
                        ),
                      ),
                      const SizedBox(width: Space.xs),
                      Expanded(
                        child: _TabChip(
                          label: Tr.of(context, ar: 'الأحدث', en: 'Latest'),
                          icon: Icons.bolt_rounded,
                          selected: _tab == CommunityTab.latest,
                          onTap: () =>
                              setState(() => _tab = CommunityTab.latest),
                        ),
                      ),
                      const SizedBox(width: Space.xs),
                      Expanded(
                        child: _TabChip(
                          label: Tr.of(context, ar: 'أتابعهم', en: 'Following'),
                          icon: Icons.people_alt_outlined,
                          selected: _tab == CommunityTab.following,
                          onTap: () =>
                              setState(() => _tab = CommunityTab.following),
                        ),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    Space.lg,
                    Space.xs,
                    Space.lg,
                    0,
                  ),
                  child: Text(
                    _tab == CommunityTab.forYou
                        ? Tr.of(
                            context,
                            ar: 'ترتيب شخصي حسب اهتماماتك',
                            en: 'Personal order based on your interests',
                          )
                        : _tab == CommunityTab.latest
                        ? Tr.of(context, ar: 'الأحدث أولًا', en: 'Newest first')
                        : Tr.of(
                            context,
                            ar: 'منشورات من تتابعهم',
                            en: 'Posts from accounts you follow',
                          ),
                    style: context.text.labelSmall?.copyWith(
                      color: palette.textMuted,
                      fontSize: 10,
                    ),
                  ),
                ),
                const SizedBox(height: Space.sm),
                Expanded(child: _Feed(tab: _tab)),
              ],
            ),
      bottomNavigationBar: null,
    );
  }

  Future<void> _compose(BuildContext context) async {
    if (ref.read(authProvider) == null) {
      showSignInPrompt(
        context,
        message: Tr.of(
          context,
          ar: 'سجّل الدخول لتشارك منشورًا في المجتمع',
          en: 'Sign in to share a post with the community',
        ),
      );
      return;
    }
    final published = await context.push<Post>(RoutePaths.communityCompose);
    if (published == null || !mounted) return;
    // The new post appears at the top of «الأحدث» immediately, without a full
    // reload of the feed.
    ref
        .read(communityFeedProvider(CommunityTab.latest).notifier)
        .prepend(published);
  }
}

class _SignedOutCommunity extends StatelessWidget {
  const _SignedOutCommunity();

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(Space.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Container(
              padding: const EdgeInsets.all(Space.lg),
              decoration: BoxDecoration(
                color: palette.surfaceAlt,
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.groups_2_outlined,
                size: 36,
                color: palette.primary,
              ),
            ),
            const SizedBox(height: Space.lg),
            Text(
              Tr.of(
                context,
                ar: 'مجتمع Wings في انتظارك',
                en: 'The Wings community is waiting',
              ),
              textAlign: TextAlign.center,
              style: context.text.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: Space.xs),
            Text(
              Tr.of(
                context,
                ar: 'سجّل الدخول لتشاهد المنشورات والريلز، وتتفاعل مع الأعضاء، وتنشر أول مقطع لك.',
                en: 'Sign in to browse posts and Reels, interact with members, and publish your first clip.',
              ),
              textAlign: TextAlign.center,
              style: context.text.bodySmall?.copyWith(
                color: palette.textSecondary,
                height: 1.7,
              ),
            ),
            const SizedBox(height: Space.lg),
            FilledButton.icon(
              onPressed: () => showSignInPrompt(
                context,
                message: Tr.of(
                  context,
                  ar: 'سجّل الدخول لفتح المجتمع والريلز.',
                  en: 'Sign in to open the community and Reels.',
                ),
              ),
              icon: const Icon(Icons.login_rounded, size: 18),
              label: Text(Tr.of(context, ar: 'تسجيل الدخول', en: 'Sign in')),
            ),
            const SizedBox(height: Space.sm),
            TextButton.icon(
              onPressed: () => context.push(RoutePaths.communityReels),
              icon: const Icon(Icons.movie_filter_outlined, size: 18),
              label: Text(
                Tr.of(context, ar: 'استكشاف الريلز', en: 'Explore Reels'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Feed extends ConsumerStatefulWidget {
  const _Feed({required this.tab});

  final CommunityTab tab;

  @override
  ConsumerState<_Feed> createState() => _FeedState();
}

class _FeedState extends ConsumerState<_Feed> {
  @override
  Widget build(BuildContext context) {
    final state = ref.watch(communityFeedProvider(widget.tab));
    final controller = ref.read(communityFeedProvider(widget.tab).notifier);

    if (state.loading && state.posts.isEmpty) {
      return const WingsLoading();
    }
    if (state.posts.isEmpty) {
      if (state.error != null) {
        return WingsEmptyState(
          icon: Icons.cloud_off_rounded,
          title: AppLocalizations.of(context).commonErrorTitle,
          message: loadFailedText(context),
          actionLabel: AppLocalizations.of(context).commonRetry,
          onAction: () => controller.load(refresh: true),
        );
      }
      return RefreshIndicator(
        onRefresh: () => controller.load(refresh: true),
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: <Widget>[
            const SizedBox(height: Space.xxxl),
            WingsEmptyState(
              icon: widget.tab == CommunityTab.following
                  ? Icons.people_outline_rounded
                  : Icons.forum_outlined,
              title: widget.tab == CommunityTab.following
                  ? Tr.of(
                      context,
                      ar: 'لا توجد منشورات ممن تتابعهم',
                      en: 'No posts from people you follow',
                    )
                  : Tr.of(
                      context,
                      ar: 'لا توجد منشورات بعد',
                      en: 'No posts yet',
                    ),
              message: widget.tab == CommunityTab.following
                  ? Tr.of(
                      context,
                      ar: 'تابع أعضاء من المجتمع لتظهر منشوراتهم هنا.',
                      en: 'Follow members and their posts will show up here.',
                    )
                  : Tr.of(
                      context,
                      ar: 'كن أول من ينشر في Wings.',
                      en: 'Be the first to post on Wings.',
                    ),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: () => controller.load(refresh: true),
      child: ListView.builder(
        padding: const EdgeInsets.only(top: Space.xs, bottom: 96),
        itemCount: state.posts.length + (state.hasMore ? 1 : 0),
        itemBuilder: (context, index) {
          if (index >= state.posts.length) {
            // Reaching the tail is the pagination trigger; no scroll listener
            // and no second query for data already on screen.
            WidgetsBinding.instance.addPostFrameCallback((_) {
              controller.loadMore();
            });
            return const Padding(
              padding: EdgeInsets.symmetric(vertical: Space.lg),
              child: Center(
                child: SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2.2),
                ),
              ),
            );
          }
          final post = state.posts[index];
          return PostCard(
            post: post,
            showFollow: true,
            onChanged: controller.replace,
            onDeleted: () => controller.remove(post.id),
          );
        },
      ),
    );
  }
}

class _TabChip extends StatelessWidget {
  const _TabChip({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Material(
      color: selected ? palette.surfaceHigh : palette.surface,
      borderRadius: BorderRadius.circular(Radii.pill),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(Radii.pill),
        child: Container(
          height: 38,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(Radii.pill),
            border: Border.all(
              color: selected ? palette.primary : palette.border,
              width: selected ? 1.4 : 1,
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              Icon(
                icon,
                size: 15,
                color: selected ? palette.primary : palette.textMuted,
              ),
              const SizedBox(width: 6),
              Text(
                label,
                style: context.text.labelSmall?.copyWith(
                  color: selected ? palette.primary : palette.textSecondary,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
