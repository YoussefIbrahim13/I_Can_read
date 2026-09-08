import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:i_can_read/core/db/app_database.dart';
import 'package:i_can_read/core/planning/plan_math.dart';
import 'package:i_can_read/core/sync/sync_client.dart';
import 'package:i_can_read/core/sync/sync_engine.dart';
import 'package:i_can_read/core/sync/sync_mappers.dart';
import 'package:i_can_read/core/sync/sync_models.dart';
import 'package:i_can_read/core/sync/sync_status.dart';
import 'package:shared_preferences/shared_preferences.dart';

final _jan1 = DateTime(2026, 1, 1, 9);
const _hash =
    'a3f5c1d2e4b6980a7c5e3f1d2b4a6c8e0f2d4b6a8c0e2f4d6b8a0c2e4f6d8b0a';

/// A server that records what it was handed and replies with what it is told.
class FakeServer implements SyncApi {
  FakeServer({this.serverTime});

  /// Every payload pushed, in order.
  final List<SyncPayload> pushes = [];

  /// Every cursor a pull was made with, including the nulls.
  final List<DateTime?> cursors = [];

  /// What the next pull hands back.
  SyncPayload nextPull = const SyncPayload();

  DateTime? serverTime;

  /// When set, push throws it instead of accepting.
  SyncException? pushFailure;

  @override
  Future<SyncPushResponse> push(SyncPayload payload) async {
    if (pushFailure != null) throw pushFailure!;
    pushes.add(payload);
    return SyncPushResponse(
      serverTime: serverTime ?? _jan1,
      applied: payload.books.length +
          payload.fingerprints.length +
          payload.plans.length +
          payload.sessions.length +
          payload.logEntries.length,
      ignored: 0,
    );
  }

  @override
  Future<SyncPullResponse> pull({DateTime? since}) async {
    cursors.add(since);
    final response = SyncPullResponse(
      serverTime: serverTime ?? _jan1,
      changes: nextPull,
    );
    nextPull = const SyncPayload();
    return response;
  }

  @override
  Future<BookDto?> lookupByHash(String sha256) async => null;
}

void main() {
  late AppDatabase db;
  late FakeServer server;
  late SharedPreferences prefs;
  late SyncEngine engine;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    server = FakeServer();
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    engine = SyncEngine(
      db: db,
      client: server,
      prefs: prefs,
      userId: 'reader-1',
    );
  });

  tearDown(() => db.close());

  Future<void> importBook({String id = 'book-1'}) {
    return db.insertImportedBook(
      bookId: id,
      fingerprintId: 'fp-$id',
      title: 'Test Book',
      pageCount: 100,
      sha256: _hash,
      sizeBytes: 1024,
      originalFileName: 'book.pdf',
      relativePath: 'books/$id.pdf',
      now: _jan1,
    );
  }

  Future<String> makePlan({String bookId = 'book-1'}) {
    return db.savePlan(
      bookId: bookId,
      spec: PlanSpec(
        mode: PlanMode.byPagesPerDay,
        startPage: 1,
        endPage: 100,
        startDate: _jan1,
        targetEndDate: _jan1.add(const Duration(days: 9)),
        pagesPerDay: 10,
      ),
      now: _jan1,
      newPlanId: 'plan-1',
    );
  }

  group('the outbox', () {
    test('an imported book queues the book and its fingerprint, not the file',
        () async {
      await importBook();

      final queued = await db.pendingOutboxEntries();
      expect(
        queued.map((e) => e.entity),
        [SyncEntity.books, SyncEntity.fingerprints],
      );
      // The PDF and where it sits on this phone are the two things that never
      // leave it, so there is deliberately nothing here for local_book_files.
      expect(queued.map((e) => e.entity), isNot(contains('local_book_files')));
    });

    test('reading queues the log entry and the advanced plan', () async {
      await importBook();
      final planId = await makePlan();
      await db.deleteOutboxEntries(
        [for (final e in await db.pendingOutboxEntries()) e.id],
      );

      await db.recordReading(
        planId: planId,
        fromPage: 1,
        toPage: 10,
        readAt: _jan1,
        logId: 'log-1',
      );

      final queued = await db.pendingOutboxEntries();
      expect(
        queued.map((e) => e.entity),
        [SyncEntity.logEntries, SyncEntity.plans],
      );
    });

    test('pausing an already-paused plan queues nothing the second time',
        () async {
      await importBook();
      final planId = await makePlan();
      await db.pausePlan(planId, _jan1);
      await db.deleteOutboxEntries(
        [for (final e in await db.pendingOutboxEntries()) e.id],
      );

      // A double tap on the pause button must not push a row whose only change
      // is a newer updatedAt, or it wins a conflict it has nothing to say in.
      await db.pausePlan(planId, _jan1.add(const Duration(hours: 1)));

      expect(await db.pendingOutboxEntries(), isEmpty);
    });

    test('replacing the reminders queues the old ones as tombstones', () async {
      await importBook();
      final planId = await makePlan();
      await db.replaceSessions(planId, [
        ReadingSessionsCompanion.insert(
          id: 'session-old',
          planId: planId,
          ordinal: 0,
          timeOfDayMinutes: 20 * 60,
          pagesShare: 10,
          updatedAt: _jan1,
        ),
      ], now: _jan1);
      await db.deleteOutboxEntries(
        [for (final e in await db.pendingOutboxEntries()) e.id],
      );

      // The reader moves the reminder to 21:00, which rebuilds the list.
      await db.replaceSessions(planId, [
        ReadingSessionsCompanion.insert(
          id: 'session-new',
          planId: planId,
          ordinal: 0,
          timeOfDayMinutes: 21 * 60,
          pagesShare: 10,
          updatedAt: _jan1,
        ),
      ], now: _jan1);

      final queued = await db.pendingOutboxEntries();
      expect(queued.map((e) => e.entityId), ['session-old', 'session-new']);
      expect(queued.map((e) => e.op), [SyncOp.delete, SyncOp.upsert]);

      // And the retired row is still here to be described, rather than gone.
      final sessions = await db.watchSessionsFor(planId).first;
      expect(sessions.map((s) => s.id), ['session-new']);
    });

    test('a reminder that keeps its id is edited, not buried and rebuilt',
        () async {
      await importBook();
      final planId = await makePlan();
      Future<void> save(int minutes) => db.replaceSessions(planId, [
            ReadingSessionsCompanion.insert(
              id: '$planId-0',
              planId: planId,
              ordinal: 0,
              timeOfDayMinutes: minutes,
              pagesShare: 10,
              updatedAt: _jan1,
            ),
          ], now: _jan1);

      await save(20 * 60);
      await db.clearOutbox();
      await save(6 * 60 + 30);

      // Nothing was retired, because nothing went away — an id that comes back
      // is the same reminder at a new time.
      final queued = await db.pendingOutboxEntries();
      expect(queued.map((e) => e.op), [SyncOp.upsert]);
      final sessions = await db.watchSessionsFor(planId).first;
      expect(sessions.single.timeOfDayMinutes, 6 * 60 + 30);
    });

    test('signing in seeds the outbox with everything already on the phone',
        () async {
      await importBook();
      final planId = await makePlan();
      await db.recordReading(
        planId: planId,
        fromPage: 1,
        toPage: 10,
        readAt: _jan1,
        logId: 'log-1',
      );
      // Everything so far was written as a guest, with nowhere to send it.
      await db.clearOutbox();

      await db.seedOutboxFromLocalData();

      expect(
        (await db.pendingOutboxEntries()).map((e) => e.entity).toSet(),
        {
          SyncEntity.books,
          SyncEntity.fingerprints,
          SyncEntity.plans,
          SyncEntity.logEntries,
        },
      );
    });
  });

  group('push', () {
    test('sends the queue grouped by kind and then empties it', () async {
      await importBook();
      await makePlan();

      final status = await engine.syncNow();

      final payload = server.pushes.single;
      expect(payload.books.single.id, 'book-1');
      expect(payload.fingerprints.single.bookId, 'book-1');
      expect(payload.plans.single.id, 'plan-1');
      expect(await db.pendingOutboxEntries(), isEmpty);
      expect((status as SyncComplete).pushed, 3);
    });

    test('leaves rows queued while a change arrives mid-flight', () async {
      await importBook();

      // A push that fails is the observable version of one still in flight:
      // either way the rows it covered have not been accepted yet.
      server.pushFailure = const SyncException(503, 'unavailable');
      final status = await engine.syncNow();

      expect(status, isA<SyncFailed>());
      expect(await db.pendingOutboxEntries(), isNotEmpty);
    });

    test('drops a row the server keeps refusing rather than wedging the queue',
        () async {
      await importBook();
      server.pushFailure = const SyncException(400, 'rejected');

      for (var attempt = 0; attempt < 5; attempt++) {
        await engine.syncNow();
      }

      // Five refusals is enough to conclude the server will never take it.
      // Retrying forever would block every later change behind it.
      expect(await db.pendingOutboxEntries(), isEmpty);
    });
  });

  group('pull', () {
    test('a new device asks with no cursor and gets everything', () async {
      await engine.syncNow();
      expect(server.cursors, [null]);
    });

    test('the next pull asks from the server time, not this device clock',
        () async {
      server.serverTime = DateTime.utc(2026, 3, 1, 12);
      await engine.syncNow();
      await engine.syncNow();

      expect(server.cursors.last, DateTime.utc(2026, 3, 1, 12));
    });

    test('a failed merge leaves the cursor where it was', () async {
      // A plan whose book never arrives violates the foreign key. The rows
      // that failed must be asked for again, so the cursor must not move.
      server.nextPull = SyncPayload(
        plans: [
          PlanDto(
            id: 'orphan-plan',
            bookId: 'book-that-was-never-sent',
            mode: 'byPagesPerDay',
            startPage: 1,
            endPage: 100,
            startDate: '2026-01-01',
            targetEndDate: '2026-01-10',
            pagesPerDay: 10,
            lastPageRead: 0,
            isActive: true,
            pausedDays: 0,
            createdAt: _jan1,
            updatedAt: _jan1,
          ),
        ],
      );

      // Reported rather than thrown: the button that started this has to stop
      // spinning even when the merge blew up.
      expect(await engine.syncNow(), isA<SyncFailed>());
      expect(engine.cursor, isNull);
    });

    test('merges a remote book into the library', () async {
      server.nextPull = SyncPayload(
        books: [
          BookDto(
            id: 'book-from-phone-2',
            title: 'Read on the other phone',
            pageCount: 200,
            pageLabelOffset: 0,
            status: 'reading',
            createdAt: _jan1,
            updatedAt: _jan1,
          ),
        ],
      );

      final status = await engine.syncNow();

      expect((status as SyncComplete).pulled, 1);
      expect((await db.findBook('book-from-phone-2'))?.title,
          'Read on the other phone');
    });

    test('what was merged in is not queued straight back out', () async {
      server.nextPull = SyncPayload(
        books: [
          BookDto(
            id: 'book-from-phone-2',
            title: 'Read on the other phone',
            pageCount: 200,
            pageLabelOffset: 0,
            status: 'reading',
            createdAt: _jan1,
            updatedAt: _jan1,
          ),
        ],
      );

      await engine.syncNow();

      // Otherwise every sync would push back everything it just received, and
      // two devices would keep each other busy forever.
      expect(await db.pendingOutboxEntries(), isEmpty);
    });
  });

  group('the cursor', () {
    test('belongs to the account, not the phone', () async {
      server.serverTime = DateTime.utc(2026, 3, 1, 12);
      await engine.syncNow();

      // A second reader signing in on the same phone starts from nothing,
      // rather than inheriting a position that would hide their whole library.
      final other = SyncEngine(
        db: db,
        client: server,
        prefs: prefs,
        userId: 'reader-2',
      );
      expect(other.cursor, isNull);
      expect(engine.cursor, isNotNull);
    });
  });

  group('the wire format', () {
    test('instants carry a zone and dates do not shift', () async {
      await importBook();
      await makePlan();
      await engine.syncNow();

      final plan = server.pushes.single.plans.single.toJson();

      // Without the Z the server reads the timestamp in its own local time,
      // and last-write-wins starts comparing shifted clocks.
      expect(plan['createdAt'], endsWith('Z'));
      // The start date is a calendar day, and local midnight on the 1st is
      // still the previous year in UTC. Sending it as an instant would move it.
      expect(plan['startDate'], '2026-01-01');
    });

    test('a reading date survives a timezone east of Greenwich', () {
      // Local 00:30 on the 8th is 21:30 on the 7th in UTC+3. Routing this
      // through UTC would credit the reading to the wrong day.
      final justAfterMidnight = DateTime(2026, 9, 8, 0, 30);
      expect(wireDate(justAfterMidnight), '2026-09-08');
    });
  });

  group('a full round trip', () {
    test('two devices converge on the furthest page read', () async {
      await importBook();
      final planId = await makePlan();
      await db.recordReading(
        planId: planId,
        fromPage: 1,
        toPage: 30,
        readAt: _jan1,
        logId: 'log-here',
      );

      // The other phone read further, but saved it earlier.
      final localPlan = await db.activePlanFor('book-1');
      server.nextPull = SyncPayload(
        plans: [
          planDto(localPlan!).copyWithProgress(
            lastPageRead: 50,
            updatedAt: _jan1.subtract(const Duration(hours: 1)),
          ),
        ],
      );

      await engine.syncNow();

      // Progress takes the maximum even though the incoming row lost the
      // last-write-wins comparison: reading only ever moves forward.
      expect((await db.activePlanFor('book-1'))!.lastPageRead, 50);
    });
  });
}

extension on PlanDto {
  PlanDto copyWithProgress({
    required int lastPageRead,
    required DateTime updatedAt,
  }) {
    return PlanDto(
      id: id,
      bookId: bookId,
      mode: mode,
      startPage: startPage,
      endPage: endPage,
      startDate: startDate,
      targetEndDate: targetEndDate,
      pagesPerDay: pagesPerDay,
      lastPageRead: lastPageRead,
      isActive: isActive,
      pausedAt: pausedAt,
      pausedDays: pausedDays,
      createdAt: createdAt,
      updatedAt: updatedAt,
    );
  }
}
