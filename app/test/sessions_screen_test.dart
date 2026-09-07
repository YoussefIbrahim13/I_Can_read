// `show OrderingTerm` only: drift's full export collides with matcher.
import 'package:drift/drift.dart' show OrderingTerm;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:i_can_read/core/db/app_database.dart';
import 'package:i_can_read/core/planning/plan_math.dart';
import 'package:i_can_read/core/theme/app_theme.dart';
import 'package:i_can_read/features/sessions/presentation/sessions_screen.dart';
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
    await db
        .into(db.readingPlans)
        .insert(
          ReadingPlansCompanion.insert(
            id: 'plan-1',
            bookId: 'book-1',
            mode: PlanMode.byPagesPerDay,
            startPage: 1,
            endPage: 240,
            startDate: _jan1,
            targetEndDate: DateTime(2026, 1, 16),
            pagesPerDay: 15,
            createdAt: _jan1,
            updatedAt: _jan1,
          ),
        );
  });

  tearDown(() => db.close());

  // Same two hazards as the plan screen: a leaked semantics handle and drift's
  // stream-close timer both have to be cleared inside the test body.
  SemanticsHandle? semantics;

  Future<void> pumpSessions(WidgetTester tester, {Locale? locale}) async {
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
          home: const SessionsScreen(bookId: 'book-1'),
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

  Future<List<ReadingSession>> storedSessions() =>
      (db.select(db.readingSessions)
            ..orderBy([(s) => OrderingTerm.asc(s.ordinal)]))
          .get();

  testWidgets('opens on one evening session holding the whole portion', (
    tester,
  ) async {
    await pumpSessions(tester);

    expect(find.text('20:00'), findsOneWidget);
    expect(find.text('15'), findsOneWidget);
    expect(find.textContaining('15 pages'), findsWidgets);

    await closeApp(tester);
  });

  testWidgets('adding a session splits the day, morning first', (tester) async {
    await pumpSessions(tester);

    await tester.tap(find.text('Add a session'));
    await tester.pumpAndSettle();

    expect(find.text('08:00'), findsOneWidget);
    expect(find.text('20:00'), findsOneWidget);
    // 15 pages over two sessions: the spare page goes to the earlier one.
    expect(find.text('8'), findsOneWidget);
    expect(find.text('7'), findsOneWidget);

    await closeApp(tester);
  });

  testWidgets('moving pages into one session takes them from the other', (
    tester,
  ) async {
    await pumpSessions(tester);
    await tester.tap(find.text('Add a session'));
    await tester.pumpAndSettle();

    await tester.tap(
      find.bySemanticsLabel('One page more in this session').first,
    );
    await tester.pumpAndSettle();

    expect(find.text('9'), findsOneWidget);
    expect(find.text('6'), findsOneWidget);

    await closeApp(tester);
  });

  testWidgets('saving writes one row per session, in time order', (
    tester,
  ) async {
    await pumpSessions(tester);
    await tester.tap(find.text('Add a session'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Start the plan'));
    await tester.pumpAndSettle();

    final saved = await storedSessions();
    expect(saved, hasLength(2));
    expect(saved[0].timeOfDayMinutes, 8 * 60);
    expect(saved[0].pagesShare, 8);
    expect(saved[1].timeOfDayMinutes, 20 * 60);
    expect(saved[1].pagesShare, 7);
    // The ordinal is what seeds the notification id, so it has to be dense.
    expect([for (final s in saved) s.ordinal], [0, 1]);

    await closeApp(tester);
  });

  testWidgets('reopening restores the split that was saved', (tester) async {
    await pumpSessions(tester);
    await tester.tap(find.text('Add a session'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.bySemanticsLabel('One page more in this session').first,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Start the plan'));
    await tester.pumpAndSettle();
    await closeApp(tester);

    await pumpSessions(tester);

    expect(find.text('9'), findsOneWidget);
    expect(find.text('6'), findsOneWidget);
    expect(await storedSessions(), hasLength(2));

    await closeApp(tester);
  });

  testWidgets('a lone session cannot be removed', (tester) async {
    await pumpSessions(tester);

    // Scoped by icon: the back arrow in the header is an `IconButton` too.
    final remove = tester.widget<IconButton>(
      find.widgetWithIcon(IconButton, Icons.close),
    );
    expect(remove.onPressed, isNull);

    await closeApp(tester);
  });

  testWidgets('Arabic renders the split right-to-left', (tester) async {
    await pumpSessions(tester, locale: const Locale('ar'));

    expect(find.text('إضافة جلسة'), findsOneWidget);
    expect(find.text('ابدأ الختمة'), findsOneWidget);
    // Times stay western digits under Arabic.
    expect(find.text('20:00'), findsOneWidget);

    await closeApp(tester);
  });
}
