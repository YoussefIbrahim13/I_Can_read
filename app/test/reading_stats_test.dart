import 'package:flutter_test/flutter_test.dart';
import 'package:i_can_read/features/stats/domain/reading_stats.dart';

DateTime _jan(int day) => DateTime(2026, 1, day);

/// The window ends here in every case below, so day 30 is "today".
final _today = _jan(30);

ReadingStats _stats(
  Map<int, int> pagesByDayOfJanuary, {
  List<FinishedBookRecord> finished = const [],
}) {
  return buildReadingStats(
    pagesByDay: {
      for (final entry in pagesByDayOfJanuary.entries)
        _jan(entry.key): entry.value,
    },
    today: _today,
    finished: finished,
  );
}

void main() {
  group('the window', () {
    test('is thirty days ending on today', () {
      final stats = _stats(const {});

      expect(stats.days, hasLength(30));
      expect(stats.days.last.date, _today);
      expect(stats.days.first.date, _jan(1));
    });

    test('never shows a day that has not happened yet', () {
      expect(_stats(const {}).days.last.date.isAfter(_today), isFalse);
    });

    test('a day with no reading is empty rather than missing', () {
      final stats = _stats(const {30: 12});

      expect(stats.days.last.pages, 12);
      expect(stats.days.last.isEmpty, isFalse);
      expect(stats.days.first.isEmpty, isTrue);
    });

    test('nothing read and nothing finished is empty', () {
      expect(_stats(const {}).isEmpty, isTrue);
      expect(_stats(const {30: 1}).isEmpty, isFalse);
    });

    test('the busiest day is what the bars are drawn against', () {
      expect(_stats(const {28: 5, 29: 40, 30: 12}).busiestDay, 40);
      // Never zero: an empty window would otherwise divide by it.
      expect(_stats(const {}).busiestDay, 1);
    });
  });

  group('streak', () {
    test('counts consecutive days back from today', () {
      expect(_stats(const {28: 5, 29: 5, 30: 5}).streakDays, 3);
    });

    test('stops at the first missed day', () {
      // The 27th is missed, so the run of the 28th–30th is all that counts.
      expect(_stats(const {25: 5, 26: 5, 28: 5, 29: 5, 30: 5}).streakDays, 3);
    });

    test('an unread today does not break yesterday\'s streak', () {
      // The reader has not read yet today. It is not a missed day until the
      // day is over, so the streak still stands at three.
      expect(_stats(const {27: 5, 28: 5, 29: 5}).streakDays, 3);
    });

    test('a second unread day does break it', () {
      expect(_stats(const {26: 5, 27: 5, 28: 5}).streakDays, 0);
    });

    test('is zero when nothing has ever been read', () {
      expect(_stats(const {}).streakDays, 0);
    });
  });

  group('average pages a day', () {
    test('counts from the first day read, not from the window edge', () {
      // Forty pages over the last two days. Divided by the whole window that
      // would read as 3 a day, which is not the pace the reader is keeping.
      expect(_stats(const {29: 20, 30: 20}).averagePagesPerDay, 20);
    });

    test('counts the missed days inside a run', () {
      // The 29th is missed, so it is 60 pages over three days, not over two.
      expect(_stats(const {28: 30, 30: 30}).averagePagesPerDay, 20);
    });

    test('runs to today, so going quiet lowers the pace', () {
      // Thirty pages at the start of the month and nothing since. Averaged to
      // the last day read that would boast 15 a day; averaged to today it is
      // the one page a day the reader has actually been keeping up.
      expect(_stats(const {1: 15, 2: 15}).averagePagesPerDay, 1);
    });

    test('is zero when nothing has been read', () {
      expect(_stats(const {}).averagePagesPerDay, 0);
    });
  });

  group('finished books', () {
    FinishedBookRecord record(
      String id,
      String title, {
      required int start,
      int? lastRead,
    }) {
      return FinishedBookRecord(
        bookId: id,
        title: title,
        startDate: _jan(start),
        lastReadDate: lastRead == null ? null : _jan(lastRead),
      );
    }

    test('measures the span inclusively, so a one-day book took a day', () {
      final stats = _stats(
        const {},
        finished: [record('b1', 'A', start: 5, lastRead: 5)],
      );

      expect(stats.finished.single.days, 1);
    });

    test('measures from the plan start to the last day read', () {
      final stats = _stats(
        const {},
        finished: [record('b1', 'A', start: 1, lastRead: 20)],
      );

      expect(stats.finished.single.days, 20);
    });

    test('lists the most recently finished first', () {
      final stats = _stats(
        const {},
        finished: [
          record('b1', 'Older', start: 1, lastRead: 10),
          record('b2', 'Newest', start: 5, lastRead: 28),
          record('b3', 'Middle', start: 3, lastRead: 15),
        ],
      );

      expect(stats.finished.map((b) => b.title), ['Newest', 'Middle', 'Older']);
    });

    test('a book finished without a page ever logged is left out', () {
      // It has no span to report, and inventing one would be a number the
      // reader never earned.
      final stats = _stats(
        const {},
        finished: [
          record('b1', 'Never read', start: 1),
          record('b2', 'Read', start: 1, lastRead: 9),
        ],
      );

      expect(stats.finished.map((b) => b.title), ['Read']);
      expect(stats.finishedCount, 1);
    });

    test('a finished book alone is enough to have something to show', () {
      final stats = _stats(
        const {},
        finished: [record('b1', 'A', start: 1, lastRead: 9)],
      );

      expect(stats.isEmpty, isFalse);
    });
  });
}
