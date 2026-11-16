import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/localization/app_localizations.dart';
import '../../app/providers.dart';
import '../../app/router/route_paths.dart';
import '../../app/theme/app_tokens.dart';
import '../../app/theme/context_ext.dart';
import '../../core/widgets/wings_cards.dart';
import '../../core/widgets/wings_feedback.dart';
import '../../core/widgets/wings_layout.dart';
import '../../data/models/anime.dart';
import '../explore/explore_providers.dart';
import 'search_providers.dart';

class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key});

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  final TextEditingController _textController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(() {
      final position = _scrollController.position;
      if (position.pixels >= position.maxScrollExtent - 400) {
        ref.read(searchProvider.notifier).loadMore();
      }
    });
  }

  @override
  void dispose() {
    _textController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _openAnime(String animeId, String query) {
    if (query.trim().isNotEmpty) {
      ref.read(libraryProvider.notifier).addSearch(query);
    }
    context.push(RoutePaths.anime(animeId));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final palette = context.palette;
    final state = ref.watch(searchProvider);
    final searches = ref.watch(libraryProvider).searches;

    return Scaffold(
      appBar: WingsAppBar(
        showBack: true,
        title: Container(
          height: 44,
          margin: const EdgeInsetsDirectional.only(end: Space.lg),
          padding: const EdgeInsets.symmetric(horizontal: Space.md),
          decoration: BoxDecoration(
            color: palette.surfaceAlt,
            borderRadius: BorderRadius.circular(Radii.sm),
            border: Border.all(color: palette.border),
          ),
          child: Row(
            children: <Widget>[
              Icon(Icons.search_rounded, size: 18, color: palette.textMuted),
              const SizedBox(width: Space.sm),
              Expanded(
                child: TextField(
                  controller: _textController,
                  autofocus: true,
                  textInputAction: TextInputAction.search,
                  style: context.text.bodyLarge?.copyWith(fontSize: 14),
                  decoration: InputDecoration(
                    isDense: true,
                    filled: false,
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    hintText: l10n.searchHint,
                    hintStyle: context.text.bodyMedium?.copyWith(
                      color: palette.textMuted,
                    ),
                    contentPadding: EdgeInsets.zero,
                  ),
                  onChanged: ref.read(searchProvider.notifier).onQueryChanged,
                  onSubmitted: (value) async {
                    FocusScope.of(context).unfocus();
                    await ref.read(searchProvider.notifier).submit(value);
                  },
                ),
              ),
              if (state.query.isNotEmpty)
                GestureDetector(
                  onTap: () {
                    _textController.clear();
                    ref.read(searchProvider.notifier).clear();
                  },
                  child: Icon(
                    Icons.close_rounded,
                    size: 18,
                    color: palette.textMuted,
                  ),
                ),
            ],
          ),
        ),
      ),
      body: SafeArea(
        top: false,
        child: state.loading
            ? const _SearchSkeleton()
            : state.error != null
            ? WingsErrorState(
                failure: state.error!,
                onRetry: () => ref.read(searchProvider.notifier).retry(),
              )
            : state.items.isNotEmpty
            ? ListView.builder(
                controller: _scrollController,
                padding: const EdgeInsets.only(
                  top: Space.sm,
                  bottom: Space.xxl,
                ),
                itemCount: state.items.length + (state.loadingMore ? 1 : 0),
                itemBuilder: (context, index) {
                  if (index >= state.items.length) {
                    return const Padding(
                      padding: EdgeInsets.all(Space.lg),
                      child: WingsLoading(),
                    );
                  }
                  final anime = state.items[index];
                  return WingsAnimeListTile(
                    anime: anime,
                    onTap: () => _openAnime(anime.id, state.query),
                  );
                },
              )
            : state.hasSearched
            ? WingsEmptyState(
                icon: Icons.search_off_rounded,
                title: l10n.searchNoResults,
                message: l10n.searchNoResultsBody,
              )
            : _SearchIdle(
                searches: searches,
                onSelect: (query) {
                  _textController.text = query;
                  ref.read(searchProvider.notifier).submit(query);
                },
                onRemove: (query) =>
                    ref.read(libraryProvider.notifier).removeSearch(query),
                onClearAll: () =>
                    ref.read(libraryProvider.notifier).clearSearchHistory(),
                onGenre: (genre) => context.push(RoutePaths.genre(genre)),
                genres: ref.watch(genresProvider).value ?? const [],
                onOpenBrowse: () => context.go(RoutePaths.explore),
              ),
      ),
    );
  }
}

class _SearchIdle extends StatelessWidget {
  const _SearchIdle({
    required this.searches,
    required this.onSelect,
    required this.onRemove,
    required this.onClearAll,
    required this.genres,
    required this.onGenre,
    required this.onOpenBrowse,
  });

  final List<String> searches;
  final ValueChanged<String> onSelect;
  final ValueChanged<String> onRemove;
  final VoidCallback onClearAll;
  final List<Genre> genres;
  final ValueChanged<String> onGenre;
  final VoidCallback onOpenBrowse;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final palette = context.palette;

    return ListView(
      padding: const EdgeInsets.symmetric(
        horizontal: Space.lg,
        vertical: Space.md,
      ),
      children: <Widget>[
        if (searches.isNotEmpty) ...<Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(l10n.searchRecent, style: context.text.titleSmall),
              ),
              TextButton(
                onPressed: onClearAll,
                child: Text(l10n.searchClearAll),
              ),
            ],
          ),
          Wrap(
            spacing: Space.sm,
            runSpacing: Space.sm,
            children: <Widget>[
              for (final query in searches)
                InputChip(
                  label: Text(query),
                  onPressed: () => onSelect(query),
                  onDeleted: () => onRemove(query),
                  deleteIcon: const Icon(Icons.close_rounded, size: 14),
                  backgroundColor: palette.surfaceAlt,
                  side: BorderSide(color: palette.border),
                  labelStyle: context.text.bodySmall?.copyWith(
                    color: palette.textPrimary,
                  ),
                ),
            ],
          ),
          const SizedBox(height: Space.xl),
        ],
        Text(l10n.exploreGenres, style: context.text.titleSmall),
        const SizedBox(height: Space.sm),
        Wrap(
          spacing: Space.sm,
          runSpacing: Space.sm,
          children: <Widget>[
            for (final genre in genres.take(12))
              ActionChip(
                label: Text(genre.name),
                onPressed: () => onGenre(genre.name),
                backgroundColor: palette.surfaceAlt,
                side: BorderSide(color: palette.border),
                labelStyle: context.text.bodySmall?.copyWith(
                  color: palette.textSecondary,
                ),
              ),
          ],
        ),
        const SizedBox(height: Space.xxl),
        WingsEmptyState(
          icon: Icons.search_rounded,
          title: l10n.searchEmptyTitle,
          message: l10n.searchEmptyBody,
          actionLabel: l10n.exploreBrowse,
          onAction: onOpenBrowse,
        ),
      ],
    );
  }
}

class _SearchSkeleton extends StatelessWidget {
  const _SearchSkeleton();

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      padding: const EdgeInsets.all(Space.lg),
      itemCount: 6,
      separatorBuilder: (_, _) => const SizedBox(height: Space.lg),
      itemBuilder: (_, _) => Row(
        children: <Widget>[
          const WingsSkeleton(
            width: 62,
            height: 92,
            borderRadius: BorderRadius.all(Radius.circular(Radii.xs)),
          ),
          const SizedBox(width: Space.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: const <Widget>[
                WingsSkeleton(height: 12, width: 180),
                SizedBox(height: Space.sm),
                WingsSkeleton(height: 10, width: 120),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
