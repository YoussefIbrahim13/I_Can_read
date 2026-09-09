import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/db/app_database.dart';
import '../../../core/planning/plan_math.dart';
import '../../../core/planning/reading_calendar.dart';
import '../../today/application/today_providers.dart';
import '../domain/reading_stats.dart';

/// How many days the chart covers. Here rather than in the widget because the
/// query has to fetch exactly the range that gets drawn.
const statsWindowDays = 30;

final _dailyPagesProvider = StreamProvider<Map<DateTime, int>>((ref) {
  final today = ref.watch(todayProvider);
  return ref
      .watch(appDatabaseProvider)
      // Null plan: every book totalled together.
      .watchDailyPagesFor(null, from: addDays(today, -(statsWindowDays - 1)));
});

/// How many week-columns the library calendar shows.
///
/// Wider than the chart above it on purpose: the chart answers "how much am I
/// reading lately", and the calendar answers "how consistent have I been" —
/// a question thirty days is too short to say anything about.
const statsCalendarColumns = 15;

final _calendarPagesProvider = StreamProvider<Map<DateTime, int>>((ref) {
  final today = ref.watch(todayProvider);
  return ref
      .watch(appDatabaseProvider)
      .watchDailyPagesFor(
        null,
        from: addDays(today, -(calendarWindowDays(statsCalendarColumns) - 1)),
      );
});

final _committedPagesProvider = StreamProvider<int>(
  (ref) => ref.watch(appDatabaseProvider).watchCommittedPagesPerDay(),
);

/// The whole library's reading calendar.
///
/// The same grid the detail screen draws for one book, measured against the sum
/// of every portion the reader is committed to rather than against one plan's.
final libraryCalendarProvider = Provider<List<List<HeatCell>>>((ref) {
  final pagesByDay =
      ref.watch(_calendarPagesProvider).value ?? const <DateTime, int>{};

  return heatmapColumns(
    pagesByDay: pagesByDay,
    today: ref.watch(todayProvider),
    pagesPerDay: libraryDailyGoal(
      committedPagesPerDay: ref.watch(_committedPagesProvider).value ?? 0,
      pagesByDay: pagesByDay,
    ),
    columns: statsCalendarColumns,
  );
});

final _finishedBooksProvider =
    StreamProvider<List<({Book book, ReadingPlan plan})>>(
      (ref) => ref.watch(appDatabaseProvider).watchFinishedBooks(),
    );

final _lastReadDatesProvider = StreamProvider<Map<String, DateTime>>(
  (ref) => ref.watch(appDatabaseProvider).watchLastReadDates(),
);

/// The stats screen, ready to draw.
final readingStatsProvider = Provider<AsyncValue<ReadingStats>>((ref) {
  final pages = ref.watch(_dailyPagesProvider);
  final finished = ref.watch(_finishedBooksProvider);
  final lastRead = ref.watch(_lastReadDatesProvider);

  // Only the chart is awaited. The finished list arrives on its own streams,
  // and blocking the screen on them would blank the three figures every time
  // a page is logged.
  return pages.whenData((pagesByDay) {
    final lastReadDates = lastRead.value ?? const <String, DateTime>{};
    final books = finished.value ?? const <({Book book, ReadingPlan plan})>[];

    return buildReadingStats(
      pagesByDay: pagesByDay,
      today: ref.watch(todayProvider),
      windowDays: statsWindowDays,
      finished: [
        for (final row in books)
          FinishedBookRecord(
            bookId: row.book.id,
            title: row.book.title,
            startDate: row.plan.startDate,
            lastReadDate: lastReadDates[row.plan.id],
          ),
      ],
    );
  });
});
