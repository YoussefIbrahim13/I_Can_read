/// One book's standing, as pure data.
///
/// This is the only screen in the app that mentions lateness, and it says it
/// as a date: the daily portion never changes, so falling behind moves the
/// finish and nothing else. There is no "behind" percentage here and no broken
/// streak, because neither would tell the reader anything they could act on.
library;

import '../../../core/planning/plan_math.dart';

// The calendar moved to core once the stats screen started drawing one too;
// exported here so the screens that already imported it keep working.
export '../../../core/planning/reading_calendar.dart';

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
    this.timeReading = Duration.zero,
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

  /// Measured time spent inside this book, across every sitting.
  ///
  /// Zero covers two different things — a book nobody has opened, and a book
  /// read entirely before the app started timing — and the screen says nothing
  /// in either case. Neither is a number worth printing.
  final Duration timeReading;

  bool get hasTimeReading => timeReading > Duration.zero;

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
  Duration timeReading = Duration.zero,
}) {
  return BookProgress(
    timeReading: timeReading,
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
