import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/db/app_database.dart';
import '../../../core/files/book_file_store.dart';
import '../../../core/planning/plan_math.dart';
import '../../sessions/application/sessions_providers.dart';
import '../../today/application/today_providers.dart';
import '../domain/book_progress.dart';

/// Pages read today for one plan, to credit against today's portion.
final _pagesReadTodayProvider = StreamProvider.autoDispose.family<int, String>((
  ref,
  planId,
) {
  final today = ref.watch(todayProvider);
  return ref
      .watch(appDatabaseProvider)
      .watchPagesReadOn(today)
      .map((byPlan) => byPlan[planId] ?? 0);
});

/// A plan's reading history, over the window the calendar draws.
final _dailyPagesProvider = StreamProvider.autoDispose
    .family<Map<DateTime, int>, String>((ref, planId) {
      final today = ref.watch(todayProvider);
      return ref
          .watch(appDatabaseProvider)
          .watchDailyPagesFor(
            planId,
            from: addDays(today, -(heatmapColumnCount * 7 - 1)),
          );
    });

/// How many week-columns the calendar shows. Here rather than in the widget
/// because the query has to fetch exactly the range that gets drawn.
const heatmapColumnCount = 10;

/// Measured time spent inside one book, over its whole life.
///
/// Not windowed like the calendar above: this is the reader's total with the
/// book, and a ختمة that took four months should say so rather than reporting
/// only the part of it that fits on a grid.
final _timeReadingProvider = StreamProvider.autoDispose.family<Duration, String>(
  (ref, planId) => ref
      .watch(appDatabaseProvider)
      .watchReadingPace(planId: planId)
      .map((pace) => pace.time),
);

/// Where a book stands, ready to draw.
///
/// Null while the book has no plan — there is nothing to be ahead of or behind,
/// and the screen offers to set a goal instead.
final bookProgressProvider = Provider.autoDispose
    .family<AsyncValue<BookProgress?>, ReadingPlan?>((ref, plan) {
      if (plan == null) return const AsyncValue.data(null);

      final sessions = ref.watch(planSessionsProvider(plan.id));
      final readToday = ref.watch(_pagesReadTodayProvider(plan.id));
      final timeReading = ref.watch(_timeReadingProvider(plan.id));

      // Only the session list is awaited. Today's pages and the reading time
      // arrive on their own streams, and blocking the whole screen on them
      // would blank the progress figure every time a page is logged.
      return sessions.whenData(
        (rows) => buildBookProgress(
          timeReading: timeReading.value ?? Duration.zero,
          plan: ref.watch(appDatabaseProvider).specOf(plan),
          lastPageRead: plan.lastPageRead,
          sessionCount: rows.length,
          today: ref.watch(todayProvider),
          pagesReadToday: readToday.value ?? 0,
          pausedDays: plan.pausedDays,
          pausedAt: plan.pausedAt,
        ),
      );
    });

/// The reading calendar for a plan, or an empty grid while it has none.
final bookHeatmapProvider = Provider.autoDispose
    .family<List<List<HeatCell>>, ReadingPlan?>((ref, plan) {
      final today = ref.watch(todayProvider);
      if (plan == null) {
        return heatmapColumns(
          pagesByDay: const {},
          today: today,
          pagesPerDay: 1,
          columns: heatmapColumnCount,
        );
      }

      return heatmapColumns(
        pagesByDay: ref.watch(_dailyPagesProvider(plan.id)).value ?? const {},
        today: today,
        pagesPerDay: plan.pagesPerDay,
        columns: heatmapColumnCount,
      );
    });

/// The things the detail screen can do to a book.
///
/// Thin over the database for the same reason [PlanWriter] is: the rules live
/// in `app_database.dart`, and all that is left here is supplying the clock —
/// and, for a removal, the file the database does not own.
class BookActions {
  const BookActions(this._db, this._files);

  final AppDatabase _db;
  final BookFileStore _files;

  Future<void> pause(String planId) => _db.pausePlan(planId, DateTime.now());

  Future<void> resume(String planId) => _db.resumePlan(planId, DateTime.now());

  Future<void> setStatus(String bookId, BookStatus status) =>
      _db.setBookStatus(bookId, status, DateTime.now());

  /// Removes a book, and the copy of its PDF this app made.
  ///
  /// The file goes first. If it went second, a delete that failed halfway would
  /// leave a book nobody can see holding on to a couple of hundred megabytes
  /// the reader has no way left to reclaim.
  ///
  /// Only our own copy is touched: whatever the reader originally picked the
  /// file from is theirs and is somewhere else entirely.
  Future<void> delete(String bookId) async {
    final relativePath = await _db.localFilePath(bookId);
    if (relativePath != null) await _files.delete(relativePath);

    await _db.deleteBook(bookId, DateTime.now());
  }
}

final bookActionsProvider = Provider<BookActions>((ref) {
  return BookActions(
    ref.watch(appDatabaseProvider),
    ref.watch(bookFileStoreProvider),
  );
});
