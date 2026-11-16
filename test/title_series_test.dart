import 'package:flutter_test/flutter_test.dart';
import 'package:wings/core/utils/title_series.dart';

void main() {
  group('seasonNumberFromTitle', () {
    test('reads Arabic part ordinals', () {
      expect(seasonNumberFromTitle('كابتن ماجد - الجزء الأول'), 1);
      expect(seasonNumberFromTitle('كابتن ماجد الجزء الثالث'), 3);
      expect(seasonNumberFromTitle('السنافر  -  الجزء الأول'), 1);
    });

    test('reads season markers with numbers', () {
      expect(seasonNumberFromTitle('أكاديمية بطلي (موسم 2)'), 2);
      expect(seasonNumberFromTitle('TopoGigio الموسم الثاني'), 2);
    });

    test('returns null when there is no marker', () {
      expect(seasonNumberFromTitle('عدنان ولينا'), isNull);
    });
  });

  group('seriesGroupKey', () {
    test('matches seasons of one work', () {
      expect(
        seriesGroupKey('ماروكو الصغيرة  - الجزء الأول'),
        seriesGroupKey('ماروكو الصغيرة  - الجزء الثاني'),
      );
    });

    test('keeps different works apart', () {
      expect(
        seriesGroupKey('عدنان ولينا'),
        isNot(seriesGroupKey('جزيرة الكنز')),
      );
    });
  });

  group('groupTitlesBySeason', () {
    test('keeps seasons separate but adjacent in season order', () {
      final titles = <String>[
        'كابتن ماجد - الجزء الثالث',
        'سلام دانك',
        'كابتن ماجد - الجزء الأول',
        'كابتن ماجد - الجزء الثاني',
        'عدنان ولينا',
      ];
      final grouped = groupTitlesBySeason(titles, (title) => title);
      expect(grouped, <String>[
        'كابتن ماجد - الجزء الأول',
        'كابتن ماجد - الجزء الثاني',
        'كابتن ماجد - الجزء الثالث',
        'سلام دانك',
        'عدنان ولينا',
      ]);
    });

    test('leaves ungrouped results in their original order', () {
      final titles = <String>['عدنان ولينا', 'جزيرة الكنز', 'رعد العملاق'];
      expect(groupTitlesBySeason(titles, (title) => title), titles);
    });
  });
}
