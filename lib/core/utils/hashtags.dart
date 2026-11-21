/// Hashtag and search-term helpers shared by every composer, the feed, the
/// search screen and the rules' client-side checks.
///
/// Anime hashtags are resolved from `animeRefs` so `#One Piece` opens the real
/// title page. Everything else is a free community hashtag registered in the
/// `hashtags` collection, keyed by its normalized slug so `#Anime`, `#anime`
/// and `# ANIME` can never become three different tags.
library;

/// Normalizes a tag into its stored slug: no `#`, no spaces, lower case.
String normalizeHashtag(String raw) {
  var value = raw.trim();
  while (value.startsWith('#')) {
    value = value.substring(1);
  }
  value = value.replaceAll(RegExp(r'[\s#]+'), '');
  return value.toLowerCase();
}

// A tag starts a word: `@user#tag` and `word#tag` stay plain text.
final RegExp _tagPattern = RegExp(r'(?:^|[\s])#([^#\s@]{1,40})');

/// The free hashtags written in [text], deduplicated and normalized.
///
/// Titles listed in [exclude] (the anime references the author picked) are left
/// out: those already have a real catalogue id and must not be duplicated as a
/// free tag.
List<String> extractHashtags(
  String text, {
  Iterable<String> exclude = const <String>[],
}) {
  final excluded = <String>{
    for (final title in exclude) normalizeHashtag(title),
  };
  final result = <String>[];
  for (final match in _tagPattern.allMatches(text)) {
    final tag = normalizeHashtag(match.group(1) ?? '');
    if (tag.length < 2 || tag.length > 40) continue;
    if (excluded.contains(tag)) continue;
    if (result.contains(tag)) continue;
    result.add(tag);
    if (result.length >= 6) break;
  }
  return result;
}

/// Lower-case words used by the community search index.
///
/// Firestore cannot do full-text search, so a post carries a bounded list of
/// its own words and a query matches a `searchTerms` array-contains. Tags are
/// inserted too, which is what makes a hashtag searchable by its name.
List<String> searchTermsFor(
  String text, {
  Iterable<String> hashtags = const <String>[],
  Iterable<String> extra = const <String>[],
}) {
  final result = <String>[];
  void add(String raw) {
    final term = raw.trim().toLowerCase();
    if (term.length < 2 || term.length > 40) return;
    if (result.contains(term)) return;
    if (result.length >= 24) return;
    result.add(term);
  }

  for (final word in text.split(RegExp(r'[^\p{L}\p{N}_#]+', unicode: true))) {
    add(word.replaceAll('#', ''));
  }
  for (final tag in hashtags) {
    add(tag);
  }
  for (final value in extra) {
    add(value);
  }
  return result;
}
