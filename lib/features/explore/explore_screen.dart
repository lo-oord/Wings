import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/localization/app_localizations.dart';
import '../../app/router/route_paths.dart';
import '../../app/theme/app_tokens.dart';
import '../../app/theme/context_ext.dart';
import '../../core/widgets/wings_buttons.dart';
import '../../core/widgets/wings_feedback.dart';
import '../../core/widgets/wings_layout.dart';
import '../../data/models/anime.dart';
import 'anime_browse_grid.dart';
import 'explore_providers.dart';

class ExploreScreen extends ConsumerStatefulWidget {
  const ExploreScreen({super.key});

  @override
  ConsumerState<ExploreScreen> createState() => _ExploreScreenState();
}

class _ExploreScreenState extends ConsumerState<ExploreScreen> {
  BrowseSort _sort = BrowseSort.newest;
  String? _genre;
  BrowseLayout _layout = BrowseLayout.grid;
  bool _loadingRandom = false;

  Future<void> _openRandom() async {
    if (_loadingRandom) return;
    setState(() => _loadingRandom = true);
    final anime = await ref.read(randomAnimeProvider)();
    if (!mounted) return;
    setState(() => _loadingRandom = false);
    if (anime == null) {
      context.showSnack(
        AppLocalizations.of(context).stateErrorGeneric,
        isError: true,
      );
      return;
    }
    context.push(RoutePaths.anime(anime.id));
  }

  Future<void> _openFilters() async {
    final result = await WingsSheet.show<({String? genre, BrowseSort sort})>(
      context,
      title: AppLocalizations.of(context).exploreFiltersTitle,
      builder: (sheetContext) =>
          _FilterBody(initialGenre: _genre, initialSort: _sort),
    );
    if (result == null) return;
    setState(() {
      _genre = result.genre;
      _sort = result.sort;
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final palette = context.palette;
    final genres = ref.watch(genresProvider);

    final header = <Widget>[
      SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            Space.lg,
            Space.md,
            Space.lg,
            Space.sm,
          ),
          child: Row(
            children: <Widget>[
              Text(l10n.exploreTitle, style: context.text.headlineSmall),
              const Spacer(),
              WingsIconButton(
                icon: Icons.casino_outlined,
                tooltip: l10n.exploreRandom,
                onPressed: _loadingRandom ? null : _openRandom,
              ),
            ],
          ),
        ),
      ),
      SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            Space.lg,
            Space.sm,
            Space.lg,
            Space.xs,
          ),
          child: GestureDetector(
            onTap: () => context.push(RoutePaths.search),
            child: Container(
              height: 46,
              padding: const EdgeInsets.symmetric(horizontal: Space.md),
              decoration: BoxDecoration(
                color: palette.surfaceAlt,
                borderRadius: BorderRadius.circular(Radii.sm),
                border: Border.all(color: palette.border),
              ),
              child: Row(
                children: <Widget>[
                  Icon(
                    Icons.search_rounded,
                    size: 19,
                    color: palette.textMuted,
                  ),
                  const SizedBox(width: Space.sm),
                  Expanded(
                    child: Text(
                      l10n.exploreSearchHint,
                      style: context.text.bodyMedium?.copyWith(
                        color: palette.textMuted,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
      SliverToBoxAdapter(
        child: WingsSectionHeader(
          title: l10n.exploreGenres,
          actionLabel: l10n.commonFilter,
          onAction: _openFilters,
          padding: const EdgeInsets.fromLTRB(
            Space.lg,
            Space.lg,
            Space.lg,
            Space.sm,
          ),
        ),
      ),
      SliverToBoxAdapter(
        child: SizedBox(
          height: 38,
          child: genres.when(
            data: (items) => ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: Space.lg),
              itemCount: items.length + 1,
              separatorBuilder: (_, _) => const SizedBox(width: Space.sm),
              itemBuilder: (context, index) {
                if (index == 0) {
                  return WingsFilterChip(
                    label: l10n.commonAll,
                    selected: _genre == null,
                    onTap: () => setState(() => _genre = null),
                  );
                }
                final genre = items[index - 1];
                return WingsFilterChip(
                  label: genre.name,
                  selected: _genre == genre.name,
                  onTap: () => setState(() => _genre = genre.name),
                );
              },
            ),
            loading: () => ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: Space.lg),
              itemCount: 5,
              separatorBuilder: (_, _) => const SizedBox(width: Space.sm),
              itemBuilder: (_, _) => const WingsSkeleton(width: 76, height: 34),
            ),
            error: (_, _) => Padding(
              padding: const EdgeInsets.symmetric(horizontal: Space.lg),
              child: Text(l10n.exploreNoResults, style: context.text.bodySmall),
            ),
          ),
        ),
      ),
      SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            Space.lg,
            Space.md,
            Space.lg,
            Space.sm,
          ),
          child: Row(
            children: <Widget>[
              Expanded(
                child: SizedBox(
                  height: 34,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    children: <Widget>[
                      for (final option in _sortOptions)
                        Padding(
                          padding: const EdgeInsetsDirectional.only(
                            end: Space.sm,
                          ),
                          child: WingsFilterChip(
                            label: _sortLabel(context, option),
                            selected: _sort == option,
                            onTap: () => setState(() => _sort = option),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: Space.sm),
              WingsIconButton(
                icon: _layout == BrowseLayout.grid
                    ? Icons.view_agenda_outlined
                    : Icons.grid_view_rounded,
                size: 34,
                tooltip: _layout == BrowseLayout.grid
                    ? l10n.commonList
                    : l10n.commonGrid,
                onPressed: () => setState(
                  () => _layout = _layout == BrowseLayout.grid
                      ? BrowseLayout.list
                      : BrowseLayout.grid,
                ),
              ),
            ],
          ),
        ),
      ),
      const SliverToBoxAdapter(child: SizedBox(height: Space.xs)),
    ];

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: AnimeBrowseGrid(
          genre: _genre,
          sort: _sort,
          layout: _layout,
          headerSlivers: header,
        ),
      ),
    );
  }
}

const List<BrowseSort> _sortOptions = <BrowseSort>[
  BrowseSort.newest,
  BrowseSort.rating,
  BrowseSort.popular,
  BrowseSort.titleAsc,
  BrowseSort.oldest,
];

String _sortLabel(BuildContext context, BrowseSort sort) {
  final l10n = AppLocalizations.of(context);
  return switch (sort) {
    BrowseSort.newest => l10n.exploreSortNewest,
    BrowseSort.oldest => l10n.exploreSortOldest,
    BrowseSort.titleAsc => l10n.exploreSortAz,
    BrowseSort.popular => l10n.exploreSortPopular,
    BrowseSort.rating => l10n.exploreSortRating,
  };
}

class _FilterBody extends ConsumerStatefulWidget {
  const _FilterBody({required this.initialGenre, required this.initialSort});

  final String? initialGenre;
  final BrowseSort initialSort;

  @override
  ConsumerState<_FilterBody> createState() => _FilterBodyState();
}

class _FilterBodyState extends ConsumerState<_FilterBody> {
  late String? _genre = widget.initialGenre;
  late BrowseSort _sort = widget.initialSort;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final genres = ref.watch(genresProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(l10n.exploreFilterGenre, style: context.text.titleSmall),
        const SizedBox(height: Space.sm),
        genres.when(
          data: (items) => Wrap(
            spacing: Space.sm,
            runSpacing: Space.sm,
            children: <Widget>[
              WingsFilterChip(
                label: l10n.commonAll,
                selected: _genre == null,
                onTap: () => setState(() => _genre = null),
              ),
              for (final genre in items)
                WingsFilterChip(
                  label: genre.count == null
                      ? genre.name
                      : '${genre.name} · ${genre.count}',
                  selected: _genre == genre.name,
                  onTap: () => setState(() => _genre = genre.name),
                ),
            ],
          ),
          loading: () => const WingsLoading(),
          error: (_, _) =>
              Text(l10n.stateErrorGeneric, style: context.text.bodySmall),
        ),
        const SizedBox(height: Space.xl),
        Text(l10n.exploreSort, style: context.text.titleSmall),
        const SizedBox(height: Space.sm),
        Wrap(
          spacing: Space.sm,
          runSpacing: Space.sm,
          children: <Widget>[
            for (final option in _sortOptions)
              WingsFilterChip(
                label: _sortLabel(context, option),
                selected: _sort == option,
                onTap: () => setState(() => _sort = option),
              ),
          ],
        ),
        const SizedBox(height: Space.xl),
        Row(
          children: <Widget>[
            Expanded(
              child: WingsButton(
                label: l10n.commonReset,
                variant: WingsButtonVariant.outline,
                onPressed: () => setState(() {
                  _genre = null;
                  _sort = BrowseSort.newest;
                }),
              ),
            ),
            const SizedBox(width: Space.md),
            Expanded(
              child: WingsButton(
                label: l10n.commonApply,
                onPressed: () =>
                    Navigator.of(context).pop((genre: _genre, sort: _sort)),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
