import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:i_can_read/core/db/app_database.dart';
import 'package:i_can_read/core/planning/plan_math.dart';
import 'package:i_can_read/core/theme/app_theme.dart';
import 'package:i_can_read/features/stats/presentation/stats_screen.dart';
import 'package:i_can_read/features/today/application/today_providers.dart';
import 'package:i_can_read/l10n/app_localizations.dart';

final _jan1 = DateTime(2026, 1, 1);
final _today = DateTime(2026, 1, 30);

void main() {
  late AppDatabase db;

  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() => db.close());

  // Drift's stream-close timer and any semantics handle both have to be
  // cleared inside the test body; see sessions_screen_test.dart.
  SemanticsHandle? semantics;

  Future<void> addBook({
    required String id,
    required String title,
    int startDay = 1,
    int pageCount = 100,
  }) async {
    await db
        .into(db.books)
        .insert(
          BooksCompanion.insert(
            id: id,
            title: title,
            pageCount: pageCount,
            createdAt: _jan1,
            updatedAt: _jan1,
          ),
        );
    await db
        .into(db.readingPlans)
        .insert(
          ReadingPlansCompanion.insert(
            id: 'plan-$id',
            bookId: id,
            mode: PlanMode.byPagesPerDay,
            startPage: 1,
            endPage: pageCount,
            startDate: DateTime(2026, 1, startDay),
            targetEndDate: DateTime(2026, 2, 1),
            pagesPerDay: 10,
            createdAt: _jan1,
            updatedAt: _jan1,
          ),
        );
  }

  /// Logs a stretch of reading on a given day of January.
  ///
  /// An evening hour: the reading day rolls over at 04:00, so midnight would
  /// be credited to the day before.
  var logId = 0;
  Future<void> read(
    String bookId,
    int day,
    int pages, {
    int from = 1,
    Duration took = Duration.zero,
  }) {
    return db.recordReading(
      planId: 'plan-$bookId',
      fromPage: from,
      toPage: from + pages - 1,
      readAt: DateTime(2026, 1, day, 21),
      durationSeconds: took.inSeconds,
      logId: 'log-${logId++}',
    );
  }

  Future<void> pumpStats(WidgetTester tester, {Locale? locale}) async {
    // A phone-height viewport rather than the 600px default. The screen is a
    // lazy list, and since the reading calendar was added the finished-books
    // section sits below the fold — where it is never built and cannot be
    // found at all.
    tester.view.physicalSize = const Size(400 * 3, 1600 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.resetPhysicalSize);

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
          home: const StatsScreen(),
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

  testWidgets('nothing read yet is an empty state, not a wall of zeros', (
    tester,
  ) async {
    await pumpStats(tester);

    expect(find.text('Nothing to show yet.'), findsOneWidget);
    expect(find.text('days in a row'), findsNothing);

    await closeApp(tester);
  });

  testWidgets('leads with the three figures', (tester) async {
    await addBook(id: 'b1', title: 'The Muqaddimah');
    // Three days running, twenty pages a day.
    await read('b1', 28, 20, from: 1);
    await read('b1', 29, 20, from: 21);
    await read('b1', 30, 20, from: 41);
    await pumpStats(tester);

    expect(find.text('days in a row'), findsOneWidget);
    expect(find.text('pages a day on average'), findsOneWidget);
    expect(find.text('books finished'), findsOneWidget);
    // Streak of 3, averaging 20 a day, nothing finished.
    expect(find.text('3'), findsOneWidget);
    expect(find.text('20'), findsOneWidget);
    expect(find.text('0'), findsOneWidget);

    await closeApp(tester);
  });

  testWidgets('time read and the pace it implies sit under the figures', (
    tester,
  ) async {
    await addBook(id: 'b1', title: 'The Muqaddimah');
    // Twenty pages in forty minutes: two minutes a page.
    await read('b1', 29, 20, from: 1, took: const Duration(minutes: 40));
    await pumpStats(tester);

    expect(
      find.text('40 minutes with a book · about 2 minutes a page'),
      findsOneWidget,
    );

    await closeApp(tester);
  });

  testWidgets('untimed reading says nothing about time at all', (tester) async {
    await addBook(id: 'b1', title: 'The Muqaddimah');
    // Logged before the app started timing sittings.
    await read('b1', 29, 20, from: 1);
    await pumpStats(tester);

    expect(find.textContaining('with a book'), findsNothing);
    expect(find.textContaining('a page'), findsNothing);

    await closeApp(tester);
  });

  testWidgets('one short sitting is a total but not yet a pace', (
    tester,
  ) async {
    await addBook(id: 'b1', title: 'The Muqaddimah');
    // Under ReadingPace.minimumPages: enough to report, too little to predict.
    await read('b1', 29, 4, from: 1, took: const Duration(minutes: 8));
    await pumpStats(tester);

    expect(find.text('8 minutes with a book'), findsOneWidget);
    expect(find.textContaining('a page'), findsNothing);

    await closeApp(tester);
  });

  testWidgets('the chart is labelled from the window start to today', (
    tester,
  ) async {
    await addBook(id: 'b1', title: 'The Muqaddimah');
    await read('b1', 30, 5);
    await pumpStats(tester);

    expect(find.text('PAGES A DAY'), findsOneWidget);
    expect(find.text('1 January'), findsOneWidget);
    expect(find.text('Today'), findsOneWidget);

    await closeApp(tester);
  });

  testWidgets('a finished book is listed with how long it took', (
    tester,
  ) async {
    await addBook(id: 'b1', title: 'The Muqaddimah', startDay: 1);
    // Read the whole hundred pages, which flips the book to finished.
    await read('b1', 20, 100);
    await pumpStats(tester);

    expect((await db.findBook('b1'))!.status, BookStatus.finished);
    expect(find.text('BOOKS YOU FINISHED'), findsOneWidget);
    expect(find.text('The Muqaddimah'), findsOneWidget);
    // 1 January to 20 January, inclusive.
    expect(find.text('20 days'), findsOneWidget);

    await closeApp(tester);
  });

  testWidgets('pages a day totals every book, not one of them', (tester) async {
    await addBook(id: 'b1', title: 'First');
    await addBook(id: 'b2', title: 'Second');
    await read('b1', 30, 12);
    await read('b2', 30, 8);
    await pumpStats(tester);

    // Twenty pages on the one day read: both books, one figure.
    expect(find.text('20'), findsOneWidget);

    await closeApp(tester);
  });

  testWidgets('an unread today leaves yesterday\'s streak standing', (
    tester,
  ) async {
    await addBook(id: 'b1', title: 'The Muqaddimah');
    await read('b1', 28, 10, from: 1);
    await read('b1', 29, 10, from: 11);
    await pumpStats(tester);

    // Two days, not zero: today is not a missed day until it is over.
    expect(find.text('2'), findsOneWidget);

    await closeApp(tester);
  });

  testWidgets('reads the same way in Arabic', (tester) async {
    await addBook(id: 'b1', title: 'مقدمة ابن خلدون');
    await read('b1', 30, 100);
    await pumpStats(tester, locale: const Locale('ar'));

    expect(find.text('يوم ورا يوم'), findsOneWidget);
    expect(find.text('متوسط الصفحات باليوم'), findsOneWidget);
    expect(find.text('كتب خلّصتها'), findsOneWidget);
    expect(find.text('ختمات خلّصتها'), findsOneWidget);
    expect(find.text('النهارده'), findsOneWidget);
    // Western digits under Arabic, as everywhere else in the app.
    expect(find.text('1 يناير'), findsOneWidget);

    await closeApp(tester);
  });
}
