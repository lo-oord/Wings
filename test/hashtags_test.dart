import 'package:flutter_test/flutter_test.dart';
import 'package:wings/core/utils/hashtags.dart';

void main() {
  group('normalizeHashtag', () {
    test('removes the marker, spaces and case', () {
      expect(normalizeHashtag(' #Anime '), 'anime');
      expect(normalizeHashtag('# B e s t   Characters'), 'bestcharacters');
      expect(normalizeHashtag('أنمي'), 'أنمي');
    });
  });

  group('extractHashtags', () {
    test('collects unique tags and skips anime titles', () {
      final tags = extractHashtags(
        '#Anime أعجبني #OnePiece و #anime مرة أخرى #Recommendations',
        exclude: const <String>['One Piece'],
      );
      expect(tags, <String>['anime', 'recommendations']);
    });

    test('ignores a one-character tag and caps the list', () {
      expect(extractHashtags('#a ok'), isEmpty);
      final many = List<String>.generate(10, (index) => '#tag$index').join(' ');
      expect(extractHashtags(many).length, 6);
    });

    test('mention text is not a tag', () {
      expect(extractHashtags('@user#tag'), isEmpty);
    });
  });

  group('searchTermsFor', () {
    test('keeps words and tags without duplicates', () {
      final terms = searchTermsFor(
        'Solo Leveling is great',
        hashtags: <String>['sololeveling', 'solo'],
      );
      expect(terms, contains('solo'));
      expect(terms, contains('leveling'));
      expect(terms, contains('sololeveling'));
      expect(terms.where((term) => term == 'solo').length, 1);
    });

    test('drops single letters and caps the index size', () {
      final long = List<String>.generate(40, (index) => 'word$index').join(' ');
      final terms = searchTermsFor('a $long');
      expect(terms.contains('a'), isFalse);
      expect(terms.length, lessThanOrEqualTo(24));
    });
  });
}
