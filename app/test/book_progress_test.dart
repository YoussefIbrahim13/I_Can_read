import 'package:flutter_test/flutter_test.dart';
import 'package:i_can_read/core/planning/plan_math.dart';
import 'package:i_can_read/features/book_detail/domain/book_progress.dart';

DateTime _jan(int day) => DateTime(2026, 1, day);

/// A 100-page book at 10 pages a day, starting 1 Jan and due 10 Jan.
PlanSpec _tenADay() => PlanSpec.fromPagesPerDay(
  startPage: 1,
  endPage: 100,
  startDate: _jan(1),
  pagesPerDay: 10,
);

BookProgress _progress({
  PlanSpec? plan,
  int lastPageRead = 0,
  int sessionCount = 1,
  DateTime? today,
  int pagesReadToday = 0,
  int pausedDays = 0,
  DateTime? pausedAt,
}) {
  return buildBookProgress(
    plan: plan ?? _tenADay(),
    lastPageRead: lastPageRead,
    sessionCount: sessionCount,
    today: today ?? _jan(5),
    pagesReadToday: pagesReadToday,
    pausedDays: pausedDays,
    pausedAt: pausedAt,
  );
}

void main() {
  group('progress', () {
    test('reports pages read against the plan range, not the book', () {
      // The plan skips the first 20 pages, so page 40 is 20 pages of work.
      final plan = PlanSpec.fromPagesPerDay(
        startPage: 21,
        endPage: 120,
        startDate: _jan(1),
        pagesPerDay: 10,
      );
      final progress = _progress(plan: plan, lastPageRead: 40);

      expect(progress.pagesRead, 20);
      expect(progress.totalPages, 100);
      expect(progress.fraction, 0.2);
    });

    test('a book not started is at zero rather than at a fraction of a page', () {
      expect(_progress().pagesRead, 0);
      expect(_progress().fraction, 0);
      expect(_progress().isComplete, isFalse);
    });

    test('reading past the last page is complete, not over 100%', () {
      final progress = _progress(lastPageRead: 140);

      expect(progress.pagesRead, 100);
      expect(progress.fraction, 1);
      expect(progress.isComplete, isTrue);
    });
  });

  group('lateness', () {
    test('a reader on pace is not late', () {
      // Four days done, forty pages read: exactly on the original schedule.
      final progress = _progress(lastPageRead: 40, today: _jan(5));

      expect(progress.projectedEndDate, _jan(10));
      expect(progress.targetEndDate, _jan(10));
      expect(progress.isLate, isFalse);
      expect(progress.schedule.isOnTrack, isTrue);
    });

    test('missed days move the finish date and leave the portion alone', () {
      // Four days elapsed, nothing read. The quota is still ten a day, so the
      // hundred pages now run from the fifth to the fourteenth.
      final progress = _progress(lastPageRead: 0, today: _jan(5));

      expect(progress.pagesPerDay, 10);
      expect(progress.projectedEndDate, _jan(14));
      expect(progress.isLate, isTrue);
      expect(progress.schedule.deltaDays, -4);
    });

    test('reading ahead pulls the finish date in and is never late', () {
      // Twenty pages left: ten today, ten tomorrow.
      final progress = _progress(lastPageRead: 80, today: _jan(5));

      expect(progress.projectedEndDate, _jan(6));
      expect(progress.isLate, isFalse);
      expect(progress.schedule.isAhead, isTrue);
    });

    test('is late on a fractional day the schedule rounds away', () {
      // Five pages behind on a ten-a-day plan: `deltaDays` truncates that to
      // zero, but the finish still lands a day later than the target.
      final progress = _progress(lastPageRead: 35, today: _jan(5));

      expect(progress.schedule.isOnTrack, isTrue);
      expect(progress.projectedEndDate, _jan(11));
      expect(progress.isLate, isTrue);
    });

    test("today's reading counts toward today's quota", () {
      final progress = _progress(
        lastPageRead: 90,
        pagesReadToday: 10,
        today: _jan(5),
      );

      // The last ten pages are tomorrow's work, not a second helping of today's.
      expect(progress.projectedEndDate, _jan(6));
    });
  });

  group('pause', () {
    test('a pause holds the finish date where it was', () {
      // Paused on the fifth with fifty pages left; five days have since passed.
      // The projection still runs from the fifth — five days of ten pages,
      // landing on the ninth — instead of sliding a day for every day paused.
      final progress = _progress(
        lastPageRead: 50,
        today: _jan(10),
        pausedAt: _jan(5),
      );
      final running = _progress(lastPageRead: 50, today: _jan(10));

      expect(progress.isPaused, isTrue);
      expect(progress.projectedEndDate, _jan(9));
      expect(progress.isLate, isFalse);
      // The same book left running would have slipped past its target.
      expect(running.projectedEndDate, _jan(14));
      expect(running.isLate, isTrue);
    });

    test('days inside an unfinished pause are not counted as a debt', () {
      final running = _progress(lastPageRead: 40, today: _jan(10));
      final paused = _progress(
        lastPageRead: 40,
        today: _jan(10),
        pausedAt: _jan(5),
      );

      expect(running.schedule.deltaDays, -5);
      expect(paused.schedule.isOnTrack, isTrue);
    });

    test('days banked by an earlier pause stay excused after resuming', () {
      final progress = _progress(
        lastPageRead: 40,
        today: _jan(10),
        pausedDays: 5,
      );

      expect(progress.isPaused, isFalse);
      expect(progress.schedule.isOnTrack, isTrue);
    });
  });

  group('reading calendar', () {
    Map<DateTime, int> pagesOn(Map<int, int> byDayOfJanuary) => {
      for (final entry in byDayOfJanuary.entries) _jan(entry.key): entry.value,
    };

    test('lays days out in columns of seven, ending on today', () {
      final columns = heatmapColumns(
        pagesByDay: const {},
        today: _jan(10),
        pagesPerDay: 10,
        columns: 3,
      );

      expect(columns, hasLength(3));
      expect(columns.every((column) => column.length == 7), isTrue);
      expect(columns.last.last.date, _jan(10));
      // Twenty-one days ending on the tenth starts on 21 December.
      expect(columns.first.first.date, DateTime(2025, 12, 21));
    });

    test('never shows a day that has not happened yet', () {
      final columns = heatmapColumns(
        pagesByDay: const {},
        today: _jan(10),
        pagesPerDay: 10,
      );

      final latest = columns.last.last.date;
      expect(latest.isAfter(_jan(10)), isFalse);
    });

    test('a day with no reading is empty, not faintly full', () {
      final columns = heatmapColumns(
        pagesByDay: pagesOn({10: 5}),
        today: _jan(10),
        pagesPerDay: 10,
        columns: 1,
      );

      expect(columns.single.last.isEmpty, isFalse);
      expect(columns.single.last.intensity, 0.5);
      expect(columns.single.first.isEmpty, isTrue);
      expect(columns.single.first.intensity, 0);
    });

    test('a day that overshoots caps at full rather than glowing brighter', () {
      final columns = heatmapColumns(
        pagesByDay: pagesOn({10: 45}),
        today: _jan(10),
        pagesPerDay: 10,
        columns: 1,
      );

      expect(columns.single.last.intensity, 1);
    });
  });
}
