/// Pure reading-plan arithmetic: no Flutter, no I/O, no database.
///
/// Every page number here is an **absolute physical page index** (1-based) into
/// the PDF. The printed page number a reader sees may differ; that offset is a
/// display concern handled elsewhere.
///
/// Dates are treated as calendar days. Never subtract two local `DateTime`s
/// directly to count days — a DST transition makes a day 23 or 25 hours long
/// and `Duration.inDays` then truncates to the wrong answer. Use [daysBetween].
library;

/// How the user expressed their goal when creating the plan.
enum PlanMode {
  /// "I want to finish it by this date."
  byDeadline,

  /// "I want to read this many pages a day."
  byPagesPerDay,
}

/// Strips the time component, keeping the calendar day in local time.
DateTime dateOnly(DateTime moment) =>
    DateTime(moment.year, moment.month, moment.day);

/// Whole calendar days from [from] to [to]. Negative when [to] precedes [from].
///
/// Normalises through UTC so DST transitions cannot skew the count.
int daysBetween(DateTime from, DateTime to) {
  final start = DateTime.utc(from.year, from.month, from.day);
  final end = DateTime.utc(to.year, to.month, to.day);
  return end.difference(start).inDays;
}

/// Days in the inclusive range [from]..[to]. A single-day range returns 1.
int inclusiveDayCount(DateTime from, DateTime to) => daysBetween(from, to) + 1;

/// [days] calendar days after [from], correct across DST.
DateTime addDays(DateTime from, int days) =>
    DateTime(from.year, from.month, from.day + days);

/// A reading plan, fully resolved. Both constructors produce a plan that holds
/// a concrete [pagesPerDay]; the daily quota never changes afterwards.
class PlanSpec {
  PlanSpec({
    required this.mode,
    required this.startPage,
    required this.endPage,
    required DateTime startDate,
    required DateTime targetEndDate,
    required this.pagesPerDay,
  }) : startDate = dateOnly(startDate),
       targetEndDate = dateOnly(targetEndDate) {
    if (startPage < 1) {
      throw ArgumentError.value(startPage, 'startPage', 'must be at least 1');
    }
    if (endPage < startPage) {
      throw ArgumentError.value(
        endPage,
        'endPage',
        'must not be before startPage ($startPage)',
      );
    }
    if (pagesPerDay < 1) {
      throw ArgumentError.value(
        pagesPerDay,
        'pagesPerDay',
        'must be at least 1',
      );
    }
  }

  /// Derives a plan from a target finish date.
  ///
  /// The resulting [pagesPerDay] is rounded up, so the reader may finish a day
  /// or two early — never late.
  factory PlanSpec.fromDeadline({
    required int startPage,
    required int endPage,
    required DateTime startDate,
    required DateTime targetEndDate,
  }) {
    final days = inclusiveDayCount(startDate, targetEndDate);
    if (days < 1) {
      throw ArgumentError.value(
        targetEndDate,
        'targetEndDate',
        'must not be before startDate',
      );
    }
    final total = endPage - startPage + 1;
    return PlanSpec(
      mode: PlanMode.byDeadline,
      startPage: startPage,
      endPage: endPage,
      startDate: startDate,
      targetEndDate: targetEndDate,
      pagesPerDay: _ceilDiv(total, days),
    );
  }

  /// Derives a plan from a daily quota, computing the finish date.
  factory PlanSpec.fromPagesPerDay({
    required int startPage,
    required int endPage,
    required DateTime startDate,
    required int pagesPerDay,
  }) {
    if (pagesPerDay < 1) {
      throw ArgumentError.value(
        pagesPerDay,
        'pagesPerDay',
        'must be at least 1',
      );
    }
    final total = endPage - startPage + 1;
    final days = _ceilDiv(total, pagesPerDay);
    return PlanSpec(
      mode: PlanMode.byPagesPerDay,
      startPage: startPage,
      endPage: endPage,
      startDate: startDate,
      targetEndDate: addDays(startDate, days - 1),
      pagesPerDay: pagesPerDay,
    );
  }

  final PlanMode mode;

  /// Inclusive, 1-based physical page index the plan begins at.
  final int startPage;

  /// Inclusive, 1-based physical page index the plan ends at.
  final int endPage;

  final DateTime startDate;

  /// What the user aimed for. The *actual* finish date moves with real
  /// progress — see [projectedEndDate].
  final DateTime targetEndDate;

  /// Fixed daily quota. Missing days extends the finish date rather than
  /// inflating this number.
  final int pagesPerDay;

  int get totalPages => endPage - startPage + 1;

  /// Pages covered given the last page the reader completed.
  ///
  /// A [lastPageRead] before [startPage] (including 0, meaning "not started")
  /// counts as no progress.
  int pagesReadFrom(int lastPageRead) {
    if (lastPageRead < startPage) return 0;
    final capped = lastPageRead > endPage ? endPage : lastPageRead;
    return capped - startPage + 1;
  }

  int remainingPagesFrom(int lastPageRead) =>
      totalPages - pagesReadFrom(lastPageRead);

  bool isComplete(int lastPageRead) => remainingPagesFrom(lastPageRead) == 0;
}

/// The stretch of pages to read in one day.
class DayAssignment {
  const DayAssignment({required this.fromPage, required this.toPage});

  /// Inclusive.
  final int fromPage;

  /// Inclusive.
  final int toPage;

  int get pageCount => toPage - fromPage + 1;

  @override
  bool operator ==(Object other) =>
      other is DayAssignment &&
      other.fromPage == fromPage &&
      other.toPage == toPage;

  @override
  int get hashCode => Object.hash(fromPage, toPage);

  @override
  String toString() => 'DayAssignment($fromPage-$toPage)';
}

/// The next unread stretch of [PlanSpec.pagesPerDay] pages, or `null` when the
/// plan is finished.
///
/// This is deliberately independent of the calendar: whatever the reader has
/// not read yet is what comes next. That is what makes a missed day slide the
/// schedule instead of piling up a double portion.
DayAssignment? nextAssignment(PlanSpec plan, int lastPageRead) {
  final from = lastPageRead < plan.startPage
      ? plan.startPage
      : lastPageRead + 1;
  if (from > plan.endPage) return null;
  final to = from + plan.pagesPerDay - 1;
  return DayAssignment(
    fromPage: from,
    toPage: to > plan.endPage ? plan.endPage : to,
  );
}

/// Splits a day's quota across sessions, largest share first.
///
/// [weights] lets a reader bias their sessions (say `[2, 1]` for a long morning
/// and a short evening); omit it for an even split. Uses the largest-remainder
/// method, so the parts always sum to exactly [pages].
///
/// When there are fewer pages than sessions the trailing sessions get 0 — the
/// UI should warn rather than silently scheduling empty reminders.
List<int> splitAcrossSessions(
  int pages, {
  required int sessionCount,
  List<int>? weights,
}) {
  if (sessionCount < 1) {
    throw ArgumentError.value(
      sessionCount,
      'sessionCount',
      'must be at least 1',
    );
  }
  if (pages < 0) {
    throw ArgumentError.value(pages, 'pages', 'must not be negative');
  }
  if (weights != null && weights.length != sessionCount) {
    throw ArgumentError.value(
      weights,
      'weights',
      'must have exactly $sessionCount entries',
    );
  }

  final effective = weights ?? List<int>.filled(sessionCount, 1);
  if (effective.any((w) => w < 0)) {
    throw ArgumentError.value(weights, 'weights', 'must not be negative');
  }
  final totalWeight = effective.fold<int>(0, (sum, w) => sum + w);
  if (totalWeight == 0) {
    throw ArgumentError.value(weights, 'weights', 'must not all be zero');
  }

  // Floor each share, then hand the leftover out to the largest remainders.
  final shares = List<int>.filled(sessionCount, 0);
  final remainders = <({int index, int remainder})>[];
  var assigned = 0;
  for (var i = 0; i < sessionCount; i++) {
    final exact = pages * effective[i];
    shares[i] = exact ~/ totalWeight;
    assigned += shares[i];
    remainders.add((index: i, remainder: exact % totalWeight));
  }

  remainders.sort((a, b) {
    final byRemainder = b.remainder.compareTo(a.remainder);
    // Ties go to the earlier session, so the morning gets the spare page.
    return byRemainder != 0 ? byRemainder : a.index.compareTo(b.index);
  });

  var leftover = pages - assigned;
  for (final entry in remainders) {
    if (leftover == 0) break;
    // A zero-weight session must stay empty.
    if (effective[entry.index] == 0) continue;
    shares[entry.index]++;
    leftover--;
  }

  return shares;
}

/// When the reader will actually finish, based on real progress rather than the
/// original target.
///
/// [pagesReadToday] is credited against today's quota, so a reader who has
/// already done their portion is projected to continue tomorrow.
DateTime projectedEndDate(
  PlanSpec plan, {
  required int lastPageRead,
  required DateTime today,
  int pagesReadToday = 0,
}) {
  final remaining = plan.remainingPagesFrom(lastPageRead);
  if (remaining <= 0) return dateOnly(today);

  final usedToday = pagesReadToday < 0 ? 0 : pagesReadToday;
  final capacityLeftToday = plan.pagesPerDay - usedToday;
  if (remaining <= capacityLeftToday) return dateOnly(today);

  final afterToday = capacityLeftToday > 0
      ? remaining - capacityLeftToday
      : remaining;
  return addDays(today, _ceilDiv(afterToday, plan.pagesPerDay));
}

/// How far ahead of, or behind, the original schedule the reader is.
class ScheduleStatus {
  const ScheduleStatus({
    required this.expectedPages,
    required this.actualPages,
    required this.pagesPerDay,
  });

  /// Pages the original plan expected to be done by now.
  final int expectedPages;

  /// Pages actually read.
  final int actualPages;

  /// The plan's fixed daily quota, used to express the gap in days.
  final int pagesPerDay;

  /// Positive when ahead, negative when behind.
  int get deltaPages => actualPages - expectedPages;

  /// Whole days ahead (positive) or behind (negative). Partial days truncate
  /// toward zero, so "half a day behind" reads as on track.
  int get deltaDays => deltaPages ~/ pagesPerDay;

  bool get isOnTrack => deltaDays == 0;
  bool get isBehind => deltaDays < 0;
  bool get isAhead => deltaDays > 0;

  @override
  String toString() =>
      'ScheduleStatus(expected: $expectedPages, actual: $actualPages)';
}

/// Compares real progress against the plan's fixed daily quota.
///
/// Only *completed* days count toward the expectation: on the first day, before
/// any reading, the reader is on track rather than a day behind. Days before the
/// plan starts count as zero, and the expectation never exceeds the book.
ScheduleStatus scheduleStatus(
  PlanSpec plan, {
  required int lastPageRead,
  required DateTime today,
}) {
  final completedDays = daysBetween(plan.startDate, today);
  final expectedRaw = completedDays < 1 ? 0 : completedDays * plan.pagesPerDay;
  final expected = expectedRaw > plan.totalPages
      ? plan.totalPages
      : expectedRaw;
  return ScheduleStatus(
    expectedPages: expected,
    actualPages: plan.pagesReadFrom(lastPageRead),
    pagesPerDay: plan.pagesPerDay,
  );
}

/// Integer ceiling division. [divisor] must be positive.
int _ceilDiv(int dividend, int divisor) => (dividend + divisor - 1) ~/ divisor;
