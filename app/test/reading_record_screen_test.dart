import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:i_can_read/core/db/app_database.dart';
import 'package:i_can_read/core/planning/plan_math.dart';
import 'package:i_can_read/core/theme/app_theme.dart';
import 'package:i_can_read/features/book_detail/presentation/reading_record_screen.dart';
import 'package:i_can_read/features/today/application/today_providers.dart';
import 'package:i_can_read/l10n/app_localizations.dart';

final _jan1 = DateTime(2026, 1, 1);
final _today = DateTime(2026, 1, 10);

void main() {
  late AppDatabase db;

  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() => db.close());

  // Drift's stream-close timer and any semantics handle both have to be
  // cleared inside the test body; see sessions_screen_test.dart.
  SemanticsHandle? semantics;

  Future<void> addBook() async {
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
            targetEndDate: DateTime(2026, 1, 24),
            pagesPerDay: 10,
            createdAt: _jan1,
            updatedAt: _jan1,
          ),
        );
  }

  /// One sitting. An evening hour: the reading day rolls over at 04:00.
  var logId = 0;
  Future<void> read(
    int day,
    int from,
    int to, {
    Duration took = Duration.zero,
    int hour = 21,
  }) {
    return db.recordReading(
      planId: 'plan-1',
      fromPage: from,
      toPage: to,
      readAt: DateTime(2026, 1, day, hour),
      durationSeconds: took.inSeconds,
      logId: 'log-${logId++}',
    );
  }

  Future<void> pumpRecord(WidgetTester tester, {Locale? locale}) async {
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
          home: const ReadingRecordScreen(bookId: 'book-1'),
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

  testWidgets('lists each day with its pages and what it took', (tester) async {
    await addBook();
    await read(3, 1, 10, took: const Duration(minutes: 12));
    await read(5, 11, 20, took: const Duration(minutes: 18));
    await pumpRecord(tester);

    expect(find.text('5 January'), findsOneWidget);
    expect(find.text('10 pages · 18 minutes'), findsOneWidget);
    expect(find.text('11–20'), findsOneWidget);

    expect(find.text('3 January'), findsOneWidget);
    expect(find.text('10 pages · 12 minutes'), findsOneWidget);
    expect(find.text('1–10'), findsOneWidget);

    await closeApp(tester);
  });

  testWidgets('leads with what the whole record adds up to', (tester) async {
    await addBook();
    await read(3, 1, 10, took: const Duration(minutes: 12));
    await read(5, 11, 20, took: const Duration(minutes: 18));
    await pumpRecord(tester);

    expect(find.text('2 days · 20 pages'), findsOneWidget);
    expect(find.text('30 minutes in all'), findsOneWidget);

    await closeApp(tester);
  });

  testWidgets('two sittings in a day are one portion, and say so', (
    tester,
  ) async {
    await addBook();
    await read(5, 1, 6, hour: 8, took: const Duration(minutes: 5));
    await read(5, 7, 10, hour: 21, took: const Duration(minutes: 4));
    await pumpRecord(tester);

    // One row, one range, both sittings' pages and time added up.
    expect(find.text('5 January'), findsOneWidget);
    expect(find.text('10 pages · 9 minutes · 2 sittings'), findsOneWidget);
    expect(find.text('1–10'), findsOneWidget);

    await closeApp(tester);
  });

  testWidgets('a day nobody timed says so instead of showing zero', (
    tester,
  ) async {
    await addBook();
    await read(5, 1, 10);
    await pumpRecord(tester);

    expect(find.text('10 pages · not timed'), findsOneWidget);
    // And with nothing measured at all, the record claims no total either.
    expect(find.textContaining('in all'), findsNothing);

    await closeApp(tester);
  });

  testWidgets('a book with no reading yet is an empty state', (tester) async {
    await addBook();
    await pumpRecord(tester);

    expect(find.text('Nothing here yet.'), findsOneWidget);
    // No totals row: zero days and zero pages is not a record, it is a blank.
    expect(find.textContaining('days ·'), findsNothing);

    await closeApp(tester);
  });

  testWidgets('reads the same way in Arabic, with western figures', (
    tester,
  ) async {
    await addBook();
    await read(5, 11, 20, took: const Duration(minutes: 18));
    await pumpRecord(tester, locale: const Locale('ar'));

    expect(find.text('سجل الأوراد'), findsOneWidget);
    expect(find.text('5 يناير'), findsOneWidget);
    // The range keeps western digits and does not reverse under RTL.
    expect(find.text('11–20'), findsOneWidget);
    expect(find.text('10 صفحات · 18 دقيقة'), findsOneWidget);

    await closeApp(tester);
  });
}
