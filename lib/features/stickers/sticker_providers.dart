import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../data/models/sticker_catalog.dart';
import 'sticker_preferences.dart';

/// The bundled catalogue, loaded once for the whole app.
final stickerCatalogProvider = FutureProvider<StickerCatalog>(
  (ref) => StickerCatalog.load(),
);

final stickerPreferencesProvider = Provider<StickerPreferences>(
  (ref) => StickerPreferences(
    LocalStickerPreferencesStore(ref.watch(localStoreProvider)),
  ),
);

@immutable
class StickerLibraryState {
  const StickerLibraryState({
    this.favorites = const <String>[],
    this.recents = const <String>[],
  });

  final List<String> favorites;
  final List<String> recents;
}

/// Device-local favourites and recents shared by the picker and the composer.
class StickerLibrary extends Notifier<StickerLibraryState> {
  StickerPreferences get _preferences => ref.read(stickerPreferencesProvider);

  @override
  StickerLibraryState build() {
    final preferences = ref.watch(stickerPreferencesProvider);
    return StickerLibraryState(
      favorites: preferences.favorites,
      recents: preferences.recents,
    );
  }

  Future<void> toggleFavorite(String id) async {
    final favorites = await _preferences.toggleFavorite(id);
    state = StickerLibraryState(favorites: favorites, recents: state.recents);
  }

  Future<void> markUsed(String id) async {
    final recents = await _preferences.markUsed(id);
    state = StickerLibraryState(favorites: state.favorites, recents: recents);
  }
}

final stickerLibraryProvider =
    NotifierProvider<StickerLibrary, StickerLibraryState>(StickerLibrary.new);
