import 'package:flutter_test/flutter_test.dart';
import 'package:i_can_read/core/planning/reading_pace.dart';

/// Ten pages in ten minutes: a minute a page, and exactly the minimum sample.
const _minute = ReadingPace(pages: 10, time: Duration(minutes: 10));

void main() {
  group('knowing the pace at all', () {
    test('nothing measured says nothing', () {
      expect(ReadingPace.unknown.isKnown, isFalse);
      expect(ReadingPace.unknown.perPage, isNull);
      expect(ReadingPace.unknown.estimateFor(15), isNull);
    });

    test('one distracted page does not become a prediction', () {
      const pace = ReadingPace(pages: 1, time: Duration(hours: 4));

      expect(pace.isKnown, isFalse);
      expect(pace.estimateFor(15), isNull);
    });

    test('the minimum sample is enough, not one page past it', () {
      expect(_minute.isKnown, isTrue);
      expect(
        const ReadingPace(
          pages: ReadingPace.minimumPages - 1,
          time: Duration(minutes: 9),
        ).isKnown,
        isFalse,
      );
    });

    test('pages with no time behind them are not a pace', () {
      // Cannot arise from the query, which filters zero-duration rows, but a
      // pace of "instant" would poison every estimate if it ever did.
      const pace = ReadingPace(pages: 40, time: Duration.zero);

      expect(pace.isKnown, isFalse);
      expect(pace.estimateFor(15), isNull);
    });
  });

  group('estimating a portion', () {
    test('scales the measured ratio to the pages asked about', () {
      expect(_minute.estimateFor(15), const Duration(minutes: 15));
      expect(_minute.perPage, const Duration(minutes: 1));
    });

    test('a portion with nothing left takes no time, rather than unknown', () {
      expect(_minute.estimateFor(0), Duration.zero);
      expect(_minute.estimateFor(-3), Duration.zero);
    });

    test('a fast reader keeps a per-page figure instead of rounding to zero', () {
      // Forty pages of plates in two minutes — three seconds a page. Dividing
      // before multiplying would floor this to nothing.
      const plates = ReadingPace(pages: 40, time: Duration(minutes: 2));

      expect(plates.perPage, const Duration(seconds: 3));
      expect(plates.estimateFor(15), const Duration(seconds: 45));
    });

    test('rounds to the nearest second rather than truncating', () {
      // Three pages a hundred seconds: 33.33s a page.
      const pace = ReadingPace(pages: 30, time: Duration(seconds: 1000));

      expect(pace.perPage, const Duration(seconds: 33));
      expect(pace.estimateFor(3), const Duration(seconds: 100));
    });
  });
}
