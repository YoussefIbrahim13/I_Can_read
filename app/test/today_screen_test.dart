import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:i_can_read/core/db/app_database.dart';
import 'package:i_can_read/core/planning/plan_math.dart';
import 'package:i_can_read/core/theme/app_theme.dart';
import 'package:i_can_read/features/today/application/today_providers.dart';
import 'package:i_can_read/features/today/presentation/today_screen.dart';
import 'package:i_can_read/l10n/app_localizations.dart';

final _today = DateTime(2026, 1, 7);
final _jan1 = DateTime(2026, 1, 1);

void main() {
  late AppDatabase db;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
  });

  tearDown(() => db.close());

  // Drift's stream-close timer and any semantics handle both have to be
  // cleared inside the test body; see sessions_screen_test.dart.
  SemanticsHandle? semantics;

  Future<void> addBook({
    String bookId = 'book-1',
    String planId = 'plan-1',
    String title = 'The Muqaddimah',
    String? author,
    int pagesPerDay = 15,
    int lastPageRead = 0,
    List<(int minutes, int pages)> sessions = const [(20 * 60, 15)],
  }) async {
    await db
        .into(db.books)
        .insert(
          BooksCompanion.insert(
            id: bookId,
            title: title,
            author: Value(author),
            pageCount: 240,
            createdAt: _jan1,
            updatedAt: _jan1,
          ),
        );
    await db
        .into(db.readingPlans)
        .insert(
          ReadingPlansCompanion.insert(
            id: planId,
            bookId: bookId,
            mode: PlanMode.byPagesPerDay,
            startPage: 1,
            endPage: 240,
            startDate: _jan1,
            targetEndDate: DateTime(2026, 1, 16),
            pagesPerDay: pagesPerDay,
            lastPageRead: Value(lastPageRead),
            createdAt: _jan1,
            updatedAt: _jan1,
          ),
        );
    await db.replaceSessions(planId, [
      for (final (ordinal, session) in sessions.indexed)
        ReadingSessionsCompanion.insert(
          id: '$planId-$ordinal',
          planId: planId,
          ordinal: ordinal,
          timeOfDayMinutes: session.$1,
          pagesShare: session.$2,
          updatedAt: _jan1,
        ),
    ]);
  }

  /// Credits pages to today, so the screen sees a part-finished day.
  ///
  /// An evening hour, not midnight: the reading day rolls over at 04:00, so
  /// `_today` at 00:00 would be credited to the sixth.
  Future<void> readToday(String planId, int fromPage, int toPage) {
    return db.recordReading(
      planId: planId,
      fromPage: fromPage,
      toPage: toPage,
      readAt: _today.add(const Duration(hours: 21)),
      logId: 'log-$planId-$fromPage',
    );
  }

  /// Gives the pace a sample, without moving the plan's progress.
  ///
  /// Written straight into the log rather than through `recordReading`: these
  /// sittings exist only to be measured, and advancing `lastPageRead` would
  /// change the very portion the test is looking at.
  Future<void> timedSitting(
    String planId, {
    required int pages,
    required Duration took,
  }) {
    return db
        .into(db.readingLog)
        .insert(
          ReadingLogCompanion.insert(
            id: 'timed-$planId',
            planId: planId,
            readDate: _jan1,
            fromPage: 1,
            toPage: pages,
            pagesRead: pages,
            durationSeconds: Value(took.inSeconds),
            createdAt: _jan1,
          ),
        );
  }

  Future<void> pumpToday(WidgetTester tester, {Locale? locale}) async {
    semantics ??= tester.ensureSemantics();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          todayProvider.overrideWithValue(_today),
        ],
        child: MaterialApp(
          locale: locale ?? const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          theme: AppTheme.of(
            brightness: Brightness.light,
            locale: locale ?? const Locale('en'),
          ),
          home: const TodayScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> closeApp(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
    semantics?.dispose();
    semantics = null;
  }

  testWidgets('leads with the session and the pages it owes', (tester) async {
    await addBook();
    await pumpToday(tester);

    expect(find.text('THIS SESSION'), findsOneWidget);
    expect(find.text('20:00'), findsOneWidget);
    expect(find.text('The Muqaddimah'), findsOneWidget);
    expect(find.text('15'), findsWidgets);
    expect(find.text('pages left'), findsOneWidget);
    expect(find.text('1–15'), findsOneWidget);
    expect(find.text('Read now'), findsOneWidget);

    await closeApp(tester);
  });

  testWidgets('once the reader has been timed, the day says how long', (
    tester,
  ) async {
    await addBook();
    // Thirty pages in half an hour: a minute a page, so fifteen pages left
    // is a quarter of an hour — on the hero and on the day card alike.
    await timedSitting('plan-1', pages: 30, took: const Duration(minutes: 30));
    await pumpToday(tester);

    expect(find.text('about 15 minutes'), findsNWidgets(2));

    await closeApp(tester);
  });

  testWidgets('an unmeasured reader is given no estimate to plan by', (
    tester,
  ) async {
    await addBook();
    await pumpToday(tester);

    expect(find.textContaining('about'), findsNothing);

    await closeApp(tester);
  });

  testWidgets('the estimate counts what is left, not the whole portion', (
    tester,
  ) async {
    await addBook();
    await timedSitting('plan-1', pages: 30, took: const Duration(minutes: 30));
    await readToday('plan-1', 1, 10);
    await pumpToday(tester);

    // Ten of fifteen done, so five minutes remain — not fifteen.
    expect(find.text('about 5 minutes'), findsNWidgets(2));

    await closeApp(tester);
  });

  testWidgets('later sessions sit under the hero, quietly', (tester) async {
    await addBook(sessions: const [(8 * 60, 8), (20 * 60, 7)]);
    await pumpToday(tester);

    expect(find.text('LATER TODAY'), findsOneWidget);
    // The hero is the morning session; the evening one is the later row.
    expect(find.text('08:00'), findsOneWidget);
    expect(find.text('20:00'), findsOneWidget);
    expect(find.text('9–15'), findsOneWidget);

    await closeApp(tester);
  });

  testWidgets('a finished session hands the hero to the next one', (
    tester,
  ) async {
    await addBook(sessions: const [(8 * 60, 8), (20 * 60, 7)]);
    await readToday('plan-1', 1, 8);
    await pumpToday(tester);

    // The morning is done, so the evening leads and owes its own seven.
    expect(find.text('20:00'), findsOneWidget);
    expect(find.text('7'), findsWidgets);
    expect(find.text('9–15'), findsOneWidget);
    // The finished morning is not repeated as a row — "later today" means
    // later — but it is still counted in the day.
    expect(find.text('1–8'), findsNothing);
    expect(find.text('LATER TODAY'), findsNothing);
    expect(find.text('8 of 15 pages done'), findsOneWidget);

    await closeApp(tester);
  });

  testWidgets('the day card counts every book', (tester) async {
    await addBook(sessions: const [(8 * 60, 8), (20 * 60, 7)]);
    await addBook(
      bookId: 'book-2',
      planId: 'plan-2',
      title: 'Kalila wa Dimna',
      pagesPerDay: 8,
      sessions: const [(7 * 60, 8)],
    );
    await readToday('plan-1', 1, 8);
    await pumpToday(tester);

    expect(find.text('ALL OF TODAY'), findsOneWidget);
    expect(find.text('8 of 23 pages done'), findsOneWidget);
    expect(find.text('3 sessions across 2 books'), findsOneWidget);

    await closeApp(tester);
  });

  testWidgets('finishing the day replaces the hero', (tester) async {
    await addBook();
    await readToday('plan-1', 1, 15);
    await pumpToday(tester);

    expect(find.text("Today's portion is done."), findsOneWidget);
    expect(find.text('Read now'), findsNothing);
    expect(find.text('LATER TODAY'), findsNothing);

    await closeApp(tester);
  });

  testWidgets('no plans means the empty state, not an empty day', (
    tester,
  ) async {
    await pumpToday(tester);

    expect(find.text('Nothing to read today.'), findsOneWidget);
    expect(find.text('Add a book'), findsOneWidget);

    await closeApp(tester);
  });

  testWidgets('a book with no sessions yet is not on the day', (tester) async {
    await addBook(sessions: const []);
    await pumpToday(tester);

    expect(find.text('Nothing to read today.'), findsOneWidget);

    await closeApp(tester);
  });

  testWidgets('Arabic keeps the page range in western digits, unreversed', (
    tester,
  ) async {
    await addBook();
    await pumpToday(tester, locale: const Locale('ar'));

    expect(find.text('جلستك دي'), findsOneWidget);
    expect(find.text('اقرأ دلوقتي'), findsOneWidget);
    expect(find.text('20:00'), findsOneWidget);
    expect(find.text('1–15'), findsOneWidget);

    await closeApp(tester);
  });

  testWidgets('Arabic counts the estimate in duals, not in «2 دقيقة»', (
    tester,
  ) async {
    await addBook(sessions: const [(20 * 60, 2)], pagesPerDay: 2);
    // A minute a page, so a two-page session is «دقيقتين» — the dual, which a
    // plural built only from one/other would get wrong.
    await timedSitting('plan-1', pages: 30, took: const Duration(minutes: 30));
    await pumpToday(tester, locale: const Locale('ar'));

    expect(find.text('حوالي دقيقتين'), findsWidgets);

    await closeApp(tester);
  });
}
