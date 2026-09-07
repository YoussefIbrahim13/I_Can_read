import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/db/app_database.dart';
import '../../../core/planning/plan_math.dart';
import '../domain/today_agenda.dart';

/// The calendar day the screen is showing.
///
/// A provider rather than a call to `DateTime.now()` inside the builder so that
/// tests can pin the day, and so the whole screen reads one date instead of
/// several that could straddle the boundary.
///
/// The boundary is 04:00, not midnight — see [readingDay].
final todayProvider = Provider<DateTime>((ref) => readingDay(DateTime.now()));

final _todaySessionsProvider =
    StreamProvider<List<({Book book, ReadingPlan plan, ReadingSession session})>>(
      (ref) => ref.watch(appDatabaseProvider).watchLivePlanSessions(),
    );

final _pagesReadTodayProvider = StreamProvider<Map<String, int>>((ref) {
  return ref
      .watch(appDatabaseProvider)
      .watchPagesReadOn(ref.watch(todayProvider));
});

/// Today, across every book, ready to draw.
final todayAgendaProvider = Provider<AsyncValue<TodayAgenda>>((ref) {
  final sessions = ref.watch(_todaySessionsProvider);
  final readToday = ref.watch(_pagesReadTodayProvider);

  // Both queries are live, so the screen would otherwise flicker through a
  // half-built day every time either one of them ticks.
  return sessions.whenData((rows) {
    final pagesRead = readToday.value ?? const <String, int>{};
    final db = ref.watch(appDatabaseProvider);

    final byPlan =
        <String, ({ReadingPlan plan, Book book, List<ReadingSession> sessions})>{};
    for (final row in rows) {
      final entry = byPlan.putIfAbsent(
        row.plan.id,
        () => (plan: row.plan, book: row.book, sessions: <ReadingSession>[]),
      );
      entry.sessions.add(row.session);
    }

    return buildTodayAgenda([
      for (final entry in byPlan.values)
        TodayBook(
          bookId: entry.book.id,
          planId: entry.plan.id,
          title: entry.book.title,
          author: entry.book.author,
          plan: db.specOf(entry.plan),
          lastPageRead: entry.plan.lastPageRead,
          pagesReadToday: pagesRead[entry.plan.id] ?? 0,
          sessions: [
            for (final session in entry.sessions)
              (
                id: session.id,
                minutes: session.timeOfDayMinutes,
                pages: session.pagesShare,
              ),
          ],
        ),
    ]);
  });
});
