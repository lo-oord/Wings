/// Helpers that recognise season/part markers in catalogue titles.
///
/// Several sources publish every season as its own entry
/// («كابتن ماجد - الجزء الأول», «كابتن ماجد الجزء الثاني» …). Search results
/// stay separate works, but they are grouped so all seasons of one title are
/// listed next to each other in season order.
library;

const Map<String, int> _ordinals = <String, int>{
  'اول': 1,
  'أول': 1,
  'الاول': 1,
  'الأول': 1,
  'ثاني': 2,
  'الثاني': 2,
  'ثالث': 3,
  'الثالث': 3,
  'رابع': 4,
  'الرابع': 4,
  'خامس': 5,
  'الخامس': 5,
  'سادس': 6,
  'السادس': 6,
  'سابع': 7,
  'السابع': 7,
  'ثامن': 8,
  'الثامن': 8,
  'تاسع': 9,
  'التاسع': 9,
  'عاشر': 10,
  'العاشر': 10,
  'حادي عشر': 11,
  'الحادي عشر': 11,
  'ثاني عشر': 12,
  'الثاني عشر': 12,
};

final RegExp _marker = RegExp(
  r'(?:^|[\s\-–—_/(])(?:ال)?(?:جزء|موسم|بارت|season|part)\s*[:#\-]?\s*'
  r'((?:ال)?(?:حادي عشر|ثاني عشر|أول|اول|[ثربخستع]اني|[ثربخستع]الث|'
  r'رابع|خامس|سادس|سابع|ثامن|تاسع|عاشر)|[0-9]{1,2})'
  r'(?:\s*(?:و|and)\s*(?:ال)?(?:أول|اول|ثاني|الثاني|ثالث|الثالث|رابع|الرابع|'
  r'خامس|الخامس|سادس|السادس|سابع|السابع|ثامن|الثامن|تاسع|التاسع|عاشر|'
  r'العاشر))?',
  caseSensitive: false,
);

final RegExp _diacritics = RegExp('[\u064B-\u0652\u0670\u06D6-\u06ED]');
final RegExp _spaces = RegExp(r'\s+');
final RegExp _punctuation = RegExp('[.,،؛:!?()\\[\\]{}«»"\'`~*_\\-–—/\\\\|+]+');

/// Folds Arabic letters, diacritics and case so titles compare reliably.
String normalizeArabicText(String value) => value
    .replaceAll(_diacritics, '')
    .replaceAll('أ', 'ا')
    .replaceAll('إ', 'ا')
    .replaceAll('آ', 'ا')
    .replaceAll('ى', 'ي')
    .replaceAll('ة', 'ه')
    .toLowerCase();

/// The season/part number carried by a title, if any.
int? seasonNumberFromTitle(String title) {
  int? number;
  for (final match in _marker.allMatches(title)) {
    final raw = match.group(1);
    if (raw == null) continue;
    final digits = int.tryParse(raw);
    final parsed = digits ?? _ordinals[normalizeArabicText(raw).trim()];
    if (parsed == null) continue;
    if (number == null || parsed < number) number = parsed;
  }
  return number;
}

/// The season/part label carried by a title, e.g. «الجزء الثاني».
String? seasonLabelFromTitle(String title) {
  final match = _marker.firstMatch(title);
  if (match == null) return null;
  final raw = match.group(1);
  if (raw == null) return null;
  final number = seasonNumberFromTitle(title);
  if (number == null) return null;
  final through = match.end;
  final label = title.substring(match.start, through).trim();
  return label.isEmpty ? null : label;
}

/// Normalised base title used to compare seasons of the same work.
String seriesGroupKey(String title) {
  final stripped = title.replaceAll(_marker, ' ');
  final normalized = normalizeArabicText(stripped)
      .replaceAll(_punctuation, ' ');
  return normalized.replaceAll(_spaces, ' ').trim();
}

/// Groups items so that seasons of one work are adjacent and in season order.
///
/// Items keep their own identity: nothing is merged into a single card. Only
/// the ordering changes, and groups stay in the order they first appear.
List<T> groupTitlesBySeason<T>(
  Iterable<T> items,
  String Function(T item) titleOf,
) {
  final groups = <String, List<T>>{};
  final order = <String>[];
  for (final item in items) {
    final key = seriesGroupKey(titleOf(item));
    final group = groups[key];
    if (group == null) {
      groups[key] = <T>[item];
      order.add(key);
    } else {
      group.add(item);
    }
  }

  final result = <T>[];
  for (final key in order) {
    final group = groups[key]!;
    if (group.length == 1) {
      result.add(group.first);
      continue;
    }
    final indexed =
        <({int index, int season, T item})>[
          for (var i = 0; i < group.length; i++)
            (
              index: i,
              season: seasonNumberFromTitle(titleOf(group[i])) ?? i + 1,
              item: group[i],
            ),
        ]..sort((a, b) {
          final bySeason = a.season.compareTo(b.season);
          if (bySeason != 0) return bySeason;
          return a.index.compareTo(b.index);
        });
    result.addAll(indexed.map((entry) => entry.item));
  }
  return result;
}
