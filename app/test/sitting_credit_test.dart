import 'package:flutter_test/flutter_test.dart';
import 'package:i_can_read/features/reader/domain/sitting_credit.dart';

/// The reader can turn to any page of the book. These are the rules that keep
/// that freedom from turning into progress nobody made.
void main() {
  group('sittingCredit', () {
    // A plan over pages 10..100 of a longer file: nine pages of front matter
    // the reader left out, and an index after page 100.
    DayAssignment? credit({required int openedAt, required int furthest}) =>
        sittingCredit(
          openedAt: openedAt,
          furthest: furthest,
          planStart: 10,
          planEnd: 100,
        );

    test('an ordinary sitting is credited as it was read', () {
      final read = credit(openedAt: 20, furthest: 32)!;

      expect(read.fromPage, 20);
      expect(read.toPage, 32);
    });

    test('turning back to re-read does not un-read the pages behind', () {
      // Read to 32, turned back to 25 to look at a paragraph again, and
      // finished from there. Twenty-three pages were read, not six.
      final read = credit(openedAt: 20, furthest: 32)!;

      expect(read.pageCount, 13);
    });

    test('the front matter before the plan is not credited', () {
      // Opened on the title page and read into the book proper.
      final read = credit(openedAt: 2, furthest: 40)!;

      expect(read.fromPage, 10, reason: 'the plan starts at 10');
      expect(read.toPage, 40);
    });

    test('the index past the plan is not credited', () {
      final read = credit(openedAt: 90, furthest: 140)!;

      expect(read.fromPage, 90);
      expect(read.toPage, 100, reason: 'the plan ends at 100');
    });

    test('a sitting spent entirely in the index credits nothing', () {
      expect(credit(openedAt: 120, furthest: 140), isNull);
    });

    test('a sitting spent entirely in the front matter credits nothing', () {
      expect(credit(openedAt: 2, furthest: 8), isNull);
    });

    test('a single page is a page', () {
      final read = credit(openedAt: 44, furthest: 44)!;

      expect(read.pageCount, 1);
    });

    test('flipping to the very end credits the plan, never past it', () {
      // The one case the freedom makes possible: a reader who jumps to the
      // last page of the file and says they are done. The claim is theirs to
      // make, but it cannot reach past the pages the plan is about.
      final read = credit(openedAt: 10, furthest: 900)!;

      expect(read.toPage, 100);
    });
  });
}
