import 'package:flutter_test/flutter_test.dart';
import 'package:i_can_read/features/sessions/domain/session_plan.dart';

/// The invariant every test here is really checking.
void expectBalanced(SessionPlan plan) {
  expect(
    plan.assignedPages,
    plan.pagesPerDay,
    reason: 'sessions must always add up to the daily portion',
  );
  expect(plan.isBalanced, isTrue);
}

List<int> pagesOf(SessionPlan plan) => [
  for (final slot in plan.slots) slot.pages,
];

List<int> timesOf(SessionPlan plan) => [
  for (final slot in plan.slots) slot.minutes,
];

void main() {
  group('a new plan', () {
    test('starts as one evening session holding the whole portion', () {
      final plan = SessionPlan.single(15);

      expect(plan.slots, hasLength(1));
      expect(plan.slots.single.minutes, 20 * 60);
      expect(plan.slots.single.pages, 15);
      expectBalanced(plan);
    });

    test('a lone session cannot be removed or re-shared', () {
      final plan = SessionPlan.single(15);

      expect(plan.canRemove, isFalse);
      expect(plan.removedAt(0).slots, hasLength(1));
      // Nothing to trade with: the one session is the whole day.
      expect(plan.withPagesAt(0, 3).slots.single.pages, 15);
    });
  });

  group('adding and removing', () {
    test('adding re-splits the day evenly, morning first', () {
      final plan = SessionPlan.single(15).added(minutes: 8 * 60);

      expect(timesOf(plan), [8 * 60, 20 * 60]);
      // The spare page goes to the earlier session.
      expect(pagesOf(plan), [8, 7]);
      expectBalanced(plan);
    });

    test('sessions stay in time order however they were added', () {
      final plan = SessionPlan.single(
        12,
        minutes: 21 * 60,
      ).added(minutes: 7 * 60).added(minutes: 13 * 60);

      expect(timesOf(plan), [7 * 60, 13 * 60, 21 * 60]);
      expect(pagesOf(plan), [4, 4, 4]);
    });

    test('removing gives the freed pages back to the rest', () {
      final plan = SessionPlan.single(15).added(minutes: 8 * 60).removedAt(0);

      expect(plan.slots, hasLength(1));
      expect(pagesOf(plan), [15]);
      expectBalanced(plan);
    });

    test('stops at the soft cap rather than scheduling nine reminders', () {
      var plan = SessionPlan.single(60);
      for (var i = 0; i < 20; i++) {
        plan = plan.added(minutes: 6 * 60 + i * 30);
      }

      expect(plan.slots, hasLength(SessionPlan.maxSessions));
      expect(plan.canAdd, isFalse);
      expectBalanced(plan);
    });
  });

  group('re-sharing', () {
    test('pages taken by one session come out of the last one', () {
      final plan = SessionPlan.single(
        15,
      ).added(minutes: 8 * 60).withPagesAt(0, 11);

      expect(pagesOf(plan), [11, 4]);
      expectBalanced(plan);
    });

    test('pages given back go to the last session too', () {
      final plan = SessionPlan.single(
        15,
      ).added(minutes: 8 * 60).withPagesAt(0, 2);

      expect(pagesOf(plan), [2, 13]);
      expectBalanced(plan);
    });

    test('drains later sessions in turn when one takes everything', () {
      final plan = SessionPlan.single(
        15,
      ).added(minutes: 8 * 60).added(minutes: 12 * 60).withPagesAt(0, 15);

      expect(pagesOf(plan), [15, 0, 0]);
      expectBalanced(plan);
    });

    test('cannot be pushed past the daily portion', () {
      final plan = SessionPlan.single(
        15,
      ).added(minutes: 8 * 60).withPagesAt(0, 99);

      expect(pagesOf(plan), [15, 0]);
      expectBalanced(plan);
    });

    test('cannot go below zero', () {
      final plan = SessionPlan.single(
        15,
      ).added(minutes: 8 * 60).withPagesAt(0, -4);

      expect(pagesOf(plan), [0, 15]);
      expectBalanced(plan);
    });
  });

  group('more sessions than pages', () {
    test('leaves the trailing sessions empty and says so', () {
      var plan = SessionPlan.single(2);
      plan = plan.added(minutes: 8 * 60).added(minutes: 12 * 60);

      expect(pagesOf(plan), [1, 1, 0]);
      expect(plan.hasEmptySession, isTrue);
      expectBalanced(plan);
    });
  });

  group('moving a session', () {
    test('re-sorts the day and keeps each share with its time', () {
      final plan = SessionPlan.single(
        15,
      ).added(minutes: 8 * 60).withTimeAt(0, 22 * 60);

      // The 8-page morning session became the 22:00 one, so it sorts last.
      expect(timesOf(plan), [20 * 60, 22 * 60]);
      expect(pagesOf(plan), [7, 8]);
      expectBalanced(plan);
    });

    test('clamps to a real time of day', () {
      final plan = SessionPlan.single(15).withTimeAt(0, 99 * 60);
      expect(plan.slots.single.minutes, 24 * 60 - 1);
    });
  });

  group('restoring stored sessions', () {
    test('keeps a hand-tuned split that still adds up', () {
      final plan = SessionPlan.restore(
        pagesPerDay: 15,
        slots: const [
          SessionSlot(minutes: 20 * 60, pages: 7),
          SessionSlot(minutes: 8 * 60, pages: 8),
        ],
      );

      expect(timesOf(plan), [8 * 60, 20 * 60]);
      expect(pagesOf(plan), [8, 7]);
    });

    test('re-splits when the plan\'s daily portion has since changed', () {
      // The reader edited the goal from 15 pages a day to 10; the old split
      // would now read 15 pages a day whatever the plan says.
      final plan = SessionPlan.restore(
        pagesPerDay: 10,
        slots: const [
          SessionSlot(minutes: 8 * 60, pages: 8),
          SessionSlot(minutes: 20 * 60, pages: 7),
        ],
      );

      expect(pagesOf(plan), [5, 5]);
      expectBalanced(plan);
    });

    test('a plan with no sessions yet gets the default one', () {
      final plan = SessionPlan.restore(pagesPerDay: 15, slots: const []);

      expect(plan.slots, hasLength(1));
      expect(plan.slots.single.pages, 15);
    });
  });

  group('period of day', () {
    test('names the part of the day a time falls in', () {
      SessionPeriod at(int hour) =>
          SessionSlot(minutes: hour * 60, pages: 1).period;

      expect(at(8), SessionPeriod.morning);
      expect(at(14), SessionPeriod.afternoon);
      expect(at(19), SessionPeriod.evening);
      expect(at(23), SessionPeriod.night);
      expect(at(3), SessionPeriod.night);
      // Boundaries, which is where an off-by-one would hide.
      expect(at(5), SessionPeriod.morning);
      expect(at(12), SessionPeriod.afternoon);
      expect(at(17), SessionPeriod.evening);
      expect(at(21), SessionPeriod.night);
    });
  });
}
