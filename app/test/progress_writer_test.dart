import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:i_can_read/core/db/app_database.dart';
import 'package:i_can_read/core/planning/plan_math.dart';
import 'package:i_can_read/features/reader/application/reader_providers.dart';

final _jan1 = DateTime(2026, 1, 1);

/// The seam between the reader's stopwatch and the log.
///
/// Thin enough to look not worth testing, which is exactly why it is: a
/// dropped `spent` here would leave every sitting recorded as instant, and
/// nothing downstream would complain — the pace would simply never appear.
void main() {
  late AppDatabase db;
  late ProgressWriter writer;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    writer = ProgressWriter(db);

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

  test('a measured sitting reaches the log as the time it took', () async {
    await writer.record(
      planId: 'plan-1',
      fromPage: 1,
      toPage: 15,
      spent: const Duration(minutes: 22),
    );

    expect(await db.readingTimeFor('plan-1'), const Duration(minutes: 22));
  });

  test('a caller with no clock records nothing rather than a guess', () async {
    await writer.record(planId: 'plan-1', fromPage: 1, toPage: 15);

    expect(await db.readingTimeFor('plan-1'), Duration.zero);
    // And the sitting is left out of the pace entirely, not counted as
    // fifteen pages read in no time at all.
    expect((await db.watchReadingPace(planId: 'plan-1').first).pages, 0);
  });

  test(
    'seconds survive the trip; a sitting is not rounded to whole minutes',
    () async {
      await writer.record(
        planId: 'plan-1',
        fromPage: 1,
        toPage: 15,
        spent: const Duration(minutes: 3, seconds: 40),
      );

      expect(
        await db.readingTimeFor('plan-1'),
        const Duration(minutes: 3, seconds: 40),
      );
    },
  );
}
