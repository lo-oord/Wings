import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// One shelf of the sticker catalogue (expressions, laughter, chibi…).
@immutable
class StickerCategory {
  const StickerCategory({
    required this.id,
    required this.nameAr,
    required this.nameEn,
    required this.sortOrder,
  });

  factory StickerCategory.fromJson(Map<String, dynamic> json) {
    final name = json['name'];
    final names = name is Map ? name : const <String, dynamic>{};
    return StickerCategory(
      id: json['id'] as String? ?? '',
      nameAr: names['ar'] as String? ?? '',
      nameEn: names['en'] as String? ?? '',
      sortOrder: (json['sortOrder'] as num?)?.toInt() ?? 0,
    );
  }

  final String id;
  final String nameAr;
  final String nameEn;
  final int sortOrder;

  String name(bool arabic) => arabic ? nameAr : nameEn;
}

/// A single sticker defined by `assets/stickers/sticker_manifest.json`.
///
/// The [id] is the only value written to Firestore, so it must stay stable
/// forever: renaming an asset file never changes the id, and an id is never
/// reused for different artwork. A sticker that is retired is marked
/// `enabled: false` instead of being deleted, so old comments still resolve it.
@immutable
class Sticker {
  const Sticker({
    required this.id,
    required this.categoryId,
    required this.assetPath,
    required this.nameAr,
    required this.nameEn,
    this.keywordsAr = const <String>[],
    this.keywordsEn = const <String>[],
    this.sortOrder = 0,
    this.enabled = true,
    this.source = '',
    this.license = '',
  });

  factory Sticker.fromJson(Map<String, dynamic> json) {
    final name = json['displayName'];
    final names = name is Map ? name : const <String, dynamic>{};
    final keywords = json['keywords'];
    final keywordMap = keywords is Map ? keywords : const <String, dynamic>{};
    List<String> list(Object? value) => value is List
        ? value.whereType<String>().toList(growable: false)
        : const <String>[];
    return Sticker(
      id: json['stickerId'] as String? ?? json['id'] as String? ?? '',
      categoryId: json['categoryId'] as String? ?? '',
      assetPath: json['assetPath'] as String? ?? '',
      nameAr: names['ar'] as String? ?? '',
      nameEn: names['en'] as String? ?? '',
      keywordsAr: list(keywordMap['ar']),
      keywordsEn: list(keywordMap['en']),
      sortOrder: (json['sortOrder'] as num?)?.toInt() ?? 0,
      enabled: json['enabled'] != false,
      source: json['source'] as String? ?? '',
      license: json['license'] as String? ?? '',
    );
  }

  final String id;
  final String categoryId;
  final String assetPath;
  final String nameAr;
  final String nameEn;
  final List<String> keywordsAr;
  final List<String> keywordsEn;
  final int sortOrder;
  final bool enabled;
  final String source;
  final String license;

  String name(bool arabic) => arabic ? nameAr : nameEn;

  /// Local search across the display name, the category and the keywords, so
  /// typing «ضحك» or «laugh» finds the same stickers in either language.
  bool matches(String query, {required bool arabic}) {
    final needle = query.trim().toLowerCase();
    if (needle.isEmpty) return true;
    final haystack = <String>[nameAr, nameEn, ...keywordsAr, ...keywordsEn];
    return haystack.any((value) => value.toLowerCase().contains(needle));
  }
}

/// The immutable sticker catalogue, read once from the bundled manifest.
///
/// Everything is local: no network request is ever made to show a sticker.
/// Stickers whose asset is missing from the bundle are dropped at load time and
/// reported through [missingAssets], so the picker can never offer a broken
/// image.
@immutable
class StickerCatalog {
  StickerCatalog._({
    required this.categories,
    required this.stickers,
    required this.missingAssets,
  }) : _byId = <String, Sticker>{
         for (final sticker in stickers) sticker.id: sticker,
       };

  /// Bundled manifest path. Keep in sync with `pubspec.yaml`.
  static const String manifestPath = 'assets/stickers/sticker_manifest.json';

  /// The pseudo-category that shows every sticker.
  static const String allCategoryId = 'all';

  final List<StickerCategory> categories;
  final List<Sticker> stickers;

  /// Asset paths referenced by the manifest but absent from the bundle.
  final List<String> missingAssets;

  final Map<String, Sticker> _byId;

  /// Every enabled sticker, in display order.
  List<Sticker> get all => stickers;

  Sticker? byId(String? id) {
    if (id == null || id.isEmpty) return null;
    return _byId[id];
  }

  /// Categories that actually contain a sticker, sorted for the picker. The
  /// «الكل» shelf is always present and always first.
  List<StickerCategory> get availableCategories {
    final counts = <String, int>{};
    for (final sticker in stickers) {
      counts.update(
        sticker.categoryId,
        (value) => value + 1,
        ifAbsent: () => 1,
      );
    }
    final available =
        categories
            .where((category) => counts[category.id] != null)
            .toList(growable: false)
          ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    final all = categories.where((category) => category.id == allCategoryId);
    return <StickerCategory>[
      if (all.isNotEmpty)
        all.first
      else
        const StickerCategory(
          id: allCategoryId,
          nameAr: 'الكل',
          nameEn: 'All',
          sortOrder: 0,
        ),
      ...available.where((category) => category.id != allCategoryId),
    ];
  }

  List<Sticker> forCategory(String categoryId) {
    if (categoryId == allCategoryId) return all;
    return stickers
        .where((sticker) => sticker.categoryId == categoryId)
        .toList(growable: false);
  }

  /// Filters [categoryId] by [query]. An empty query returns the whole shelf.
  List<Sticker> search(
    String query, {
    required bool arabic,
    String categoryId = allCategoryId,
  }) {
    if (query.trim().isEmpty) return forCategory(categoryId);
    final category = categories
        .where((item) => item.id == categoryId)
        .firstOrNull;
    return forCategory(categoryId)
        .where((sticker) {
          if (sticker.matches(query, arabic: arabic)) return true;
          final shelf = category?.name(arabic) ?? '';
          return shelf.isNotEmpty &&
              shelf.toLowerCase().contains(query.trim().toLowerCase());
        })
        .toList(growable: false);
  }

  /// Stickers for a list of ids, dropping unknown and disabled ids.
  List<Sticker> resolveAll(Iterable<String> ids) => <Sticker>[
    for (final id in ids) ?byId(id),
  ];

  static StickerCatalog fromJson(
    Map<String, dynamic> json, {
    Set<String>? availableAssets,
  }) {
    final rawCategories = json['categories'];
    final rawStickers = json['stickers'];
    final categories = <StickerCategory>[
      if (rawCategories is List)
        for (final item in rawCategories)
          if (item is Map)
            StickerCategory.fromJson(Map<String, dynamic>.from(item)),
    ];
    final missing = <String>[];
    final seen = <String>{};
    final stickers = <Sticker>[];
    if (rawStickers is List) {
      for (final item in rawStickers) {
        if (item is! Map) continue;
        final sticker = Sticker.fromJson(Map<String, dynamic>.from(item));
        if (sticker.id.isEmpty || !sticker.enabled) continue;
        if (!seen.add(sticker.id)) continue;
        if (sticker.assetPath.isEmpty ||
            (availableAssets != null &&
                !availableAssets.contains(sticker.assetPath))) {
          missing.add(
            sticker.assetPath.isEmpty ? sticker.id : sticker.assetPath,
          );
          continue;
        }
        stickers.add(sticker);
      }
    }
    stickers.sort((a, b) {
      final order = a.sortOrder.compareTo(b.sortOrder);
      return order != 0 ? order : a.id.compareTo(b.id);
    });
    return StickerCatalog._(
      categories: categories,
      stickers: List<Sticker>.unmodifiable(stickers),
      missingAssets: List<String>.unmodifiable(missing),
    );
  }

  /// Reads and validates the bundled manifest. Any asset that is not in the
  /// bundle is skipped; in debug builds the omission is printed so a broken
  /// download is visible without ever crashing the comments UI.
  static Future<StickerCatalog> load({AssetBundle? bundle}) async {
    final assets = bundle ?? rootBundle;
    final raw = await assets.loadString(manifestPath);
    final decoded = jsonDecode(raw);
    if (decoded is! Map) return fromJson(const <String, dynamic>{});
    Set<String>? available;
    try {
      final manifest = await AssetManifest.loadFromAssetBundle(assets);
      available = manifest.listAssets().toSet();
    } on Object {
      // Older engine without AssetManifest support: skip asset validation.
      available = null;
    }
    final catalog = fromJson(
      Map<String, dynamic>.from(decoded),
      availableAssets: available,
    );
    if (catalog.missingAssets.isNotEmpty) {
      debugPrint(
        'Wings stickers: ${catalog.missingAssets.length} missing asset(s): '
        '${catalog.missingAssets.join(', ')}',
      );
    }
    return catalog;
  }
}
