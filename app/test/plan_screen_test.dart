import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:i_can_read/core/db/app_database.dart';
import 'package:i_can_read/core/theme/app_theme.dart';
import 'package:i_can_read/features/plan/presentation/plan_screen.dart';
import 'package:i_can_read/l10n/app_localizations.dart';

final _jan1 = DateTime(2026, 1, 1);

void main() {
  late AppDatabase db;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    await db
        .into(db.books)
        .insert(
          BooksCompanion.insert(
            id: 'book-1',
            title: 'The Muqaddimah',
            pageCount: 240,
            createdAt: _jan1,
            updatedAt: _jan1,
          ),
        );
  });

  tearDown(() => db.close());

  // The steppers are found by their screen-reader labels, which only exist
  // while the semantics tree is being built. Held here rather than registered
  // with `addTearDown`, because the framework checks for leaked handles before
  // teardowns run — so, like the unmount below, it has to happen in the body.
  SemanticsHandle? semantics;

  Future<void> pumpPlan(WidgetTester tester, {Locale? locale}) async {
    semantics ??= tester.ensureSemantics();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [appDatabaseProvider.overrideWithValue(db)],
        child: MaterialApp(
          locale: locale ?? const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          theme: AppTheme.of(
            brightness: Brightness.light,
            locale: locale ?? const Locale('en'),
          ),
          home: const PlanScreen(bookId: 'book-1'),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// Unmounts the app and gives drift's stream teardown a frame to finish.
  ///
  /// Disposing a live drift stream schedules a zero-duration timer to close it,
  /// created *during* the frame that unmounts the tree — so it is still pending
  /// when the framework's own cleanup pump returns, and every test would fail
  /// on "a Timer is still pending". One extra pump inside the body clears it.
  Future<void> closeApp(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    // Has to advance the clock: the timer is created *during* the unmount
    // frame, and a zero-duration pump does not run a timer scheduled inside the
    // elapse it is already performing.
    await tester.pump(const Duration(milliseconds: 1));

    semantics?.dispose();
    semantics = null;
  }

  Future<ReadingPlan?> savedPlan() => db.activePlanFor('book-1');

  testWidgets('opens on a month-long goal, named in the preview', (
    tester,
  ) async {
    await pumpPlan(tester);

    // 240 pages over 30 days, so the daily portion is 8 — and it is the number
    // the reader sees, not something they have to work out.
    expect(find.text('8'), findsOneWidget);
    expect(find.textContaining('a day and finish on'), findsOneWidget);
    expect(find.textContaining('240 pages total'), findsOneWidget);

    await closeApp(tester);
  });

  testWidgets('a preset moves the deadline and the daily portion with it', (
    tester,
  ) async {
    await pumpPlan(tester);

    await tester.tap(find.text('60 days'));
    await tester.pumpAndSettle();

    // 240 over 60 days.
    expect(find.text('4'), findsOneWidget);
    expect(find.textContaining('60 days ·'), findsOneWidget);

    await closeApp(tester);
  });

  testWidgets('switching to pages-a-day keeps the plan the reader had', (
    tester,
  ) async {
    await pumpPlan(tester);

    await tester.tap(find.text('Pages per day'));
    await tester.pumpAndSettle();

    // The stepper opens on the 8 the deadline implied, rather than resetting.
    expect(find.text('8'), findsNWidgets(2)); // the preview and the stepper

    await closeApp(tester);
  });

  testWidgets('the stepper moves the projected finish date', (tester) async {
    await pumpPlan(tester);
    await tester.tap(find.text('Pages per day'));
    await tester.pumpAndSettle();

    await tester.tap(find.bySemanticsLabel('One page a day more'));
    await tester.pumpAndSettle();

    expect(find.text('9'), findsNWidgets(2));

    await closeApp(tester);
  });

  testWidgets('starting later shortens the plan, not the book', (tester) async {
    await pumpPlan(tester);

    // The start-page row sits below the fold on a test-sized screen, and a
    // `ListView` does not build what it cannot show.
    await tester.scrollUntilVisible(
      find.bySemanticsLabel('One page more'),
      120,
    );
    await tester.tap(find.bySemanticsLabel('One page more'));
    await tester.pumpAndSettle();

    expect(find.textContaining('239 pages from page 2'), findsOneWidget);

    await closeApp(tester);
  });

  testWidgets('saving writes the plan and leaves the screen', (tester) async {
    await pumpPlan(tester);
    expect(await savedPlan(), isNull);

    await tester.tap(find.text('Continue to sessions'));
    await tester.pumpAndSettle();

    final plan = await savedPlan();
    expect(plan, isNotNull);
    expect(plan!.pagesPerDay, 8);
    expect(plan.startPage, 1);
    expect(plan.endPage, 240);

    await closeApp(tester);
  });

  testWidgets('reopening a book with a plan edits it rather than adding', (
    tester,
  ) async {
    await pumpPlan(tester);
    await tester.tap(find.text('Continue to sessions'));
    await tester.pumpAndSettle();
    // Leave the screen for real, so the form is rebuilt from the stored plan
    // rather than from whatever the first pass left in its state.
    await closeApp(tester);

    await pumpPlan(tester);
    expect(find.text('Edit the plan'), findsOneWidget);

    await tester.tap(find.text('Pages per day'));
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsLabel('One page a day more'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(await db.select(db.readingPlans).get(), hasLength(1));
    expect((await savedPlan())!.pagesPerDay, 9);

    await closeApp(tester);
  });

  testWidgets('Arabic renders the same plan right-to-left', (tester) async {
    await pumpPlan(tester, locale: const Locale('ar'));

    expect(find.text('كمّل للجلسات'), findsOneWidget);
    expect(find.textContaining('هتقرأ'), findsOneWidget);
    // Figures stay western even under Arabic.
    expect(find.text('8'), findsOneWidget);

    await closeApp(tester);
  });
}
