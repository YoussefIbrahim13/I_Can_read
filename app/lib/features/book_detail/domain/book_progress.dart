/// One book's standing, as pure data.
///
/// This is the only screen in the app that mentions lateness, and it says it
/// as a date: the daily portion never changes, so falling behind moves the
/// finish and nothing else. There is no "behind" percentage here and no broken
/// streak, because neither would tell the reader anything they could act on.
library;

import '../../../core/planning/plan_math.dart';

/// Everything the detail screen draws above the actions.
class BookProgress {
  const BookProgress({
    required this.pagesRead,
    required this.totalPages,
    required this.pagesPerDay,
    required this.sessionCount,
    required this.targetEndDate,
    required this.projectedEndDate,
    required this.schedule,
    required this.pausedAt,
  });

  /// Pages of the plan's range that are done, clamped to the range.
  final int pagesRead;
  final int totalPages;
  final int pagesPerDay;

  /// How many times a day the portion is split. Zero until times are set.
  final int sessionCount;

  /// What the reader originally aimed for.
  final DateTime targetEndDate;

  /// When they will actually finish at the current pace.
  final DateTime projectedEndDate;

  final ScheduleStatus schedule;

  /// When the plan was paused, or null while it is running.
  final DateTime? pausedAt;

  bool get isPaused => pausedAt != null;

  double get fraction => totalPages == 0 ? 0 : pagesRead / totalPages;

  bool get isComplete => pagesRead >= totalPages;

  /// True when the projection has slipped past the original target.
  ///
  /// Compared against the target date rather than against [schedule], because
  /// the sentence the screen writes is about dates. A reader can be a fraction
  /// of a day behind — which [ScheduleStatus] rounds away to "on track" — and
  /// still finish a day later than they meant to.
  bool get isLate => projectedEndDate.isAfter(targetEndDate);
}

/// Works out where a book stands, given its plan and its progress.
BookProgress buildBookProgress({
  required PlanSpec plan,
  required int lastPageRead,
  required int sessionCount,
  required DateTime today,
  int pagesReadToday = 0,
  int pausedDays = 0,
  DateTime? pausedAt,
}) {
  return BookProgress(
    pagesRead: plan.pagesReadFrom(lastPageRead),
    totalPages: plan.totalPages,
    pagesPerDay: plan.pagesPerDay,
    sessionCount: sessionCount,
    targetEndDate: dateOnly(plan.targetEndDate),
    // A paused plan is projected from the day it stopped, not from today.
    // Otherwise the finish date would crawl forward every morning of a pause
    // the reader deliberately took, which is the one thing a pause promises
    // will not happen.
    projectedEndDate: projectedEndDate(
      plan,
      lastPageRead: lastPageRead,
      today: pausedAt == null ? today : dateOnly(pausedAt),
      pagesReadToday: pausedAt == null ? pagesReadToday : 0,
    ),
    schedule: scheduleStatus(
      plan,
      lastPageRead: lastPageRead,
      today: today,
      pausedDays: pausedDays + _daysInsideCurrentPause(pausedAt, today),
    ),
    pausedAt: pausedAt,
  );
}

/// Days spent inside a pause that has not ended yet.
///
/// [ReadingPlans.pausedDays] only banks a pause on resume, so without this the
/// gap would grow all through a pause and the reader would come back to a debt
/// the pause was supposed to prevent.
int _daysInsideCurrentPause(DateTime? pausedAt, DateTime today) {
  if (pausedAt == null) return 0;
  final elapsed = daysBetween(pausedAt, today);
  return elapsed < 0 ? 0 : elapsed;
}

/// One day in the reading calendar.
class HeatCell {
  const HeatCell({required this.date, required this.pages, required this.goal});

  final DateTime date;

  /// Pages read on this day.
  final int pages;

  /// The daily portion this day was measured against.
  final int goal;

  bool get isEmpty => pages <= 0;

  /// How full the day was, 0 to 1. A day that overshoots caps at full: reading
  /// three days' worth in one sitting is one dark square, not a brighter one
  /// than the square next to it.
  double get intensity {
    if (pages <= 0 || goal <= 0) return 0;
    final filled = pages / goal;
    return filled > 1 ? 1 : filled;
  }
}

/// The reading calendar, laid out as columns of seven days.
///
/// Column-major and ending on [today], so the newest day is the bottom of the
/// last column and the grid never shows a future square. Rows are not weekdays:
/// the design draws no weekday labels, and pinning the rows to a weekday would
/// mean padding the first column with blanks that mean nothing.
List<List<HeatCell>> heatmapColumns({
  required Map<DateTime, int> pagesByDay,
  required DateTime today,
  required int pagesPerDay,
  int columns = 10,
}) {
  const rows = 7;
  final end = dateOnly(today);
  final first = addDays(end, -(columns * rows - 1));

  return [
    for (var column = 0; column < columns; column++)
      [
        for (var row = 0; row < rows; row++)
          () {
            final date = addDays(first, column * rows + row);
            return HeatCell(
              date: date,
              pages: pagesByDay[date] ?? 0,
              goal: pagesPerDay,
            );
          }(),
      ],
  ];
}
