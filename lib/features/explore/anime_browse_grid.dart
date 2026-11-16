import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/localization/app_localizations.dart';
import '../../app/providers.dart';
import '../../app/router/route_paths.dart';
import '../../app/theme/app_tokens.dart';
import '../../app/theme/context_ext.dart';
import '../../core/errors/app_failure.dart';
import '../../core/widgets/wings_cards.dart';
import '../../core/widgets/wings_feedback.dart';
import '../../data/models/anime.dart';

enum BrowseLayout { grid, list }

/// Paginated catalogue browser shared by Explore and genre screens.
class AnimeBrowseGrid extends ConsumerStatefulWidget {
  const AnimeBrowseGrid({
    super.key,
    required this.genre,
    required this.sort,
    this.layout = BrowseLayout.grid,
    this.headerSlivers = const <Widget>[],
  });

  final String? genre;
  final BrowseSort sort;
  final BrowseLayout layout;
  final List<Widget> headerSlivers;

  @override
  ConsumerState<AnimeBrowseGrid> createState() => _AnimeBrowseGridState();
}

class _AnimeBrowseGridState extends ConsumerState<AnimeBrowseGrid> {
  final ScrollController _controller = ScrollController();
  final List<Anime> _items = <Anime>[];

  CancelToken? _cancelToken;
  Object? _error;
  bool _loading = true;
  bool _loadingMore = false;
  bool _hasMore = false;
  int _page = 0;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onScroll);
    _reload();
  }

  @override
  void didUpdateWidget(covariant AnimeBrowseGrid oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.genre != widget.genre || oldWidget.sort != widget.sort) {
      _reload();
    }
  }

  @override
  void dispose() {
    _controller
      ..removeListener(_onScroll)
      ..dispose();
    _cancelToken?.cancel();
    super.dispose();
  }

  void _onScroll() {
    if (!_controller.hasClients || _loadingMore || !_hasMore) return;
    final position = _controller.position;
    if (position.pixels >= position.maxScrollExtent - 600) {
      _loadMore();
    }
  }

  Future<void> _reload() async {
    _cancelToken?.cancel();
    final token = CancelToken();
    _cancelToken = token;
    setState(() {
      _loading = true;
      _error = null;
      _items.clear();
      _page = 0;
      _hasMore = false;
    });
    try {
      final result = await ref
          .read(animeRepositoryProvider)
          .browse(
            BrowseQuery(genre: widget.genre, sort: widget.sort),
            cancelToken: token,
          );
      if (!mounted || token.isCancelled) return;
      setState(() {
        _items
          ..clear()
          ..addAll(result.items);
        _page = result.page;
        _hasMore = result.hasMore;
        _loading = false;
      });
    } on Object catch (error) {
      if (!mounted || token.isCancelled) return;
      setState(() {
        _error = error is AppFailure ? error : AppFailure.from(error);
        _loading = false;
      });
    }
  }

  Future<void> _loadMore() async {
    if (_loadingMore || !_hasMore) return;
    setState(() => _loadingMore = true);
    try {
      final result = await ref
          .read(animeRepositoryProvider)
          .browse(
            BrowseQuery(genre: widget.genre, sort: widget.sort),
            page: _page + 1,
          );
      if (!mounted) return;
      setState(() {
        _items.addAll(result.items);
        _page = result.page;
        _hasMore = result.hasMore;
        _loadingMore = false;
      });
    } on Object {
      if (!mounted) return;
      setState(() => _loadingMore = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    final header = widget.headerSlivers;
    if (_loading) {
      return CustomScrollView(
        controller: _controller,
        slivers: <Widget>[
          ...header,
          const SliverToBoxAdapter(child: _GridSkeleton()),
        ],
      );
    }

    if (_error != null && _items.isEmpty) {
      return CustomScrollView(
        controller: _controller,
        slivers: <Widget>[
          ...header,
          SliverFillRemaining(
            hasScrollBody: false,
            child: WingsErrorState(failure: _error!, onRetry: _reload),
          ),
        ],
      );
    }

    if (_items.isEmpty) {
      return CustomScrollView(
        controller: _controller,
        slivers: <Widget>[
          ...header,
          SliverFillRemaining(
            hasScrollBody: false,
            child: WingsEmptyState(
              title: l10n.exploreNoResults,
              icon: Icons.search_off_rounded,
            ),
          ),
        ],
      );
    }

    return RefreshIndicator(
      onRefresh: _reload,
      color: context.palette.primary,
      backgroundColor: context.palette.surface,
      child: CustomScrollView(
        controller: _controller,
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: <Widget>[
          ...header,
          if (widget.layout == BrowseLayout.grid)
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(
                Space.lg,
                0,
                Space.lg,
                Space.lg,
              ),
              sliver: SliverGrid(
                gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: 160,
                  mainAxisSpacing: Space.lg,
                  crossAxisSpacing: Space.md,
                  childAspectRatio: 0.53,
                ),
                delegate: SliverChildBuilderDelegate((context, index) {
                  final anime = _items[index];
                  return WingsPosterCard(
                    anime: anime,
                    width: double.infinity,
                    onTap: () => context.push(RoutePaths.anime(anime.id)),
                  );
                }, childCount: _items.length),
              ),
            )
          else
            SliverList.builder(
              itemCount: _items.length,
              itemBuilder: (context, index) {
                final anime = _items[index];
                return WingsAnimeListTile(
                  anime: anime,
                  onTap: () => context.push(RoutePaths.anime(anime.id)),
                );
              },
            ),
          if (_loadingMore)
            const SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.all(Space.lg),
                child: WingsLoading(),
              ),
            ),
          const SliverToBoxAdapter(child: SizedBox(height: Space.xl)),
        ],
      ),
    );
  }
}

class _GridSkeleton extends StatelessWidget {
  const _GridSkeleton();

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(Space.lg, 0, Space.lg, Space.lg),
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 160,
        mainAxisSpacing: Space.lg,
        crossAxisSpacing: Space.md,
        childAspectRatio: 0.53,
      ),
      itemCount: 9,
      itemBuilder: (_, _) => const WingsPosterSkeleton(),
    );
  }
}
