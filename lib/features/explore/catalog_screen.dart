import 'package:flutter/material.dart';

import '../../app/localization/app_localizations.dart';
import '../../app/theme/app_tokens.dart';
import '../../app/theme/context_ext.dart';
import '../../core/widgets/wings_layout.dart';
import '../../data/models/anime.dart';
import 'anime_browse_grid.dart';

/// Full list behind a home-section "see all" action.
class CatalogScreen extends StatelessWidget {
  const CatalogScreen({super.key, required this.kind});

  /// One of `newest`, `popular`, `rating`.
  final String kind;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final (title, sort) = switch (kind) {
      'popular' => (l10n.homePopular, BrowseSort.popular),
      'rating' => (l10n.homeRecommended, BrowseSort.rating),
      _ => (l10n.homeRecentlyAdded, BrowseSort.newest),
    };

    return Scaffold(
      appBar: WingsAppBar(
        showBack: true,
        title: Text(
          title,
          style: context.text.titleLarge?.copyWith(fontSize: 19),
        ),
      ),
      body: SafeArea(
        top: false,
        child: AnimeBrowseGrid(
          genre: null,
          sort: sort,
          headerSlivers: const <Widget>[
            SliverToBoxAdapter(child: SizedBox(height: Space.sm)),
          ],
        ),
      ),
    );
  }
}
