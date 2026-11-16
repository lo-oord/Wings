import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../data/models/anime.dart';

final genresProvider = FutureProvider<List<Genre>>((ref) {
  return ref.watch(animeRepositoryProvider).genres();
});

final randomAnimeProvider = Provider<Future<Anime?> Function()>((ref) {
  final repository = ref.watch(animeRepositoryProvider);
  return repository.randomAnime;
});
