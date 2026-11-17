import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/utils/title_series.dart';
import '../../data/models/anime.dart';

final genresProvider = FutureProvider<List<Genre>>((ref) {
  return ref.watch(animeRepositoryProvider).genres();
});

/// The result of opening one category.
class GenreFeed {
  const GenreFeed({required this.items, this.fellBack = false});

  final List<Anime> items;

  /// True when the source had no category page and the titles came from a
  /// name search instead, so the screen can say so honestly.
  final bool fellBack;
}

/// One category page.
///
/// A source that does not index the category directly would answer with an
/// empty page, which looked like a blank screen. The fallback searches the
/// category name and keeps the titles whose genres really match, so the page
/// always shows something relevant or an explicit empty state.
final genreFeedProvider =
    FutureProvider.family<GenreFeed, ({String genre, BrowseSort sort})>((
      ref,
      key,
    ) async {
      final repository = ref.watch(animeRepositoryProvider);
      final page = await repository.browse(
        BrowseQuery(genre: key.genre, sort: key.sort),
      );
      if (page.items.isNotEmpty) return GenreFeed(items: page.items);

      final needle = normalizeArabicText(key.genre);
      try {
        final search = await repository.search(key.genre);
        final matches = search.items
            .where(
              (anime) => anime.genres.any(
                (genre) => normalizeArabicText(genre) == needle,
              ),
            )
            .toList(growable: false);
        return GenreFeed(
          items: matches.isNotEmpty ? matches : search.items,
          fellBack: true,
        );
      } on Object {
        return const GenreFeed(items: <Anime>[], fellBack: true);
      }
    });

final randomAnimeProvider = Provider<Future<Anime?> Function()>((ref) {
  final repository = ref.watch(animeRepositoryProvider);
  return repository.randomAnime;
});
