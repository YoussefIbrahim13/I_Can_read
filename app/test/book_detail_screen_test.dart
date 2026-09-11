import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:i_can_read/core/db/app_database.dart';
import 'package:i_can_read/core/files/book_file_store.dart';
import 'package:i_can_read/core/planning/plan_math.dart';
import 'package:i_can_read/core/theme/app_theme.dart';
import 'package:i_can_read/features/book_detail/presentation/book_detail_screen.dart';
import 'package:i_can_read/features/today/application/today_providers.dart';
import 'package:i_can_read/l10n/app_localizations.dart';

final _jan1 = DateTime(2026, 1, 1);

/// The fifth: four days of a ten-day plan are done.
final _today = DateTime(2026, 1, 5);

void main() {
  late AppDatabase db;

  // A store the actions can reach. The detail screen can now remove a book,
  // and removing one deletes the app's copy of its PDF.
  late Directory documents;
  late BookFileStore store;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    documents = await Directory.systemTemp.createTemp('i_can_read_detail');
    store = BookFileStore(documents);
  });
  tearDown(() async {
    await db.close();
    if (documents.existsSync()) await documents.delete(recursive: true);
  });

  // Drift's stream-close timer and any semantics handle both have to be
  // cleared inside the test body; see sessions_screen_test.dart.
  SemanticsHandle? semantics;

  Future<void> addBook({
    String? author = 'Ibn Khaldun',
    BookStatus status = BookStatus.reading,
    bool withPlan = true,
    int lastPageRead = 0,
    int sessionCount = 1,
    DateTime? pausedAt,
  }) async {
    await db
        .into(db.books)
        .insert(
          BooksCompanion.insert(
            id: 'book-1',
            title: 'The Muqaddimah',
            author: Value(author),
            pageCount: 240,
            status: Value(status),
            createdAt: _jan1,
            updatedAt: _jan1,
          ),
        );
    if (!withPlan) return;

    await db
        .into(db.readingPlans)
        .insert(
          ReadingPlansCompanion.insert(
            id: 'plan-1',
            bookId: 'book-1',
            mode: PlanMode.byPagesPerDay,
            startPage: 1,
            endPage: 100,
            startDate: _jan1,
            targetEndDate: DateTime(2026, 1, 10),
            pagesPerDay: 10,
            lastPageRead: Value(lastPageRead),
            pausedAt: Value(pausedAt),
            createdAt: _jan1,
            updatedAt: _jan1,
          ),
        );
    await db.replaceSessions('plan-1', [
      for (var ordinal = 0; ordinal < sessionCount; ordinal++)
        ReadingSessionsCompanion.insert(
          id: 'session-$ordinal',
          planId: 'plan-1',
          ordinal: ordinal,
          timeOfDayMinutes: (8 + ordinal) * 60,
          pagesShare: 10 ~/ sessionCount,
          updatedAt: _jan1,
        ),
    ]);
  }

  Future<void> pumpDetail(
    WidgetTester tester, {
    Locale? locale,
    Size viewport = const Size(400, 1200),
  }) async {
    // A phone-height viewport rather than the 600px default. The screen is a
    // lazy list, and since the record link was added under the calendar the
    // action row sits below the fold — where it is never built and cannot be
    // found at all. Same reason as stats_screen_test.dart.
    tester.view.physicalSize = viewport * 3;
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    semantics ??= tester.ensureSemantics();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          bookFileStoreProvider.overrideWithValue(store),
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
          home: const BookDetailScreen(bookId: 'book-1'),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// Taps an action, scrolling it into view first.
  ///
  /// The 600px test viewport is shorter than the phone the screen is drawn
  /// for, so the action row can sit below the fold — and a tap at a point
  /// outside the viewport hits nothing and reports no error.
  Future<void> tap(WidgetTester tester, String label) async {
    final button = find.text(label);
    await tester.ensureVisible(button);
    await tester.pumpAndSettle();
    await tester.tap(button);
    await tester.pumpAndSettle();
  }

  Future<void> closeApp(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
    semantics?.dispose();
    semantics = null;
  }

  testWidgets('leads with the book and how far through it the reader is', (
    tester,
  ) async {
    await addBook(lastPageRead: 40);
    await pumpDetail(tester);

    // v2's masthead is the title and the author and nothing else.
    expect(find.text('The Muqaddimah'), findsOneWidget);
    expect(find.text('Ibn Khaldun'), findsOneWidget);
    // The figure stands bare, with its sign carried by the caption beside it.
    expect(find.text('40'), findsOneWidget);
    expect(find.text('of the book'), findsOneWidget);
    expect(find.text('40 of 100 pages'), findsOneWidget);
    // The book's two unchanging facts moved down among the plan's dates.
    expect(find.text('240 pages · Started 1 January'), findsOneWidget);

    await closeApp(tester);
  });

  testWidgets('states the plan as a portion and a count of sittings', (
    tester,
  ) async {
    await addBook(lastPageRead: 40, sessionCount: 2);
    await pumpDetail(tester);

    expect(find.text('THE PLAN'), findsOneWidget);
    expect(find.text('10 pages a day · 2 sessions'), findsOneWidget);

    await closeApp(tester);
  });

  testWidgets('adds up the time actually spent inside the book', (
    tester,
  ) async {
    await addBook(lastPageRead: 40);
    await db.recordReading(
      planId: 'plan-1',
      fromPage: 1,
      toPage: 20,
      readAt: DateTime(2026, 1, 3, 21),
      durationSeconds: const Duration(hours: 1, minutes: 5).inSeconds,
      logId: 'log-1',
    );
    await db.recordReading(
      planId: 'plan-1',
      fromPage: 21,
      toPage: 40,
      readAt: DateTime(2026, 1, 4, 21),
      durationSeconds: const Duration(minutes: 25).inSeconds,
      logId: 'log-2',
    );
    await pumpDetail(tester);

    expect(find.text('Time reading: 1 hour 30 minutes'), findsOneWidget);

    await closeApp(tester);
  });

  testWidgets('a book read before the clock existed claims no time', (
    tester,
  ) async {
    await addBook(lastPageRead: 40);
    await db.recordReading(
      planId: 'plan-1',
      fromPage: 1,
      toPage: 40,
      readAt: DateTime(2026, 1, 3, 21),
      logId: 'log-1',
    );
    await pumpDetail(tester);

    // Zero would read as "you finished forty pages instantly".
    expect(find.textContaining('Time reading'), findsNothing);

    await closeApp(tester);
  });

  testWidgets('offers the record from under the calendar', (tester) async {
    await addBook(lastPageRead: 40);
    await pumpDetail(tester);

    expect(find.text('READING DAYS'), findsOneWidget);
    expect(find.text('Every portion, day by day'), findsOneWidget);

    await closeApp(tester);
  });

  testWidgets('a reader on pace is told the date and nothing about lateness', (
    tester,
  ) async {
    await addBook(lastPageRead: 40);
    await pumpDetail(tester);

    expect(find.text('Projected finish: 10 January'), findsOneWidget);
    expect(find.textContaining('You aimed for'), findsNothing);

    await closeApp(tester);
  });

  testWidgets('missed days move the date, and the portion is left alone', (
    tester,
  ) async {
    // Four days elapsed, nothing read: the hundred pages now run to the 14th.
    await addBook(lastPageRead: 0);
    await pumpDetail(tester);

    expect(find.text('Projected finish: 14 January'), findsOneWidget);
    expect(
      find.text(
        'You aimed for 10 January. The daily portion is unchanged — '
        'only the date moved.',
      ),
      findsOneWidget,
    );
    // The quota itself is untouched — that is the promise being kept.
    expect(find.text('10 pages a day · 1 session'), findsOneWidget);

    await closeApp(tester);
  });

  testWidgets('a paused plan says so and offers to resume', (tester) async {
    await addBook(lastPageRead: 40, pausedAt: DateTime(2026, 1, 3));
    await pumpDetail(tester);

    expect(
      find.text(
        "Paused since 3 January. These days aren't counted against you.",
      ),
      findsOneWidget,
    );
    expect(find.text('Resume'), findsOneWidget);
    expect(find.text('Pause'), findsNothing);

    await closeApp(tester);
  });

  testWidgets('pausing stops the plan without touching the goal', (
    tester,
  ) async {
    await addBook(lastPageRead: 40);
    await pumpDetail(tester);

    await tap(tester, 'Pause');

    final plan = await db.activePlanFor('book-1');
    expect(plan!.pausedAt, isNotNull);
    // A pause suspends the plan; it does not renegotiate it.
    expect(plan.pagesPerDay, 10);
    expect(plan.lastPageRead, 40);

    await closeApp(tester);
  });

  testWidgets('resuming clears the pause and banks the days it lasted', (
    tester,
  ) async {
    await addBook(lastPageRead: 40, pausedAt: DateTime(2026, 1, 3));
    await pumpDetail(tester);

    await tap(tester, 'Resume');

    final plan = await db.activePlanFor('book-1');
    expect(plan!.pausedAt, isNull);
    expect(plan.pausedDays, greaterThan(0));

    await closeApp(tester);
  });

  testWidgets('marking a book finished moves it off the reading shelf', (
    tester,
  ) async {
    await addBook(lastPageRead: 40);
    await pumpDetail(tester);

    await tap(tester, 'I finished it');

    expect((await db.findBook('book-1'))!.status, BookStatus.finished);
    // And the screen redraws itself onto the new shelf rather than going on
    // offering to finish a book that is already finished.
    await tester.pumpAndSettle();
    expect(find.text('I finished it'), findsNothing);
    expect(find.text('Reading again'), findsOneWidget);

    await closeApp(tester);
  });

  testWidgets('a finished book is not offered a pause it cannot use', (
    tester,
  ) async {
    await addBook(lastPageRead: 100, status: BookStatus.finished);
    await pumpDetail(tester);

    expect(find.text('100'), findsOneWidget);
    expect(find.text('Pause'), findsNothing);
    expect(find.text('I finished it'), findsNothing);
    // One way out, and it is the reversible one.
    expect(find.text('Reading again'), findsOneWidget);

    await closeApp(tester);
  });

  testWidgets('a book with no plan is asked for one instead of reporting', (
    tester,
  ) async {
    await addBook(withPlan: false);
    await pumpDetail(tester);

    expect(find.text('No plan for this book yet.'), findsOneWidget);
    expect(find.text('Create a plan'), findsOneWidget);
    // Nothing to report, so none of the reporting is drawn.
    expect(find.text('THE PLAN'), findsNothing);
    expect(find.textContaining('Projected finish'), findsNothing);
    expect(find.text('I finished it'), findsNothing);

    await closeApp(tester);
  });

  testWidgets('a book with no plan can still be opened and read', (
    tester,
  ) async {
    // A goal is what the screen asks for, but it is not a toll gate: a reader
    // who just wants to open the book is not doing anything wrong.
    await addBook(withPlan: false);
    await pumpDetail(tester);

    expect(find.text('Open the book'), findsOneWidget);

    await closeApp(tester);
  });

  testWidgets('a book being read offers the way back into it', (tester) async {
    await addBook(lastPageRead: 40);
    await pumpDetail(tester);

    // Above the two things you do to the book itself, and not primary: the
    // screen still does not end in something to press.
    expect(find.text('Keep reading'), findsOneWidget);

    await closeApp(tester);
  });

  testWidgets('a finished book can be opened without being un-finished', (
    tester,
  ) async {
    await addBook(status: BookStatus.finished, lastPageRead: 100);
    await pumpDetail(tester);

    expect(find.text('Open the book'), findsOneWidget);
    expect(find.text('Reading again'), findsOneWidget);

    await closeApp(tester);
  });

  testWidgets('fits its actions across on the narrowest phone', (
    tester,
  ) async {
    // 320dp is the narrowest width the app claims to support, and the action
    // row is the only place two controls share one line. Tall, because the
    // width is the subject: v2's full-bleed reading calendar made the screen
    // longer, and the row would otherwise sit below the fold unbuilt.
    await addBook(lastPageRead: 40);
    await pumpDetail(tester, viewport: const Size(320, 1600));

    // An overflow would already have failed the pump; this pins the row down
    // as the thing being checked.
    expect(find.text('Pause'), findsOneWidget);
    expect(find.text('I finished it'), findsOneWidget);
    // Editing the plan is no longer down here — v2 moved it up beside the
    // plan sentence it edits, which is what left this row with two.
    expect(find.text('Edit the plan'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await closeApp(tester);
  });

  testWidgets('reads the same way in Arabic, with western figures', (
    tester,
  ) async {
    await addBook(lastPageRead: 0);
    await pumpDetail(tester, locale: const Locale('ar'));

    expect(find.text('الخطة'), findsOneWidget);
    expect(find.text('الانتهاء المتوقّع: 14 يناير'), findsOneWidget);
    expect(
      find.text(
        'كنت مستهدف 10 يناير. الورد اليومي زي ما هو — التاريخ بس اتأخر.',
      ),
      findsOneWidget,
    );
    expect(find.text('خلّصته'), findsOneWidget);

    await closeApp(tester);
  });
}
