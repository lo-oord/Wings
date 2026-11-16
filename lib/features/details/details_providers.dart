import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../data/models/anime.dart';

class DetailsBundle {
  const DetailsBundle({
    required this.anime,
    required this.episodes,
    required this.related,
    this.episodesError,
  });

  final Anime anime;
  final List<AnimeEpisode> episodes;
  final List<Anime> related;
  final Object? episodesError;
}

final detailsBundleProvider = FutureProvider.family<DetailsBundle, String>((
  ref,
  animeId,
) async {
  final repository = ref.watch(animeRepositoryProvider);
  final anime = await repository.details(animeId);

  var episodes = const <AnimeEpisode>[];
  Object? episodesError;
  try {
    episodes = await repository.episodes(anime);
  } on Object catch (error) {
    episodesError = error;
  }

  final related = await repository.related(anime);
  return DetailsBundle(
    anime: anime,
    episodes: episodes,
    related: related,
    episodesError: episodesError,
  );
});

/// Servers for one episode, loaded on demand by the player and download sheet.
final episodeServersProvider =
    FutureProvider.family<
      List<StreamServer>,
      ({String animeId, String episodeId})
    >((ref, key) async {
      final repository = ref.watch(animeRepositoryProvider);
      final bundle = await ref.watch(detailsBundleProvider(key.animeId).future);
      final episode =
          bundle.episodes.cast<AnimeEpisode?>().firstWhere(
            (item) => item?.id == key.episodeId,
            orElse: () => null,
          ) ??
          AnimeEpisode(id: key.episodeId, number: 0, animeId: key.animeId);
      return repository.servers(bundle.anime, episode);
    });
