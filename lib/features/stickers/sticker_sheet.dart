import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme/app_tokens.dart';
import '../../app/theme/context_ext.dart';
import '../../core/utils/tr.dart';
import '../../core/widgets/wings_buttons.dart';
import '../../core/widgets/wings_layout.dart';
import '../../data/models/sticker_catalog.dart';
import 'sticker_providers.dart';
import 'sticker_view.dart';

/// Opens the sticker shelf from the bottom of the screen and returns the
/// chosen sticker, or null when the sheet is dismissed.
Future<Sticker?> showStickerPicker(BuildContext context) {
  return WingsPopup.show<Sticker>(
    context: context,
    heightFactor: 0.86,
    builder: (sheetContext) => const StickerPickerSheet(),
  );
}

/// Searchable, categorised, scrollable sticker picker.
class StickerPickerSheet extends ConsumerStatefulWidget {
  const StickerPickerSheet({super.key});

  @override
  ConsumerState<StickerPickerSheet> createState() => _StickerPickerSheetState();
}

class _StickerPickerSheetState extends ConsumerState<StickerPickerSheet> {
  static const String _favoritesShelf = '_favorites';
  static const String _recentShelf = '_recent';

  final TextEditingController _search = TextEditingController();
  String _shelf = StickerCatalog.allCategoryId;
  String _query = '';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final arabic = Tr.isArabic(context);
    final catalogAsync = ref.watch(stickerCatalogProvider);

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.72,
        child: Column(
          children: <Widget>[
            const SizedBox(height: Space.sm),
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: palette.borderStrong,
                borderRadius: BorderRadius.circular(Radii.pill),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                Space.lg,
                Space.sm,
                Space.lg,
                Space.sm,
              ),
              child: Row(
                children: <Widget>[
                  Icon(
                    Icons.emoji_emotions_outlined,
                    size: 18,
                    color: palette.primary,
                  ),
                  const SizedBox(width: Space.sm),
                  Text(
                    Tr.of(context, ar: 'الملصقات', en: 'Stickers'),
                    style: context.text.titleSmall,
                  ),
                  const Spacer(),
                  WingsIconButton(
                    icon: Icons.close_rounded,
                    size: 34,
                    tooltip: Tr.of(context, ar: 'إغلاق', en: 'Close'),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: Space.lg),
              child: TextField(
                controller: _search,
                textInputAction: TextInputAction.search,
                onChanged: (value) => setState(() => _query = value),
                decoration: InputDecoration(
                  isDense: true,
                  hintText: Tr.of(
                    context,
                    ar: 'ابحث في الملصقات…',
                    en: 'Search stickers…',
                  ),
                  prefixIcon: const Icon(Icons.search_rounded, size: 18),
                  suffixIcon: _query.isEmpty
                      ? null
                      : IconButton(
                          icon: const Icon(Icons.close_rounded, size: 16),
                          tooltip: Tr.of(context, ar: 'مسح', en: 'Clear'),
                          onPressed: () {
                            _search.clear();
                            setState(() => _query = '');
                          },
                        ),
                ),
              ),
            ),
            Expanded(
              child: catalogAsync.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (error, stack) => _LoadError(
                  onRetry: () => ref.invalidate(stickerCatalogProvider),
                ),
                data: (catalog) => _CatalogBody(
                  catalog: catalog,
                  arabic: arabic,
                  query: _query,
                  shelf: _shelf,
                  favoritesShelf: _favoritesShelf,
                  recentShelf: _recentShelf,
                  onShelf: (shelf) => setState(() => _shelf = shelf),
                  onPick: (sticker) => Navigator.of(context).pop(sticker),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CatalogBody extends ConsumerWidget {
  const _CatalogBody({
    required this.catalog,
    required this.arabic,
    required this.query,
    required this.shelf,
    required this.favoritesShelf,
    required this.recentShelf,
    required this.onShelf,
    required this.onPick,
  });

  final StickerCatalog catalog;
  final bool arabic;
  final String query;
  final String shelf;
  final String favoritesShelf;
  final String recentShelf;
  final ValueChanged<String> onShelf;
  final ValueChanged<Sticker> onPick;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final library = ref.watch(stickerLibraryProvider);
    final favorites = catalog.resolveAll(library.favorites);
    final recents = catalog.resolveAll(library.recents);
    final categories = catalog.availableCategories;

    final shelves = <_Shelf>[
      for (final category in categories)
        _Shelf(category.id, category.name(arabic)),
      if (recents.isNotEmpty)
        _Shelf(
          recentShelf,
          Tr.of(context, ar: 'المستخدمة مؤخرًا', en: 'Recent'),
        ),
      if (favorites.isNotEmpty)
        _Shelf(favoritesShelf, Tr.of(context, ar: 'المفضلة', en: 'Favourites')),
    ];
    final active = shelves.any((item) => item.id == shelf)
        ? shelf
        : StickerCatalog.allCategoryId;

    final visible = switch (active) {
      _ when active == favoritesShelf => _filter(favorites),
      _ when active == recentShelf => _filter(recents),
      _ => catalog.search(query, arabic: arabic, categoryId: active),
    };

    final favoriteIds = <String>{for (final sticker in favorites) sticker.id};

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        const SizedBox(height: Space.sm),
        SizedBox(
          height: 38,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: Space.lg),
            itemCount: shelves.length,
            separatorBuilder: (context, index) =>
                const SizedBox(width: Space.sm),
            itemBuilder: (context, index) {
              final item = shelves[index];
              return Center(
                child: WingsFilterChip(
                  label: item.label,
                  selected: item.id == active,
                  onTap: () => onShelf(item.id),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: Space.sm),
        Expanded(
          child: visible.isEmpty
              ? _EmptyState(
                  message: query.trim().isNotEmpty
                      ? Tr.of(
                          context,
                          ar: 'لا توجد ملصقات تطابق بحثك.',
                          en: 'No stickers match your search.',
                        )
                      : Tr.of(
                          context,
                          ar: 'لا توجد ملصقات في هذا التصنيف.',
                          en: 'No stickers in this shelf.',
                        ),
                )
              : GridView.builder(
                  padding: const EdgeInsets.fromLTRB(
                    Space.lg,
                    Space.xs,
                    Space.lg,
                    Space.lg,
                  ),
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.onDrag,
                  gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 84,
                    mainAxisSpacing: Space.sm,
                    crossAxisSpacing: Space.sm,
                  ),
                  itemCount: visible.length,
                  itemBuilder: (context, index) {
                    final sticker = visible[index];
                    return _StickerCell(
                      sticker: sticker,
                      favorite: favoriteIds.contains(sticker.id),
                      onTap: () => onPick(sticker),
                      onToggleFavorite: () => ref
                          .read(stickerLibraryProvider.notifier)
                          .toggleFavorite(sticker.id),
                    );
                  },
                ),
        ),
      ],
    );
  }

  List<Sticker> _filter(List<Sticker> source) {
    if (query.trim().isEmpty) return source;
    return source
        .where((sticker) => sticker.matches(query, arabic: arabic))
        .toList(growable: false);
  }
}

class _Shelf {
  const _Shelf(this.id, this.label);

  final String id;
  final String label;
}

class _StickerCell extends StatelessWidget {
  const _StickerCell({
    required this.sticker,
    required this.favorite,
    required this.onTap,
    required this.onToggleFavorite,
  });

  final Sticker sticker;
  final bool favorite;
  final VoidCallback onTap;
  final VoidCallback onToggleFavorite;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Material(
      key: ValueKey<String>('sticker_cell_${sticker.id}'),
      color: palette.surfaceAlt,
      borderRadius: BorderRadius.circular(Radii.sm),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        onLongPress: onToggleFavorite,
        child: Stack(
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.all(Space.xs + 2),
              child: Center(child: StickerAsset(sticker: sticker, size: 56)),
            ),
            Positioned(
              top: 0,
              right: 0,
              child: Semantics(
                button: true,
                label: Tr.of(
                  context,
                  ar: favorite ? 'إزالة من المفضلة' : 'إضافة إلى المفضلة',
                  en: favorite ? 'Remove from favourites' : 'Add to favourites',
                ),
                child: InkResponse(
                  radius: 16,
                  onTap: onToggleFavorite,
                  child: Padding(
                    padding: const EdgeInsets.all(3),
                    child: Icon(
                      favorite ? Icons.star_rounded : Icons.star_border_rounded,
                      size: 15,
                      color: favorite ? palette.warning : palette.textMuted,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(Space.xxl),
        child: Text(
          message,
          textAlign: TextAlign.center,
          style: context.text.bodySmall?.copyWith(
            color: context.palette.textMuted,
          ),
        ),
      ),
    );
  }
}

class _LoadError extends StatelessWidget {
  const _LoadError({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(Space.xxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(
              Icons.sentiment_dissatisfied_rounded,
              size: 28,
              color: context.palette.textMuted,
            ),
            const SizedBox(height: Space.sm),
            Text(
              Tr.of(
                context,
                ar: 'تعذر تحميل الملصقات.',
                en: 'Could not load the stickers.',
              ),
              textAlign: TextAlign.center,
              style: context.text.bodySmall?.copyWith(
                color: context.palette.textSecondary,
              ),
            ),
            const SizedBox(height: Space.sm),
            WingsButton(
              label: Tr.of(context, ar: 'إعادة المحاولة', en: 'Try again'),
              height: Sizes.buttonCompact,
              variant: WingsButtonVariant.tonal,
              onPressed: onRetry,
            ),
          ],
        ),
      ),
    );
  }
}
