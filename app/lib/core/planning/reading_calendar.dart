/// The reading calendar, as pure data.
///
/// Lives in `core` rather than with one screen because two screens draw it: a
/// book's own last ten weeks on the detail screen, and the whole library's on
/// the stats screen. The only difference between them is what a full day is
/// measured against.
library;

import 'plan_math.dart';

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

/// How many days the calendar covers, given a column count.
int calendarWindowDays(int columns) => columns * 7;

/// What a full day means for a grid that spans the whole library.
///
/// The sum of the daily portions the reader is actually committed to, which is
/// the honest answer: a full square is a day they did everything they set out
/// to do, across every book.
///
/// With nothing committed — everything finished, or every plan paused — there
/// is no portion to measure against, so the busiest day in the window stands in
/// for it. Otherwise a reader with no live plan would see a grid of empty
/// squares on days they demonstrably read.
int libraryDailyGoal({
  required int committedPagesPerDay,
  required Map<DateTime, int> pagesByDay,
}) {
  if (committedPagesPerDay > 0) return committedPagesPerDay;

  var busiest = 0;
  for (final pages in pagesByDay.values) {
    if (pages > busiest) busiest = pages;
  }
  return busiest;
}
