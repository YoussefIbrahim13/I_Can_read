import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:i_can_read/core/db/app_database.dart';
import 'package:i_can_read/core/planning/plan_math.dart';
import 'package:i_can_read/core/planning/reading_calendar.dart';
import 'package:i_can_read/core/theme/app_theme.dart';
import 'package:i_can_read/core/widgets/reading_calendar_grid.dart';
import 'package:i_can_read/features/stats/application/stats_providers.dart';
import 'package:i_can_read/features/stats/presentation/stats_screen.dart';
import 'package:i_can_read/features/today/application/today_providers.dart';
import 'package:i_can_read/l10n/app_localizations.dart';

final _jan1 = DateTime(2026, 1, 1);
final _today = DateTime(2026, 1, 20);

void main() {
  group('libraryDailyGoal', () {
    test('is what the reader is committed to across every book', () {
      expect(
        libraryDailyGoal(committedPagesPerDay: 25, pagesByDay: const {}),
        25,
      );
    });

    test('falls back to the busiest day when nothing is committed', () {
      // Everything finished or paused. Measuring against zero would draw a grid
      // of empty squares on days the reader demonstrably read.
      expect(
        libraryDailyGoal(
          committedPagesPerDay: 0,
          pagesByDay: {_jan1: 12, addDays(_jan1, 1): 40},
        ),
        40,
      );
    });

    test('is zero when there is nothing at all to measure', () {
      expect(
        libraryDailyGoal(committedPagesPerDay: 0, pagesByDay: const {}),
        0,
      );
    });
  });

  group('the committed portion', () {
    late AppDatabase db;

    setUp(() => db = AppDatabase(NativeDatabase.memory()));
    tearDown(() => db.close());

    Future<void> addPlan({
      required String id,
      required int pagesPerDay,
      BookStatus status = BookStatus.reading,
      DateTime? pausedAt,
      DateTime? bookDeletedAt,
      bool isActive = true,
    }) async {
      await db
          .into(db.books)
          .insert(
            BooksCompanion.insert(
              id: 'book-$id',
              title: 'Book $id',
              pageCount: 300,
              status: Value(status),
              deletedAt: Value(bookDeletedAt),
              createdAt: _jan1,
              updatedAt: _jan1,
            ),
          );
      await db
          .into(db.readingPlans)
          .insert(
            ReadingPlansCompanion.insert(
              id: 'plan-$id',
              bookId: 'book-$id',
              mode: PlanMode.byPagesPerDay,
              startPage: 1,
              endPage: 300,
              startDate: _jan1,
              targetEndDate: DateTime(2026, 2, 1),
              pagesPerDay: pagesPerDay,
              isActive: Value(isActive),
              pausedAt: Value(pausedAt),
              createdAt: _jan1,
              updatedAt: _jan1,
            ),
          );
    }

    test('adds up every live plan', () async {
      await addPlan(id: 'a', pagesPerDay: 10);
      await addPlan(id: 'b', pagesPerDay: 15);

      expect(await db.watchCommittedPagesPerDay().first, 25);
    });

    test('ignores what owes nothing today', () async {
      await addPlan(id: 'a', pagesPerDay: 10);
      await addPlan(id: 'paused', pagesPerDay: 100, pausedAt: _jan1);
      await addPlan(id: 'done', pagesPerDay: 100, status: BookStatus.finished);
      await addPlan(id: 'gone', pagesPerDay: 100, bookDeletedAt: _jan1);

      // A finished book, a paused plan and a removed book promise nothing, and
      // counting them would make every day look like a shortfall against a
      // promise the reader never made.
      expect(await db.watchCommittedPagesPerDay().first, 10);
    });

    test('is zero with an empty library', () async {
      expect(await db.watchCommittedPagesPerDay().first, 0);
    });
  });

  group('the stats calendar', () {
    late AppDatabase db;
    late ProviderContainer container;

    setUp(() {
      db = AppDatabase(NativeDatabase.memory());
      container = ProviderContainer(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          todayProvider.overrideWithValue(_today),
        ],
      );
    });

    tearDown(() async {
      container.dispose();
      await db.close();
    });

    Future<void> readOn(DateTime day, int pages) async {
      await db
          .into(db.readingLog)
          .insert(
            ReadingLogCompanion.insert(
              id: 'log-${day.millisecondsSinceEpoch}',
              planId: 'plan-1',
              readDate: dateOnly(day),
              fromPage: 1,
              toPage: pages,
              pagesRead: pages,
              createdAt: day,
            ),
          );
    }

    test('ends on today and never draws a future square', () async {
      final columns = container.read(libraryCalendarProvider);

      expect(columns, hasLength(statsCalendarColumns));
      expect(columns.last.last.date, dateOnly(_today));
      expect(
        columns
            .expand((column) => column)
            .every((day) => !day.date.isAfter(_today)),
        isTrue,
      );
    });

    test('covers a full fifteen weeks', () {
      final columns = container.read(libraryCalendarProvider);
      final days = columns.expand((column) => column).length;

      expect(days, calendarWindowDays(statsCalendarColumns));
    });

    test('fills the days that were read', () async {
      // The plan is only here to give the log rows something to hang off; the
      // calendar totals every book, so it never asks which plan they were.
      await db
          .into(db.books)
          .insert(
            BooksCompanion.insert(
              id: 'book-1',
              title: 'The Muqaddimah',
              pageCount: 300,
              createdAt: _jan1,
              updatedAt: _jan1,
            ),
          );
      await db
          .into(db.readingPlans)
          .insert(
            ReadingPlansCompanion.insert(
              id: 'plan-1',
              bookId: 'book-1',
              mode: PlanMode.byPagesPerDay,
              startPage: 1,
              endPage: 300,
              startDate: _jan1,
              targetEndDate: DateTime(2026, 2, 1),
              pagesPerDay: 10,
              createdAt: _jan1,
              updatedAt: _jan1,
            ),
          );
      await readOn(addDays(_today, -1), 5);
      await readOn(_today, 20);

      // Two database streams feed the calendar, and neither has delivered yet
      // at the moment the rows are written. The listener keeps the provider
      // alive while they do.
      container.listen(libraryCalendarProvider, (_, _) {});
      for (var turn = 0; turn < 5; turn++) {
        await Future<void>.delayed(Duration.zero);
      }

      final columns = container.read(libraryCalendarProvider);
      final days = columns.expand((column) => column).toList();

      final yesterday = days.firstWhere(
        (day) => day.date == dateOnly(addDays(_today, -1)),
      );
      final today = days.firstWhere((day) => day.date == dateOnly(_today));

      expect(yesterday.pages, 5);
      // Half the day's portion, so half strength.
      expect(yesterday.intensity, closeTo(0.5, 0.001));
      // Twice the portion caps at full: three days' reading in one sitting is
      // one dark square, not a brighter one than the square beside it.
      expect(today.intensity, 1);
    });
  });

  group('the stats screen', () {
    late AppDatabase db;

    setUp(() => db = AppDatabase(NativeDatabase.memory()));
    tearDown(() => db.close());

    testWidgets('draws the calendar under the chart', (tester) async {
      await db
          .into(db.books)
          .insert(
            BooksCompanion.insert(
              id: 'book-1',
              title: 'The Muqaddimah',
              pageCount: 300,
              createdAt: _jan1,
              updatedAt: _jan1,
            ),
          );
      await db
          .into(db.readingPlans)
          .insert(
            ReadingPlansCompanion.insert(
              id: 'plan-1',
              bookId: 'book-1',
              mode: PlanMode.byPagesPerDay,
              startPage: 1,
              endPage: 300,
              startDate: _jan1,
              targetEndDate: DateTime(2026, 2, 1),
              pagesPerDay: 10,
              createdAt: _jan1,
              updatedAt: _jan1,
            ),
          );
      await db.recordReading(
        planId: 'plan-1',
        fromPage: 1,
        toPage: 10,
        readAt: _today,
        logId: 'log-1',
      );

      // A phone-height viewport rather than the 600px default: the screen is a
      // lazy list and the calendar sits below the chart, so on a short viewport
      // it is never built and cannot be found at all.
      tester.view.physicalSize = const Size(400 * 3, 1400 * 3);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.resetPhysicalSize);

      final semantics = tester.ensureSemantics();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            appDatabaseProvider.overrideWithValue(db),
            todayProvider.overrideWithValue(_today),
          ],
          child: MaterialApp(
            locale: const Locale('en'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            theme: AppTheme.of(
              brightness: Brightness.light,
              locale: const Locale('en'),
            ),
            home: const StatsScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final l10n = await AppLocalizations.delegate.load(const Locale('en'));
      // The section heading sets through `Kicker`, which upper-cases it.
      expect(find.text(l10n.statsCalendarHint), findsOneWidget);
      expect(find.byType(ReadingCalendarGrid), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 1));
      semantics.dispose();
    });
  });
}
