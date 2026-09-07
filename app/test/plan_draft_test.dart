import 'package:flutter_test/flutter_test.dart';
import 'package:i_can_read/core/planning/plan_math.dart';
import 'package:i_can_read/features/plan/domain/plan_draft.dart';

/// A fixed "today" well away from any DST boundary, so a failure here is a
/// failure in the draft rather than in the calendar.
final _today = DateTime(2026, 10, 12);

PlanDraft _draft({int pageCount = 240}) =>
    PlanDraft.forBook(pageCount: pageCount, today: _today);

void main() {
  group('a fresh draft', () {
    test('opens on the whole book, finishing in a month', () {
      final draft = _draft();

      expect(draft.mode, PlanMode.byDeadline);
      expect(draft.startPage, 1);
      expect(draft.startDate, _today);
      expect(draft.targetEndDate, DateTime(2026, 11, 10));
      expect(draft.spec!.pagesPerDay, 8); // 240 over 30 days
    });

    test('is valid, so the reader can accept the default and move on', () {
      expect(_draft().isValid, isTrue);
      expect(_draft().problem, isNull);
    });

    test('handles a one-page book without dividing by zero', () {
      final draft = _draft(pageCount: 1);

      expect(draft.isValid, isTrue);
      expect(draft.spec!.pagesPerDay, 1);
      expect(draft.totalPages, 1);
    });
  });

  group('switching mode', () {
    test('carries the deadline across as its daily quota', () {
      final draft = _draft().withMode(PlanMode.byPagesPerDay);

      // The 30-day deadline meant 8 pages a day, so that is where the other
      // mode starts — the toggle must not look like it discarded the answer.
      expect(draft.pagesPerDay, 8);
      expect(draft.spec!.pagesPerDay, 8);
    });

    test('carries a daily quota back as the date it reaches', () {
      final draft = _draft()
          .withMode(PlanMode.byPagesPerDay)
          .withPagesPerDay(10)
          .withMode(PlanMode.byDeadline);

      // 240 pages at 10 a day is 24 days, counting today.
      expect(draft.targetEndDate, DateTime(2026, 11, 4));
      expect(draft.spec!.pagesPerDay, 10);
    });

    test('is a no-op when the mode is already the current one', () {
      final draft = _draft();
      expect(identical(draft.withMode(PlanMode.byDeadline), draft), isTrue);
    });
  });

  group('start page', () {
    test('clamps to the book at both ends', () {
      expect(_draft().withStartPage(0).startPage, 1);
      expect(_draft().withStartPage(999).startPage, 240);
    });

    test('shortens the plan without moving the end of the book', () {
      final draft = _draft().withStartPage(9);

      expect(draft.totalPages, 232);
      expect(draft.spec!.startPage, 9);
      expect(draft.spec!.endPage, 240);
    });

    test('pulls an oversized daily quota down with it', () {
      // 100 pages a day was fine over the whole book; starting at page 200
      // leaves only 41, and a quota larger than the plan is nonsense.
      final draft = _draft()
          .withMode(PlanMode.byPagesPerDay)
          .withPagesPerDay(100)
          .withStartPage(200);

      expect(draft.pagesPerDay, 41);
    });
  });

  group('daily quota', () {
    test('never drops below one page', () {
      final draft = _draft()
          .withMode(PlanMode.byPagesPerDay)
          .withPagesPerDay(0);

      expect(draft.pagesPerDay, 1);
      expect(draft.isValid, isTrue);
    });

    test('is capped at finishing in a single day', () {
      final draft = _draft()
          .withMode(PlanMode.byPagesPerDay)
          .withPagesPerDay(5000);

      expect(draft.pagesPerDay, 240);
      expect(draft.spec!.targetEndDate, _today);
    });
  });

  group('target date', () {
    test('cannot be pulled before the day the plan starts', () {
      final draft = _draft().withTargetEndDate(DateTime(2026, 9, 1));

      expect(draft.targetEndDate, _today);
      expect(draft.isValid, isTrue);
      // A same-day deadline is the whole book today, not an error.
      expect(draft.spec!.pagesPerDay, 240);
    });

    test('drops the time component, so two dates on one day are equal', () {
      final draft = _draft().withTargetEndDate(
        DateTime(2026, 11, 3, 23, 59, 59),
      );

      expect(draft.targetEndDate, DateTime(2026, 11, 3));
    });

    test('presets set an inclusive day count and report as selected', () {
      final draft = _draft().withDayCount(60);

      expect(inclusiveDayCount(draft.startDate, draft.targetEndDate), 60);
      expect(draft.matchesDayCount(60), isTrue);
      expect(draft.matchesDayCount(30), isFalse);
    });
  });

  group('problems', () {
    test('a start page past the book has no spec', () {
      final draft = PlanDraft(
        pageCount: 10,
        mode: PlanMode.byDeadline,
        startPage: 11,
        startDate: _today,
        targetEndDate: DateTime(2026, 10, 20),
        pagesPerDay: 1,
      );

      expect(draft.problem, PlanDraftProblem.startPageOutOfRange);
      expect(draft.spec, isNull);
    });

    test('a stale value in the mode not in use does not block the plan', () {
      // Deadline mode is asked about its date, never about a quota it is not
      // using — otherwise a carried-over 0 would freeze a perfectly good plan.
      final draft = _draft().copyWith(pagesPerDay: 0);

      expect(draft.mode, PlanMode.byDeadline);
      expect(draft.isValid, isTrue);
    });

    test('a deadline before the start date is reported, not thrown', () {
      final draft = _draft().copyWith(
        targetEndDate: DateTime(2026, 10, 11),
      );

      expect(draft.problem, PlanDraftProblem.targetDateBeforeStart);
      expect(draft.spec, isNull);
    });
  });

  test('reopening a saved plan restores it exactly', () {
    final spec = PlanSpec.fromPagesPerDay(
      startPage: 9,
      endPage: 240,
      startDate: DateTime(2026, 9, 1),
      pagesPerDay: 12,
    );

    final draft = PlanDraft.fromSpec(spec, pageCount: 240);

    expect(draft.mode, PlanMode.byPagesPerDay);
    expect(draft.startPage, 9);
    // The original start date survives: a plan that began in September is
    // still a September plan after an edit.
    expect(draft.startDate, DateTime(2026, 9, 1));
    expect(draft.pagesPerDay, 12);
    expect(draft.spec!.targetEndDate, spec.targetEndDate);
  });
}
