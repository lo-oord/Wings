import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/localization/app_localizations.dart';
import '../../app/providers.dart';
import '../../app/theme/app_tokens.dart';
import '../../app/theme/context_ext.dart';
import '../../core/widgets/wings_buttons.dart';
import '../../core/widgets/wings_layout.dart';
import '../../data/models/anime.dart';
import 'anime_browse_grid.dart';

class GenreScreen extends ConsumerStatefulWidget {
  const GenreScreen({super.key, required this.genre});

  final String genre;

  @override
  ConsumerState<GenreScreen> createState() => _GenreScreenState();
}

class _GenreScreenState extends ConsumerState<GenreScreen> {
  BrowseSort _sort = BrowseSort.newest;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final palette = context.palette;
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
      body: Column(
        children: <Widget>[
          SizedBox(
            height: 34,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: Space.lg),
              children: <Widget>[
                for (final option in const <BrowseSort>[
                  BrowseSort.newest,
                  BrowseSort.rating,
                  BrowseSort.popular,
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
            child: AnimeBrowseGrid(genre: widget.genre, sort: _sort),
          ),
        ],
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
