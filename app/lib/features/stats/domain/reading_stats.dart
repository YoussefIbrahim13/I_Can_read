/// What the reader has actually done, as pure data.
///
/// Three numbers, a shape, and a list — and none of them is a score. The app
/// has one rule about lateness (it moves a date, it does not punish), and this
/// screen keeps it: there is no "days missed", no completion percentage, and
/// no target to fall short of. Everything here is something the reader did.
library;

import '../../../core/planning/plan_math.dart';

/// One day in the pages-a-day chart.
class StatsDay {
  const StatsDay({required this.date, required this.pages});

  final DateTime date;
  final int pages;

  bool get isEmpty => pages <= 0;
}

/// A book the reader saw through to the end.
class FinishedBook {
  const FinishedBook({
    required this.bookId,
    required this.title,
    required this.days,
  });

  final String bookId;
  final String title;

  /// Calendar days from the plan's start to the last day read, inclusive.
  final int days;
}

/// A finished book before its span has been worked out.
class FinishedBookRecord {
  const FinishedBookRecord({
    required this.bookId,
    required this.title,
    required this.startDate,
    required this.lastReadDate,
  });

  final String bookId;
  final String title;
  final DateTime startDate;

  /// Null when the book was marked finished without a page ever being logged.
  final DateTime? lastReadDate;
}

/// The whole stats screen, ready to draw.
class ReadingStats {
  const ReadingStats({
    required this.streakDays,
    required this.averagePagesPerDay,
    required this.days,
    required this.finished,
  });

  /// Consecutive days read, counting back from today.
  final int streakDays;

  /// Pages a day since the reader started, over the window.
  final int averagePagesPerDay;

  /// The window, oldest day first.
  final List<StatsDay> days;

  /// Finished books, longest-ago start first is not useful — newest first.
  final List<FinishedBook> finished;

  int get finishedCount => finished.length;

  /// The most pages read on any one day in the window, which is what the bars
  /// are drawn against. One, not zero, so an empty window cannot divide by it.
  int get busiestDay =>
      days.fold(1, (best, day) => day.pages > best ? day.pages : best);

  /// True when there is nothing worth drawing yet.
  bool get isEmpty => days.every((day) => day.isEmpty) && finished.isEmpty;
}

/// Builds the stats screen from the reading log.
///
/// [windowDays] is the width of the chart, counting back from and including
/// [today].
ReadingStats buildReadingStats({
  required Map<DateTime, int> pagesByDay,
  required DateTime today,
  List<FinishedBookRecord> finished = const [],
  int windowDays = 30,
}) {
  final end = dateOnly(today);
  final start = addDays(end, -(windowDays - 1));

  final days = [
    for (var offset = 0; offset < windowDays; offset++)
      () {
        final date = addDays(start, offset);
        return StatsDay(date: date, pages: pagesByDay[date] ?? 0);
      }(),
  ];

  return ReadingStats(
    streakDays: _streak(pagesByDay, end),
    averagePagesPerDay: _average(days),
    days: days,
    finished: _finished(finished),
  );
}

/// Consecutive days read, counting back from [today].
///
/// A day that has not finished yet cannot break a streak: if nothing has been
/// read today, the count starts at yesterday and today is simply not in it.
/// Otherwise every streak in the app would die at midnight and only come back
/// once the reader had done their portion, which reports a loss for the hours
/// they were still perfectly on time.
int _streak(Map<DateTime, int> pagesByDay, DateTime today) {
  var day = (pagesByDay[today] ?? 0) > 0 ? today : addDays(today, -1);
  var streak = 0;

  while ((pagesByDay[day] ?? 0) > 0) {
    streak++;
    day = addDays(day, -1);
  }
  return streak;
}

/// Pages a day, averaged from the reader's first day in the window.
///
/// Not divided by the window: someone three days into their first book would
/// have their pace divided by thirty and be told they read four pages a day
/// when they read forty. The average starts when they did.
int _average(List<StatsDay> days) {
  final firstRead = days.indexWhere((day) => !day.isEmpty);
  if (firstRead < 0) return 0;

  final counted = days.sublist(firstRead);
  final total = counted.fold<int>(0, (sum, day) => sum + day.pages);
  return (total / counted.length).round();
}

/// Finished books, most recently finished first.
List<FinishedBook> _finished(List<FinishedBookRecord> records) {
  final dated = [
    for (final record in records)
      if (record.lastReadDate case final last?) (record: record, last: last),
  ];
  dated.sort((a, b) => b.last.compareTo(a.last));

  return [
    for (final entry in dated)
      FinishedBook(
        bookId: entry.record.bookId,
        title: entry.record.title,
        // Inclusive: a book started and finished on one day took a day, not
        // zero days.
        days: inclusiveDayCount(entry.record.startDate, entry.last),
      ),
  ];
}
