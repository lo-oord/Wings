import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/localization/app_localizations.dart';
import '../../app/providers.dart';
import '../../app/router/route_paths.dart';
import '../../app/theme/app_tokens.dart';
import '../../app/theme/context_ext.dart';
import '../../core/utils/tr.dart';
import '../../core/widgets/wings_buttons.dart';
import '../../core/widgets/wings_cards.dart';
import '../../core/widgets/wings_feedback.dart';
import '../../core/widgets/wings_layout.dart';
import '../../data/models/anime.dart';
import 'explore_providers.dart';

/// Everything that belongs to one category.
class GenreScreen extends ConsumerStatefulWidget {
  const GenreScreen({super.key, required this.genre});

  final String genre;

  @override
  ConsumerState<GenreScreen> createState() => _GenreScreenState();
}

class _GenreScreenState extends ConsumerState<GenreScreen> {
  BrowseSort _sort = BrowseSort.popular;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final palette = context.palette;
    final feed = ref.watch(
      genreFeedProvider((genre: widget.genre, sort: _sort)),
    );
    final favoriteGenre = ref
        .watch(libraryProvider)
        .favorites
        .any((entry) => entry.anime.genres.contains(widget.genre));

    return Scaffold(
      appBar: WingsAppBar(
        showBack: true,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text(
              widget.genre,
              style: context.text.titleLarge?.copyWith(fontSize: 18),
            ),
            Text(
              l10n.exploreGenres,
              style: context.text.labelSmall?.copyWith(
                color: palette.textMuted,
              ),
            ),
          ],
        ),
        actions: <Widget>[
          if (favoriteGenre)
            Padding(
              padding: const EdgeInsetsDirectional.only(end: Space.md),
              child: WingsBadge(
                l10n.libraryFavorites,
                style: WingsBadgeStyle.success,
              ),
            ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: Column(
          children: <Widget>[
            SizedBox(
              height: 38,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: Space.lg),
                children: <Widget>[
                  for (final option in const <BrowseSort>[
                    BrowseSort.popular,
                    BrowseSort.newest,
                    BrowseSort.rating,
                    BrowseSort.titleAsc,
                    BrowseSort.oldest,
                  ])
                    Padding(
                      padding: const EdgeInsetsDirectional.only(end: Space.sm),
                      child: WingsFilterChip(
                        label: _label(context, option),
                        selected: _sort == option,
                        onTap: () => setState(() => _sort = option),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: Space.sm),
            Expanded(
              child: feed.when(
                loading: () => const _GenreSkeleton(),
                error: (error, _) => WingsErrorState(
                  failure: error,
                  onRetry: () => ref.invalidate(
                    genreFeedProvider((genre: widget.genre, sort: _sort)),
                  ),
                ),
                data: (value) {
                  if (value.items.isEmpty) {
                    return WingsEmptyState(
                      icon: Icons.movie_filter_outlined,
                      title: Tr.of(
                        context,
                        ar: 'لا توجد أعمال في هذا التصنيف الآن',
                        en: 'Nothing in this category yet',
                      ),
                      message: Tr.of(
                        context,
                        ar: 'جرّب تصنيفًا آخر أو تصفّح كل الأعمال.',
                        en: 'Try another category or browse everything.',
                      ),
                      actionLabel: l10n.exploreBrowse,
                      onAction: () => context.push(RoutePaths.explore),
                    );
                  }
                  final count = value.items.length;
                  return RefreshIndicator(
                    color: palette.primary,
                    backgroundColor: palette.surface,
                    onRefresh: () async => ref.invalidate(
                      genreFeedProvider((genre: widget.genre, sort: _sort)),
                    ),
                    child: CustomScrollView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      slivers: <Widget>[
                        SliverToBoxAdapter(
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(
                              Space.lg,
                              Space.xs,
                              Space.lg,
                              Space.sm,
                            ),
                            child: Text(
                              '$count ${Tr.of(context, ar: 'عملًا في «${widget.genre}»', en: 'titles in “${widget.genre}”')}',
                              style: context.text.labelSmall?.copyWith(
                                color: palette.textMuted,
                              ),
                            ),
                          ),
                        ),
                        SliverPadding(
                          padding: const EdgeInsets.fromLTRB(
                            Space.lg,
                            0,
                            Space.lg,
                            Space.xxl,
                          ),
                          sliver: SliverGrid(
                            gridDelegate: AnimeGrid.delegate(context),
                            delegate: SliverChildBuilderDelegate((
                              context,
                              index,
                            ) {
                              final anime = value.items[index];
                              return WingsPosterCard(
                                anime: anime,
                                width: double.infinity,
                                onTap: () =>
                                    context.push(RoutePaths.anime(anime.id)),
                              );
                            }, childCount: value.items.length),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _label(BuildContext context, BrowseSort sort) {
    final l10n = AppLocalizations.of(context);
    return switch (sort) {
      BrowseSort.newest => l10n.exploreSortNewest,
      BrowseSort.oldest => l10n.exploreSortOldest,
      BrowseSort.titleAsc => l10n.exploreSortAz,
      BrowseSort.popular => l10n.exploreSortPopular,
      BrowseSort.rating => l10n.exploreSortRating,
    };
  }
}

class _GenreSkeleton extends StatelessWidget {
  const _GenreSkeleton();

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(Space.lg, 0, Space.lg, Space.lg),
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: AnimeGrid.delegate(context),
      itemCount: 9,
      itemBuilder: (_, _) => const WingsPosterSkeleton(),
    );
  }
}
