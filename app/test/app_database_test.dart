// `show Value` only: drift also exports `isNull`, which collides with matcher.
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:i_can_read/core/db/app_database.dart';
import 'package:i_can_read/core/planning/plan_math.dart';
import 'package:i_can_read/core/planning/reading_pace.dart';

final _jan1 = DateTime(2026, 1, 1);
const _hash =
    'a3f5c1d2e4b6980a7c5e3f1d2b4a6c8e0f2d4b6a8c0e2f4d6b8a0c2e4f6d8b0a';

void main() {
  late AppDatabase db;

  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() => db.close());

  Future<void> insertBook({
    String id = 'book-1',
    String title = 'Test Book',
    int pageCount = 100,
  }) {
    return db
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
  }

  Future<void> insertPlan({
    String id = 'plan-1',
    String bookId = 'book-1',
    int startPage = 1,
    int endPage = 100,
    int pagesPerDay = 10,
  }) {
    return db
        .into(db.readingPlans)
        .insert(
          ReadingPlansCompanion.insert(
            id: id,
            bookId: bookId,
            mode: PlanMode.byPagesPerDay,
            startPage: startPage,
            endPage: endPage,
            startDate: _jan1,
            targetEndDate: DateTime(2026, 1, 10),
            pagesPerDay: pagesPerDay,
            createdAt: _jan1,
            updatedAt: _jan1,
          ),
        );
  }

  group('schema integrity', () {
    test('foreign keys are enforced, not just declared', () async {
      // SQLite ignores FK constraints unless the pragma is on; this asserts
      // the beforeOpen hook actually ran.
      await expectLater(
        db
            .into(db.readingPlans)
            .insert(
              ReadingPlansCompanion.insert(
                id: 'orphan',
                bookId: 'does-not-exist',
                mode: PlanMode.byDeadline,
                startPage: 1,
                endPage: 10,
                startDate: _jan1,
                targetEndDate: _jan1,
                pagesPerDay: 10,
                createdAt: _jan1,
                updatedAt: _jan1,
              ),
            ),
        throwsA(isA<SqliteException>()),
      );
    });

    test('deleting a book cascades to its plans, sessions and log', () async {
      await insertBook();
      await insertPlan();
      await db
          .into(db.readingSessions)
          .insert(
            ReadingSessionsCompanion.insert(
              id: 'session-1',
              planId: 'plan-1',
              ordinal: 0,
              timeOfDayMinutes: 7 * 60,
              pagesShare: 10,
              updatedAt: _jan1,
            ),
          );
      await db.recordReading(
        logId: 'log-1',
        planId: 'plan-1',
        fromPage: 1,
        toPage: 10,
        readAt: _jan1,
      );

      await (db.delete(db.books)..where((b) => b.id.equals('book-1'))).go();

      expect(await db.select(db.readingPlans).get(), isEmpty);
      expect(await db.select(db.readingSessions).get(), isEmpty);
      expect(await db.select(db.readingLog).get(), isEmpty);
    });
  });

  group('finding a book by its file', () {
    test('a known fingerprint resolves to its book', () async {
      await insertBook();
      await db
          .into(db.bookFingerprints)
          .insert(
            BookFingerprintsCompanion.insert(
              id: 'fp-1',
              bookId: 'book-1',
              sha256: _hash,
              pageCount: 100,
              sizeBytes: 2048,
              createdAt: _jan1,
            ),
          );

      final found = await db.findBookByFileHash(_hash);
      expect(found?.id, 'book-1');
    });

    test('an unknown fingerprint resolves to nothing', () async {
      await insertBook();
      expect(await db.findBookByFileHash(_hash), isNull);
    });

    test('a second edition of the same book relinks to it', () async {
      await insertBook();
      const otherHash =
          'b4e6d2c3f5a7091b8d6f4e2c3a5b7d9f1e3c5a7b9d1f3e5c7a9b1d3f5e7c9a1b';
      for (final (index, hash) in [_hash, otherHash].indexed) {
        await db
            .into(db.bookFingerprints)
            .insert(
              BookFingerprintsCompanion.insert(
                id: 'fp-$index',
                bookId: 'book-1',
                sha256: hash,
                pageCount: index == 0 ? 100 : 104,
                sizeBytes: 2048,
                createdAt: _jan1,
              ),
            );
      }

      expect((await db.findBookByFileHash(otherHash))?.id, 'book-1');
    });
  });

  group('recordReading', () {
    setUp(() async {
      await insertBook();
      await insertPlan();
    });

    test('advances progress and appends to the log', () async {
      await db.recordReading(
        logId: 'log-1',
        planId: 'plan-1',
        fromPage: 1,
        toPage: 10,
        readAt: _jan1,
      );

      final plan = await db.activePlanFor('book-1');
      expect(plan!.lastPageRead, 10);
      expect(await db.select(db.readingLog).get(), hasLength(1));
    });

    test('re-reading earlier pages never walks progress backwards', () async {
      await db.recordReading(
        logId: 'log-1',
        planId: 'plan-1',
        fromPage: 1,
        toPage: 50,
        readAt: _jan1,
      );
      await db.recordReading(
        logId: 'log-2',
        planId: 'plan-1',
        fromPage: 5,
        toPage: 12,
        readAt: DateTime(2026, 1, 2),
      );

      final plan = await db.activePlanFor('book-1');
      expect(plan!.lastPageRead, 50);
      // The revisit is still recorded — it just does not move the frontier.
      expect(await db.select(db.readingLog).get(), hasLength(2));
    });

    test('reaching the last page marks the book finished', () async {
      final finished = await db.recordReading(
        logId: 'log-1',
        planId: 'plan-1',
        fromPage: 91,
        toPage: 100,
        readAt: _jan1,
      );

      expect(finished, isTrue);
      final book = await db.findBook('book-1');
      expect(book!.status, BookStatus.finished);
    });

    test('stopping short of the end leaves the book in progress', () async {
      final finished = await db.recordReading(
        logId: 'log-1',
        planId: 'plan-1',
        fromPage: 91,
        toPage: 99,
        readAt: _jan1,
      );

      expect(finished, isFalse);
      expect((await db.findBook('book-1'))!.status, BookStatus.reading);
    });

    test('sums only the pages credited to a given day', () async {
      await db.recordReading(
        logId: 'log-1',
        planId: 'plan-1',
        fromPage: 1,
        toPage: 6,
        readAt: DateTime(2026, 1, 1, 8),
      );
      await db.recordReading(
        logId: 'log-2',
        planId: 'plan-1',
        fromPage: 7,
        toPage: 10,
        readAt: DateTime(2026, 1, 1, 21, 30),
      );
      await db.recordReading(
        logId: 'log-3',
        planId: 'plan-1',
        fromPage: 11,
        toPage: 20,
        readAt: DateTime(2026, 1, 2, 9),
      );

      expect(await db.pagesReadOn('plan-1', DateTime(2026, 1, 1, 23, 59)), 10);
      expect(await db.pagesReadOn('plan-1', DateTime(2026, 1, 2)), 10);
      expect(await db.pagesReadOn('plan-1', DateTime(2026, 1, 3)), 0);
    });
  });

  group('sessions', () {
    setUp(() async {
      await insertBook();
      await insertPlan();
    });

    test('replacing sessions swaps the whole set atomically', () async {
      await db.replaceSessions('plan-1', [
        ReadingSessionsCompanion.insert(
          id: 's1',
          planId: 'plan-1',
          ordinal: 0,
          timeOfDayMinutes: 420,
          pagesShare: 5,
          updatedAt: _jan1,
        ),
        ReadingSessionsCompanion.insert(
          id: 's2',
          planId: 'plan-1',
          ordinal: 1,
          timeOfDayMinutes: 1260,
          pagesShare: 5,
          updatedAt: _jan1,
        ),
      ]);

      expect(await db.watchSessionsFor('plan-1').first, hasLength(2));

      await db.replaceSessions('plan-1', [
        ReadingSessionsCompanion.insert(
          id: 's3',
          planId: 'plan-1',
          ordinal: 0,
          timeOfDayMinutes: 1320,
          pagesShare: 10,
          updatedAt: _jan1,
        ),
      ]);

      final sessions = await db.watchSessionsFor('plan-1').first;
      expect(sessions, hasLength(1));
      expect(sessions.single.id, 's3');
    });
  });

  group('missing files', () {
    test('a book with no local file is listed as missing', () async {
      await insertBook();
      final missing = await db.watchBooksMissingFiles().first;
      expect(missing.map((b) => b.id), ['book-1']);
    });

    test('a linked available file removes it from the list', () async {
      await insertBook();
      await db
          .into(db.localBookFiles)
          .insert(
            LocalBookFilesCompanion.insert(
              bookId: 'book-1',
              relativePath: 'books/book-1.pdf',
              linkedAt: _jan1,
            ),
          );

      expect(await db.watchBooksMissingFiles().first, isEmpty);
    });

    test('a file that has gone away is listed again', () async {
      await insertBook();
      await db
          .into(db.localBookFiles)
          .insert(
            LocalBookFilesCompanion.insert(
              bookId: 'book-1',
              relativePath: 'books/book-1.pdf',
              isAvailable: const Value(false),
              linkedAt: _jan1,
            ),
          );

      expect((await db.watchBooksMissingFiles().first).map((b) => b.id), [
        'book-1',
      ]);
    });
  });

  group('library shelves', () {
    test('soft-deleted books disappear from their shelf', () async {
      await insertBook();
      expect(await db.watchBooks(BookStatus.reading).first, hasLength(1));

      await (db.update(db.books)..where((b) => b.id.equals('book-1'))).write(
        BooksCompanion(deletedAt: Value(DateTime(2026, 2, 1))),
      );

      expect(await db.watchBooks(BookStatus.reading).first, isEmpty);
    });

    Future<List<String>> shelf({required bool paused}) async {
      final books = await db.watchBooksByPause(paused: paused).first;
      return books.map((b) => b.id).toList();
    }

    test('pausing a plan moves its book to the other shelf, once', () async {
      await insertBook();
      await insertPlan();

      expect(await shelf(paused: false), ['book-1']);
      expect(await shelf(paused: true), isEmpty);

      await db.pausePlan('plan-1', DateTime(2026, 1, 5));

      // The point of the split: never on both shelves at the same time.
      expect(await shelf(paused: false), isEmpty);
      expect(await shelf(paused: true), ['book-1']);

      await db.resumePlan('plan-1', DateTime(2026, 1, 9));

      expect(await shelf(paused: false), ['book-1']);
      expect(await shelf(paused: true), isEmpty);
    });

    test(
      'a book with no plan cannot be paused, so it stays on reading',
      () async {
        await insertBook();

        expect(await shelf(paused: false), ['book-1']);
        expect(await shelf(paused: true), isEmpty);
      },
    );

    test('a finished book is on neither reading shelf', () async {
      await insertBook();
      await insertPlan();
      await db.pausePlan('plan-1', DateTime(2026, 1, 5));
      await db.setBookStatus(
        'book-1',
        BookStatus.finished,
        DateTime(2026, 2, 1),
      );

      expect(await shelf(paused: false), isEmpty);
      expect(await shelf(paused: true), isEmpty);
      expect(await db.watchBooks(BookStatus.finished).first, hasLength(1));
    });
  });

  group('savePlan', () {
    PlanSpec spec({int startPage = 1, int pagesPerDay = 10}) =>
        PlanSpec.fromPagesPerDay(
          startPage: startPage,
          endPage: 100,
          startDate: _jan1,
          pagesPerDay: pagesPerDay,
        );

    test('creates the book\'s first plan', () async {
      await insertBook();

      final id = await db.savePlan(
        bookId: 'book-1',
        spec: spec(),
        now: _jan1,
        newPlanId: 'plan-new',
      );

      final stored = await db.activePlanFor('book-1');
      expect(id, 'plan-new');
      expect(stored!.id, 'plan-new');
      expect(stored.pagesPerDay, 10);
      expect(stored.targetEndDate, DateTime(2026, 1, 10));
    });

    test('rewrites an existing plan in place, keeping its id', () async {
      await insertBook();
      await insertPlan();

      final id = await db.savePlan(
        bookId: 'book-1',
        spec: spec(startPage: 9, pagesPerDay: 25),
        now: DateTime(2026, 2, 1),
        newPlanId: 'plan-unused',
      );

      expect(id, 'plan-1');
      final stored = await db.activePlanFor('book-1');
      expect(stored!.startPage, 9);
      expect(stored.pagesPerDay, 25);
      // One active plan, not a second one alongside the old.
      expect(await db.select(db.readingPlans).get(), hasLength(1));
    });

    test('editing the goal does not unread the pages already read', () async {
      await insertBook();
      await insertPlan();
      await db.recordReading(
        planId: 'plan-1',
        fromPage: 1,
        toPage: 30,
        readAt: _jan1,
        logId: 'log-1',
      );

      await db.savePlan(
        bookId: 'book-1',
        spec: spec(pagesPerDay: 5),
        now: DateTime(2026, 2, 1),
        newPlanId: 'plan-unused',
      );

      final stored = await db.activePlanFor('book-1');
      expect(stored!.lastPageRead, 30);
      expect(await db.select(db.readingLog).get(), hasLength(1));
    });

    test('watchActivePlans keys the shelf by book', () async {
      await insertBook();
      await insertBook(id: 'book-2', title: 'Second');
      await insertPlan();

      expect(await db.watchActivePlans().first, {'book-1': isA<ReadingPlan>()});
    });
  });

  group('pausing a plan', () {
    Future<ReadingPlan> storedPlan() => (db.select(
      db.readingPlans,
    )..where((p) => p.id.equals('plan-1'))).getSingle();

    Future<void> addSession() {
      return db.replaceSessions('plan-1', [
        ReadingSessionsCompanion.insert(
          id: 'session-1',
          planId: 'plan-1',
          ordinal: 0,
          timeOfDayMinutes: 20 * 60,
          pagesShare: 10,
          updatedAt: _jan1,
        ),
      ]);
    }

    setUp(() async {
      await insertBook();
      await insertPlan();
    });

    test(
      'a paused plan owes nothing today and reminds about nothing',
      () async {
        await addSession();
        expect(await db.watchLivePlanSessions().first, hasLength(1));

        await db.pausePlan('plan-1', DateTime(2026, 1, 5));

        expect(await db.watchLivePlanSessions().first, isEmpty);
        expect(await db.watchDueReminders().first, isEmpty);
      },
    );

    test('resuming banks the days spent paused', () async {
      await db.pausePlan('plan-1', DateTime(2026, 1, 5));
      await db.resumePlan('plan-1', DateTime(2026, 1, 9));

      final plan = await storedPlan();
      expect(plan.pausedAt, isNull);
      expect(plan.pausedDays, 4);
    });

    test('pauses accumulate across several breaks', () async {
      await db.pausePlan('plan-1', DateTime(2026, 1, 5));
      await db.resumePlan('plan-1', DateTime(2026, 1, 9));
      await db.pausePlan('plan-1', DateTime(2026, 1, 20));
      await db.resumePlan('plan-1', DateTime(2026, 1, 23));

      expect((await storedPlan()).pausedDays, 7);
    });

    test('pausing twice keeps the first pause date', () async {
      // The caller is a button; a double tap must not restart the clock.
      await db.pausePlan('plan-1', DateTime(2026, 1, 5));
      await db.pausePlan('plan-1', DateTime(2026, 1, 8));

      expect((await storedPlan()).pausedAt, DateTime(2026, 1, 5));
    });

    test('resuming a plan that was never paused changes nothing', () async {
      await db.resumePlan('plan-1', DateTime(2026, 1, 9));

      final plan = await storedPlan();
      expect(plan.pausedAt, isNull);
      expect(plan.pausedDays, 0);
    });

    test('a pause and a resume on the same day cost no days', () async {
      await db.pausePlan('plan-1', DateTime(2026, 1, 5, 9));
      await db.resumePlan('plan-1', DateTime(2026, 1, 5, 21));

      expect((await storedPlan()).pausedDays, 0);
    });

    test('the paused days feed straight into the schedule status', () async {
      await db.pausePlan('plan-1', DateTime(2026, 1, 2));
      await db.resumePlan('plan-1', DateTime(2026, 1, 6));

      final plan = await storedPlan();
      final status = scheduleStatus(
        db.specOf(plan),
        lastPageRead: 20,
        today: DateTime(2026, 1, 7),
        pausedDays: plan.pausedDays,
      );

      expect(status.isOnTrack, isTrue);
    });
  });

  group('the reading day', () {
    test('reading after midnight is credited to the day before', () async {
      await insertBook();
      await insertPlan();

      await db.recordReading(
        planId: 'plan-1',
        fromPage: 1,
        toPage: 10,
        readAt: DateTime(2026, 1, 8, 1, 30),
        logId: 'log-1',
      );

      expect(await db.pagesReadOn('plan-1', DateTime(2026, 1, 7)), 10);
      expect(await db.pagesReadOn('plan-1', DateTime(2026, 1, 8)), 0);
    });

    test('reading after the boundary is credited to the new day', () async {
      await insertBook();
      await insertPlan();

      await db.recordReading(
        planId: 'plan-1',
        fromPage: 1,
        toPage: 10,
        readAt: DateTime(2026, 1, 8, 4, 30),
        logId: 'log-1',
      );

      expect(await db.pagesReadOn('plan-1', DateTime(2026, 1, 8)), 10);
    });
  });

  group('reading time', () {
    test('adds up every sitting logged against the plan', () async {
      await insertBook();
      await insertPlan();

      await db.recordReading(
        logId: 'log-1',
        planId: 'plan-1',
        fromPage: 1,
        toPage: 10,
        readAt: _jan1,
        durationSeconds: 600,
      );
      await db.recordReading(
        logId: 'log-2',
        planId: 'plan-1',
        fromPage: 11,
        toPage: 20,
        readAt: DateTime(2026, 1, 2),
        durationSeconds: 900,
      );

      expect(
        await db.readingTimeFor('plan-1'),
        const Duration(minutes: 25),
      );
    });

    test('a sitting logged without a clock counts as nothing, not as null',
        () async {
      await insertBook();
      await insertPlan();
      await db.recordReading(
        logId: 'log-1',
        planId: 'plan-1',
        fromPage: 1,
        toPage: 10,
        readAt: _jan1,
      );

      expect(await db.readingTimeFor('plan-1'), Duration.zero);
    });

    test('a plan nobody has read is zero rather than an error', () async {
      await insertBook();
      await insertPlan();

      expect(await db.readingTimeFor('plan-1'), Duration.zero);
    });

    test('another plan\'s reading does not leak into this one', () async {
      await insertBook();
      await insertPlan();
      await insertBook(id: 'book-2', title: 'Other');
      await insertPlan(id: 'plan-2', bookId: 'book-2');

      await db.recordReading(
        logId: 'log-1',
        planId: 'plan-2',
        fromPage: 1,
        toPage: 10,
        readAt: _jan1,
        durationSeconds: 1200,
      );

      expect(await db.readingTimeFor('plan-1'), Duration.zero);
      expect(
        await db.readingTimeFor('plan-2'),
        const Duration(minutes: 20),
      );
    });
  });

  group('reading pace', () {
    test('divides measured pages by the time they measurably took', () async {
      await insertBook();
      await insertPlan();

      await db.recordReading(
        logId: 'log-1',
        planId: 'plan-1',
        fromPage: 1,
        toPage: 10,
        readAt: _jan1,
        durationSeconds: 600,
      );

      final pace = await db.watchReadingPace(planId: 'plan-1').first;

      expect(pace.pages, 10);
      expect(pace.time, const Duration(minutes: 10));
      expect(pace.perPage, const Duration(minutes: 1));
    });

    test('a sitting nobody timed is left out of the page count too', () async {
      await insertBook();
      await insertPlan();

      // Timed: ten pages, ten minutes.
      await db.recordReading(
        logId: 'log-1',
        planId: 'plan-1',
        fromPage: 1,
        toPage: 10,
        readAt: _jan1,
        durationSeconds: 600,
      );
      // Logged before the clock existed. Counting its pages against the ten
      // minutes above would report the reader as twice as fast as they are.
      await db.recordReading(
        logId: 'log-2',
        planId: 'plan-1',
        fromPage: 11,
        toPage: 20,
        readAt: DateTime(2026, 1, 2),
      );

      final pace = await db.watchReadingPace(planId: 'plan-1').first;

      expect(pace.pages, 10);
      expect(pace.perPage, const Duration(minutes: 1));
    });

    test('with no plan named, every book counts toward one speed', () async {
      await insertBook();
      await insertPlan();
      await insertBook(id: 'book-2', title: 'Other');
      await insertPlan(id: 'plan-2', bookId: 'book-2');

      await db.recordReading(
        logId: 'log-1',
        planId: 'plan-1',
        fromPage: 1,
        toPage: 10,
        readAt: _jan1,
        durationSeconds: 600,
      );
      await db.recordReading(
        logId: 'log-2',
        planId: 'plan-2',
        fromPage: 1,
        toPage: 10,
        readAt: _jan1,
        durationSeconds: 1200,
      );

      final pace = await db.watchReadingPace().first;

      expect(pace.pages, 20);
      expect(pace.time, const Duration(minutes: 30));
    });

    test('a window ignores reading from before it', () async {
      await insertBook();
      await insertPlan();

      await db.recordReading(
        logId: 'old',
        planId: 'plan-1',
        fromPage: 1,
        toPage: 10,
        readAt: _jan1,
        durationSeconds: 6000,
      );
      await db.recordReading(
        logId: 'recent',
        planId: 'plan-1',
        fromPage: 11,
        toPage: 20,
        readAt: DateTime(2026, 1, 20),
        durationSeconds: 600,
      );

      final pace = await db
          .watchReadingPace(from: DateTime(2026, 1, 15))
          .first;

      expect(pace.pages, 10);
      expect(pace.time, const Duration(minutes: 10));
    });

    test('a reader nobody has timed is unknown, not infinitely fast', () async {
      await insertBook();
      await insertPlan();

      expect(await db.watchReadingPace().first, ReadingPace.unknown);
    });
  });

  test('specOf round-trips a stored plan into plan arithmetic', () async {
    await insertBook();
    await insertPlan();

    final plan = await db.activePlanFor('book-1');
    final spec = db.specOf(plan!);

    expect(spec.totalPages, 100);
    expect(spec.pagesPerDay, 10);
    expect(
      nextAssignment(spec, plan.lastPageRead),
      const DayAssignment(fromPage: 1, toPage: 10),
    );
  });
}
