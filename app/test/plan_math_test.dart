import 'package:flutter_test/flutter_test.dart';
import 'package:i_can_read/core/planning/plan_math.dart';

/// 1 Jan 2026, the anchor for most scenarios below.
final _jan1 = DateTime(2026, 1, 1);

DateTime _jan(int day) => DateTime(2026, 1, day);

/// A 100-page book at 10 pages a day, starting 1 Jan and due 10 Jan.
PlanSpec _tenADay() => PlanSpec.fromPagesPerDay(
  startPage: 1,
  endPage: 100,
  startDate: _jan1,
  pagesPerDay: 10,
);

void main() {
  group('date helpers', () {
    test('counts whole calendar days regardless of time of day', () {
      expect(
        daysBetween(DateTime(2026, 3, 29, 23, 59), DateTime(2026, 3, 30, 0, 1)),
        1,
      );
      expect(daysBetween(_jan(1), _jan(1)), 0);
      expect(daysBetween(_jan(10), _jan(1)), -9);
    });

    test('spans a DST transition without losing or gaining a day', () {
      // Whatever the machine's zone, these are 7 calendar days apart. A naive
      // Duration.inDays on local times can report 6 across a spring-forward.
      expect(daysBetween(DateTime(2026, 3, 25), DateTime(2026, 4, 1)), 7);
      expect(daysBetween(DateTime(2026, 10, 22), DateTime(2026, 10, 29)), 7);
    });

    test('inclusive day count treats a single day as one', () {
      expect(inclusiveDayCount(_jan(1), _jan(1)), 1);
      expect(inclusiveDayCount(_jan(1), _jan(10)), 10);
    });

    test('addDays rolls over months, years and leap days', () {
      expect(addDays(_jan(31), 1), DateTime(2026, 2, 1));
      expect(addDays(DateTime(2026, 12, 31), 1), DateTime(2027, 1, 1));
      expect(addDays(DateTime(2028, 2, 28), 1), DateTime(2028, 2, 29));
      expect(addDays(DateTime(2026, 2, 28), 1), DateTime(2026, 3, 1));
    });

    test('dateOnly strips the time component', () {
      expect(dateOnly(DateTime(2026, 1, 1, 23, 45, 12)), _jan1);
    });
  });

  group('PlanSpec.fromDeadline', () {
    test('divides evenly when the pages divide the days', () {
      final plan = PlanSpec.fromDeadline(
        startPage: 1,
        endPage: 100,
        startDate: _jan1,
        targetEndDate: _jan(10),
      );
      expect(plan.pagesPerDay, 10);
      expect(plan.totalPages, 100);
      expect(plan.mode, PlanMode.byDeadline);
    });

    test('rounds the daily quota up so the reader is never late', () {
      // 100 pages over 7 days is 14.28 a day; 14 would overrun the deadline.
      final plan = PlanSpec.fromDeadline(
        startPage: 1,
        endPage: 100,
        startDate: _jan1,
        targetEndDate: _jan(7),
      );
      expect(plan.pagesPerDay, 15);
      expect(plan.pagesPerDay * 7, greaterThanOrEqualTo(plan.totalPages));
    });

    test('a same-day deadline puts the whole book in one day', () {
      final plan = PlanSpec.fromDeadline(
        startPage: 1,
        endPage: 100,
        startDate: _jan1,
        targetEndDate: _jan1,
      );
      expect(plan.pagesPerDay, 100);
    });

    test('a generous deadline floors the quota at one page a day', () {
      final plan = PlanSpec.fromDeadline(
        startPage: 1,
        endPage: 10,
        startDate: _jan1,
        targetEndDate: _jan(30),
      );
      expect(plan.pagesPerDay, 1);
      // The reader finishes early; the target date is kept as asked for.
      expect(plan.targetEndDate, _jan(30));
    });

    test('honours a start page past the front matter', () {
      final plan = PlanSpec.fromDeadline(
        startPage: 21,
        endPage: 120,
        startDate: _jan1,
        targetEndDate: _jan(10),
      );
      expect(plan.totalPages, 100);
      expect(plan.pagesPerDay, 10);
    });

    test('rejects a deadline before the start date', () {
      expect(
        () => PlanSpec.fromDeadline(
          startPage: 1,
          endPage: 100,
          startDate: _jan(10),
          targetEndDate: _jan(1),
        ),
        throwsArgumentError,
      );
    });
  });

  group('PlanSpec.fromPagesPerDay', () {
    test('computes the finish date inclusive of the start day', () {
      final plan = _tenADay();
      expect(plan.targetEndDate, _jan(10));
      expect(plan.mode, PlanMode.byPagesPerDay);
    });

    test('rounds the day count up for a ragged last day', () {
      final plan = PlanSpec.fromPagesPerDay(
        startPage: 1,
        endPage: 100,
        startDate: _jan1,
        pagesPerDay: 15,
      );
      // 7 days: six full days of 15 plus a final day of 10.
      expect(plan.targetEndDate, _jan(7));
    });

    test('a quota larger than the book finishes the same day', () {
      final plan = PlanSpec.fromPagesPerDay(
        startPage: 1,
        endPage: 100,
        startDate: _jan1,
        pagesPerDay: 500,
      );
      expect(plan.targetEndDate, _jan1);
    });

    test('a one-page book is a one-day plan', () {
      final plan = PlanSpec.fromPagesPerDay(
        startPage: 1,
        endPage: 1,
        startDate: _jan1,
        pagesPerDay: 10,
      );
      expect(plan.totalPages, 1);
      expect(plan.targetEndDate, _jan1);
    });

    test('rejects a non-positive quota', () {
      expect(
        () => PlanSpec.fromPagesPerDay(
          startPage: 1,
          endPage: 100,
          startDate: _jan1,
          pagesPerDay: 0,
        ),
        throwsArgumentError,
      );
    });

    test('rejects an inverted or zero page range', () {
      expect(
        () => PlanSpec.fromPagesPerDay(
          startPage: 50,
          endPage: 10,
          startDate: _jan1,
          pagesPerDay: 5,
        ),
        throwsArgumentError,
      );
      expect(
        () => PlanSpec.fromPagesPerDay(
          startPage: 0,
          endPage: 10,
          startDate: _jan1,
          pagesPerDay: 5,
        ),
        throwsArgumentError,
      );
    });
  });

  group('splitAcrossSessions', () {
    test('splits evenly when it divides cleanly', () {
      expect(splitAcrossSessions(10, sessionCount: 2), [5, 5]);
      expect(splitAcrossSessions(12, sessionCount: 3), [4, 4, 4]);
    });

    test('gives the spare pages to the earliest sessions', () {
      expect(splitAcrossSessions(10, sessionCount: 3), [4, 3, 3]);
      expect(splitAcrossSessions(11, sessionCount: 3), [4, 4, 3]);
    });

    test('leaves trailing sessions empty when pages are scarce', () {
      expect(splitAcrossSessions(2, sessionCount: 3), [1, 1, 0]);
      expect(splitAcrossSessions(1, sessionCount: 4), [1, 0, 0, 0]);
      expect(splitAcrossSessions(0, sessionCount: 3), [0, 0, 0]);
    });

    test('respects weights for uneven sessions', () {
      expect(splitAcrossSessions(10, sessionCount: 3, weights: [2, 1, 1]), [
        5,
        3,
        2,
      ]);
      expect(splitAcrossSessions(9, sessionCount: 2, weights: [2, 1]), [6, 3]);
    });

    test('keeps a zero-weight session empty', () {
      expect(splitAcrossSessions(5, sessionCount: 3, weights: [1, 0, 1]), [
        3,
        0,
        2,
      ]);
    });

    test('the parts always sum back to the quota', () {
      for (var pages = 0; pages <= 60; pages++) {
        for (var sessions = 1; sessions <= 5; sessions++) {
          final parts = splitAcrossSessions(pages, sessionCount: sessions);
          expect(
            parts.fold<int>(0, (sum, p) => sum + p),
            pages,
            reason: 'split of $pages across $sessions sessions',
          );
          expect(parts.length, sessions);
          expect(parts.every((p) => p >= 0), isTrue);
        }
      }
    });

    test('rejects malformed input', () {
      expect(
        () => splitAcrossSessions(10, sessionCount: 0),
        throwsArgumentError,
      );
      expect(
        () => splitAcrossSessions(-1, sessionCount: 2),
        throwsArgumentError,
      );
      expect(
        () => splitAcrossSessions(10, sessionCount: 3, weights: [1, 1]),
        throwsArgumentError,
      );
      expect(
        () => splitAcrossSessions(10, sessionCount: 2, weights: [0, 0]),
        throwsArgumentError,
      );
    });
  });

  group('nextAssignment', () {
    test('starts at the plan start page when nothing has been read', () {
      expect(
        nextAssignment(_tenADay(), 0),
        const DayAssignment(fromPage: 1, toPage: 10),
      );
    });

    test('continues from the page after the last one read', () {
      expect(
        nextAssignment(_tenADay(), 10),
        const DayAssignment(fromPage: 11, toPage: 20),
      );
    });

    test('the final portion is short rather than overshooting the book', () {
      final assignment = nextAssignment(_tenADay(), 95)!;
      expect(assignment, const DayAssignment(fromPage: 96, toPage: 100));
      expect(assignment.pageCount, 5);
    });

    test('returns null once the plan is finished', () {
      expect(nextAssignment(_tenADay(), 100), isNull);
      expect(nextAssignment(_tenADay(), 150), isNull);
    });

    test('ignores progress that sits before the plan start page', () {
      final plan = PlanSpec.fromPagesPerDay(
        startPage: 21,
        endPage: 120,
        startDate: _jan1,
        pagesPerDay: 10,
      );
      expect(
        nextAssignment(plan, 0),
        const DayAssignment(fromPage: 21, toPage: 30),
      );
      expect(
        nextAssignment(plan, 15),
        const DayAssignment(fromPage: 21, toPage: 30),
      );
    });
  });

  group('projectedEndDate — missed days push the finish out', () {
    test('an untouched plan finishes on its target date', () {
      expect(
        projectedEndDate(_tenADay(), lastPageRead: 0, today: _jan1),
        _jan(10),
      );
    });

    test('four missed days move the finish four days later', () {
      // The daily quota stays at 10; only the end date moves.
      expect(
        projectedEndDate(_tenADay(), lastPageRead: 0, today: _jan(5)),
        _jan(14),
      );
    });

    test('reading ahead pulls the finish date in', () {
      // 50 pages read on day 2 leaves 50, i.e. five more days from tomorrow.
      expect(
        projectedEndDate(
          _tenADay(),
          lastPageRead: 50,
          today: _jan(2),
          pagesReadToday: 50,
        ),
        _jan(7),
      );
    });

    test('todays remaining capacity can absorb the last pages', () {
      expect(
        projectedEndDate(_tenADay(), lastPageRead: 90, today: _jan(9)),
        _jan(9),
      );
    });

    test('a quota already spent today pushes the rest to tomorrow', () {
      expect(
        projectedEndDate(
          _tenADay(),
          lastPageRead: 90,
          today: _jan(9),
          pagesReadToday: 10,
        ),
        _jan(10),
      );
    });

    test('a finished plan projects to today', () {
      expect(
        projectedEndDate(_tenADay(), lastPageRead: 100, today: _jan(7)),
        _jan(7),
      );
    });
  });

  group('scheduleStatus', () {
    test('day one before reading is on track, not behind', () {
      final status = scheduleStatus(_tenADay(), lastPageRead: 0, today: _jan1);
      expect(status.expectedPages, 0);
      expect(status.isOnTrack, isTrue);
    });

    test('reports whole days behind after missed days', () {
      final status = scheduleStatus(
        _tenADay(),
        lastPageRead: 0,
        today: _jan(5),
      );
      expect(status.expectedPages, 40);
      expect(status.deltaPages, -40);
      expect(status.deltaDays, -4);
      expect(status.isBehind, isTrue);
    });

    test('the days-behind figure matches how far the finish date slipped', () {
      final plan = _tenADay();
      final status = scheduleStatus(plan, lastPageRead: 0, today: _jan(5));
      final projected = projectedEndDate(plan, lastPageRead: 0, today: _jan(5));
      expect(daysBetween(plan.targetEndDate, projected), -status.deltaDays);
    });

    test('a partial day of slippage still counts as on track', () {
      final status = scheduleStatus(
        _tenADay(),
        lastPageRead: 5,
        today: _jan(2),
      );
      expect(status.expectedPages, 10);
      expect(status.deltaPages, -5);
      expect(status.deltaDays, 0);
      expect(status.isOnTrack, isTrue);
    });

    test('reports days ahead when reading fast', () {
      final status = scheduleStatus(
        _tenADay(),
        lastPageRead: 50,
        today: _jan(3),
      );
      expect(status.expectedPages, 20);
      expect(status.deltaDays, 3);
      expect(status.isAhead, isTrue);
    });

    test('never expects more pages than the book holds', () {
      final status = scheduleStatus(
        _tenADay(),
        lastPageRead: 100,
        today: _jan(90),
      );
      expect(status.expectedPages, 100);
      expect(status.isOnTrack, isTrue);
    });

    test('expects nothing before the plan has started', () {
      final status = scheduleStatus(
        _tenADay(),
        lastPageRead: 0,
        today: DateTime(2025, 12, 20),
      );
      expect(status.expectedPages, 0);
      expect(status.isOnTrack, isTrue);
    });
  });

  group('progress accounting', () {
    test('counts pages read within the plan range only', () {
      final plan = PlanSpec.fromPagesPerDay(
        startPage: 21,
        endPage: 120,
        startDate: _jan1,
        pagesPerDay: 10,
      );
      expect(plan.pagesReadFrom(0), 0);
      expect(plan.pagesReadFrom(20), 0);
      expect(plan.pagesReadFrom(21), 1);
      expect(plan.pagesReadFrom(120), 100);
      expect(plan.pagesReadFrom(200), 100);
    });

    test('remaining pages and completion agree', () {
      final plan = _tenADay();
      expect(plan.remainingPagesFrom(0), 100);
      expect(plan.remainingPagesFrom(40), 60);
      expect(plan.remainingPagesFrom(100), 0);
      expect(plan.isComplete(100), isTrue);
      expect(plan.isComplete(99), isFalse);
    });
  });

  group('end to end', () {
    test('a plan read exactly on schedule lands on its target date', () {
      final plan = _tenADay();
      var lastPage = 0;
      var day = 0;

      while (!plan.isComplete(lastPage)) {
        final assignment = nextAssignment(plan, lastPage)!;
        lastPage = assignment.toPage;
        day++;
        expect(day, lessThanOrEqualTo(100), reason: 'plan must terminate');
      }

      expect(lastPage, 100);
      expect(addDays(plan.startDate, day - 1), plan.targetEndDate);
    });

    test('a ragged plan still terminates and covers every page', () {
      final plan = PlanSpec.fromPagesPerDay(
        startPage: 7,
        endPage: 103,
        startDate: _jan1,
        pagesPerDay: 13,
      );
      var lastPage = 0;
      var covered = 0;
      var previousEnd = plan.startPage - 1;

      while (!plan.isComplete(lastPage)) {
        final assignment = nextAssignment(plan, lastPage)!;
        expect(assignment.fromPage, previousEnd + 1, reason: 'no gaps');
        covered += assignment.pageCount;
        previousEnd = assignment.toPage;
        lastPage = assignment.toPage;
      }

      expect(covered, plan.totalPages);
      expect(lastPage, 103);
    });
  });

  group('readingDay', () {
    test('daytime belongs to its own calendar day', () {
      expect(readingDay(DateTime(2026, 1, 7, 9, 30)), _jan(7));
      expect(readingDay(DateTime(2026, 1, 7, 23, 59)), _jan(7));
    });

    test('the small hours still belong to the day before', () {
      // Someone reading at 01:00 is finishing the day they are awake in.
      expect(readingDay(DateTime(2026, 1, 8, 0, 0)), _jan(7));
      expect(readingDay(DateTime(2026, 1, 8, 1, 30)), _jan(7));
      expect(readingDay(DateTime(2026, 1, 8, 3, 59)), _jan(7));
    });

    test('the boundary itself starts the new day', () {
      expect(readingDay(DateTime(2026, 1, 8, 4, 0)), _jan(8));
    });

    test('rolling back over a month boundary lands on the last day', () {
      expect(readingDay(DateTime(2026, 2, 1, 2, 0)), DateTime(2026, 1, 31));
    });

    test('the boundary sits where the constant says', () {
      expect(readingDayStartHour, 4);
    });
  });

  group('scheduleStatus with pauses', () {
    test('paused days are not counted against the reader', () {
      final plan = _tenADay();
      // Six days elapsed, four of them paused, twenty pages read: the two
      // days that actually ran expected exactly twenty.
      final status = scheduleStatus(
        plan,
        lastPageRead: 20,
        today: _jan(7),
        pausedDays: 4,
      );

      expect(status.expectedPages, 20);
      expect(status.isOnTrack, isTrue);
    });

    test('without the pause the same reader looks four days behind', () {
      final status = scheduleStatus(
        _tenADay(),
        lastPageRead: 20,
        today: _jan(7),
      );

      expect(status.expectedPages, 60);
      expect(status.deltaDays, -4);
    });

    test('a pause longer than the plan cannot invent progress', () {
      final status = scheduleStatus(
        _tenADay(),
        lastPageRead: 0,
        today: _jan(7),
        pausedDays: 99,
      );

      expect(status.expectedPages, 0);
      expect(status.isOnTrack, isTrue);
    });
  });
}
