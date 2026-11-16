import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/localization/app_localizations.dart';
import '../../app/providers.dart';
import '../../app/router/route_paths.dart';
import '../../app/theme/app_tokens.dart';
import '../../app/theme/context_ext.dart';
import '../../core/widgets/wings_buttons.dart';
import '../../core/widgets/wings_cards.dart';
import '../../core/widgets/wings_feedback.dart';
import '../../core/widgets/wings_image.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/wings_layout.dart';
import '../../data/models/anime.dart';
import '../../data/models/library.dart';
import 'home_providers.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final feed = ref.watch(homeFeedProvider);
    final online = ref.watch(onlineProvider).value ?? true;
    final continueWatching = ref.watch(continueWatchingProvider);

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: RefreshIndicator(
          color: context.palette.primary,
          backgroundColor: context.palette.surface,
          onRefresh: () => ref.read(homeFeedProvider.notifier).refresh(),
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: <Widget>[
              SliverToBoxAdapter(child: _HomeHeader(online: online)),
              if (!online) const SliverToBoxAdapter(child: WingsOfflineStrip()),
              ...feed.when(
                data: (value) =>
                    _buildContent(context, ref, value, continueWatching),
                loading: () => <Widget>[
                  const SliverToBoxAdapter(child: _HomeSkeleton()),
                ],
                error: (error, _) => <Widget>[
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: WingsErrorState(
                      failure: error,
                      onRetry: () => ref.invalidate(homeFeedProvider),
                    ),
                  ),
                ],
              ),
              const SliverToBoxAdapter(child: SizedBox(height: Space.xxxl)),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _buildContent(
    BuildContext context,
    WidgetRef ref,
    HomeFeed feed,
    List<WatchHistoryEntry> continueWatching,
  ) {
    final l10n = AppLocalizations.of(context);
    return <Widget>[
      if (feed.featured != null)
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.only(top: Space.sm),
            child: WingsFeaturedBanner(
              anime: feed.featured!,
              onWatch: () {
                final episode = feed.featuredEpisode;
                if (episode == null) {
                  context.push(RoutePaths.anime(feed.featured!.id));
                  return;
                }
                context.push(
                  RoutePaths.watch(
                    animeId: feed.featured!.id,
                    episodeId: episode.id,
                  ),
                  extra: feed.featured,
                );
              },
              onDetails: () =>
                  context.push(RoutePaths.anime(feed.featured!.id)),
            ),
          ),
        ),
      if (continueWatching.isNotEmpty) ...<Widget>[
        SliverToBoxAdapter(
          child: WingsSectionHeader(title: l10n.homeContinueWatching),
        ),
        SliverToBoxAdapter(
          child: SizedBox(
            height: 170,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: Space.lg),
              itemCount: continueWatching.length,
              separatorBuilder: (_, _) => const SizedBox(width: Space.md),
              itemBuilder: (context, index) {
                final entry = continueWatching[index];
                return WingsContinueCard(
                  entry: entry,
                  onTap: () => context.push(
                    RoutePaths.watch(
                      animeId: entry.animeId,
                      episodeId: entry.episodeId,
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ],
      if (feed.recentlyAdded.isNotEmpty) ...<Widget>[
        SliverToBoxAdapter(
          child: WingsSectionHeader(
            title: l10n.homeRecentlyAdded,
            actionLabel: l10n.commonSeeAll,
            onAction: () => context.go(RoutePaths.explore),
          ),
        ),
        SliverToBoxAdapter(child: _PosterRail(items: feed.recentlyAdded)),
      ],
      if (feed.latest.isNotEmpty) ...<Widget>[
        SliverToBoxAdapter(
          child: WingsSectionHeader(title: l10n.homeLatestEpisodes),
        ),
        SliverList.builder(
          itemCount: feed.latest.length,
          itemBuilder: (context, index) {
            final item = feed.latest[index];
            return _LatestEpisodeRow(
              item: item,
              onOpen: () => context.push(RoutePaths.anime(item.anime.id)),
              onPlay: () => context.push(
                RoutePaths.watch(
                  animeId: item.anime.id,
                  episodeId: item.episode.id,
                ),
                extra: item.anime,
              ),
            );
          },
        ),
        if (feed.latestHasMore)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: Space.lg,
                vertical: Space.sm,
              ),
              child: TextButton(
                onPressed: () =>
                    ref.read(homeFeedProvider.notifier).loadMoreLatest(),
                child: Text(l10n.commonMore),
              ),
            ),
          ),
      ] else
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: Space.xl),
            child: WingsEmptyState(
              icon: Icons.new_releases_outlined,
              title: l10n.homeLatestEmpty,
            ),
          ),
        ),
      if (feed.popular.isNotEmpty) ...<Widget>[
        SliverToBoxAdapter(child: WingsSectionHeader(title: l10n.homePopular)),
        SliverToBoxAdapter(
          child: _PosterRail(items: feed.popular, ranked: true),
        ),
      ],
      if (feed.recommended.isNotEmpty) ...<Widget>[
        SliverToBoxAdapter(
          child: WingsSectionHeader(title: l10n.homeRecommended),
        ),
        SliverToBoxAdapter(child: _PosterRail(items: feed.recommended)),
      ],
    ];
  }
}

class _HomeHeader extends StatelessWidget {
  const _HomeHeader({required this.online});

  final bool online;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        Space.lg,
        Space.md,
        Space.lg,
        Space.sm,
      ),
      child: Row(
        children: <Widget>[
          const WingsLockup(size: 30, showTagline: true),
          const Spacer(),
          WingsIconButton(
            icon: Icons.search_rounded,
            tooltip: AppLocalizations.of(context).searchTitle,
            onPressed: () => context.push(RoutePaths.search),
          ),
          const SizedBox(width: Space.xs),
          WingsIconButton(
            icon: Icons.notifications_none_rounded,
            tooltip: AppLocalizations.of(context).notificationsTitle,
            onPressed: () => context.push(RoutePaths.notifications),
          ),
        ],
      ),
    );
  }
}

class _PosterRail extends StatelessWidget {
  const _PosterRail({required this.items, this.ranked = false});

  final List<Anime> items;
  final bool ranked;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 214,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: Space.lg),
        itemCount: items.length,
        separatorBuilder: (_, _) => const SizedBox(width: Space.md),
        itemBuilder: (context, index) {
          final anime = items[index];
          return WingsPosterCard(
            anime: anime,
            rank: ranked ? index + 1 : null,
            onTap: () => context.push(RoutePaths.anime(anime.id)),
          );
        },
      ),
    );
  }
}

class _LatestEpisodeRow extends StatelessWidget {
  const _LatestEpisodeRow({
    required this.item,
    required this.onOpen,
    required this.onPlay,
  });

  final LatestEpisode item;
  final VoidCallback onOpen;
  final VoidCallback onPlay;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final l10n = AppLocalizations.of(context);
    return InkWell(
      onTap: onOpen,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: Space.lg,
          vertical: Space.sm - 2,
        ),
        child: Row(
          children: <Widget>[
            Stack(
              children: <Widget>[
                WingsImage(
                  url: item.episode.thumbnailUrl ?? item.anime.imageUrl,
                  width: 116,
                  height: 66,
                  borderRadius: BorderRadius.circular(Radii.xs),
                ),
                PositionedDirectional(
                  start: Space.xs,
                  bottom: Space.xs,
                  child: WingsBadge(
                    '${item.episode.number}',
                    style: WingsBadgeStyle.overlay,
                    compact: true,
                  ),
                ),
              ],
            ),
            const SizedBox(width: Space.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    item.anime.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: context.text.titleSmall,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    l10n.commonEpisodeNumber(item.episode.number),
                    style: context.text.bodySmall?.copyWith(
                      color: palette.textSecondary,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: Space.xs),
                  Row(
                    children: <Widget>[
                      if (item.releasedAt != null)
                        Text(
                          relativeTime(item.releasedAt, l10n),
                          style: context.text.labelSmall?.copyWith(
                            color: palette.textMuted,
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
            WingsIconButton(
              icon: Icons.play_circle_fill_rounded,
              color: palette.primary,
              onPressed: onPlay,
            ),
          ],
        ),
      ),
    );
  }
}

class _HomeSkeleton extends StatelessWidget {
  const _HomeSkeleton();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: Space.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const SizedBox(height: Space.sm),
          AspectRatio(
            aspectRatio: 4 / 5,
            child: WingsSkeleton(borderRadius: BorderRadius.circular(Radii.md)),
          ),
          const SizedBox(height: Space.xl),
          const WingsSkeleton(height: 16, width: 140),
          const SizedBox(height: Space.md),
          SizedBox(
            height: 180,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: 3,
              separatorBuilder: (_, _) => const SizedBox(width: Space.md),
              itemBuilder: (_, _) => const WingsPosterSkeleton(width: 132),
            ),
          ),
        ],
      ),
    );
  }
}
