import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:i_can_read/core/db/app_database.dart';
import 'package:i_can_read/core/planning/plan_math.dart';
import 'package:i_can_read/core/sync/sync_models.dart';
import 'package:i_can_read/features/backup/domain/backup_file.dart';

final _jan1 = DateTime(2026, 1, 1);

void main() {
  group('the file format', () {
    test('survives a round trip', () {
      final data = SyncPayload(
        books: [
          BookDto(
            id: 'book-1',
            title: 'The Muqaddimah',
            author: 'Ibn Khaldun',
            pageCount: 300,
            pageLabelOffset: 0,
            status: 'reading',
            createdAt: _jan1,
            updatedAt: _jan1,
            deletedAt: null,
          ),
        ],
      );

      final restored = decodeBackup(encodeBackup(data, createdAt: _jan1));

      expect(restored.books.single.title, 'The Muqaddimah');
      expect(restored.books.single.author, 'Ibn Khaldun');
      expect(restored.books.single.pageCount, 300);
    });

    test('refuses a file that is not ours', () {
      expect(
        () => decodeBackup('{"format":"someone-elses-app","data":{}}'),
        throwsA(
          isA<BackupException>().having(
            (e) => e.problem,
            'problem',
            BackupProblem.notABackup,
          ),
        ),
      );
    });

    test('refuses something that is not even JSON', () {
      expect(
        () => decodeBackup('%PDF-1.7 this is a book, not a backup'),
        throwsA(isA<BackupException>()),
      );
    });

    test('refuses a file from a newer app rather than guessing', () {
      final fromTheFuture = jsonEncode({
        'format': 'i_can_read.backup',
        'formatVersion': backupFormatVersion + 1,
        'createdAt': '2026-01-01T00:00:00.000Z',
        'data': const <String, dynamic>{},
      });

      expect(
        () => decodeBackup(fromTheFuture),
        throwsA(
          isA<BackupException>().having(
            (e) => e.problem,
            'problem',
            BackupProblem.tooNew,
          ),
        ),
      );
    });

    test('names the file by the day it was written', () {
      expect(
        backupFileName(DateTime(2026, 3, 9)),
        'yaqra-backup-2026-03-09.json',
      );
    });
  });

  group('what a backup holds', () {
    late AppDatabase db;

    setUp(() => db = AppDatabase(NativeDatabase.memory()));
    tearDown(() => db.close());

    Future<void> addLibrary() async {
      await db.insertImportedBook(
        bookId: 'book-1',
        fingerprintId: 'fp-1',
        title: 'The Muqaddimah',
        author: 'Ibn Khaldun',
        pageCount: 300,
        sha256: 'a' * 64,
        sizeBytes: 1024,
        originalFileName: 'book.pdf',
        relativePath: 'books/book-1.pdf',
        now: _jan1,
      );
      await db.savePlan(
        bookId: 'book-1',
        spec: PlanSpec(
          mode: PlanMode.byPagesPerDay,
          startPage: 1,
          endPage: 300,
          startDate: _jan1,
          targetEndDate: DateTime(2026, 2, 1),
          pagesPerDay: 10,
        ),
        now: _jan1,
        newPlanId: 'plan-1',
      );
      await db.replaceSessions('plan-1', [
        ReadingSessionsCompanion.insert(
          id: 'session-1',
          planId: 'plan-1',
          ordinal: 0,
          timeOfDayMinutes: 20 * 60,
          pagesShare: 10,
          updatedAt: _jan1,
        ),
      ]);
      await db.recordReading(
        planId: 'plan-1',
        fromPage: 1,
        toPage: 10,
        readAt: DateTime(2026, 1, 2, 20),
        logId: 'log-1',
      );
    }

    test('carries the library, the plan and the reading', () async {
      await addLibrary();

      final data = await db.exportLocalData();

      expect(data.books.single.title, 'The Muqaddimah');
      expect(data.fingerprints.single.sha256, 'a' * 64);
      expect(data.plans.single.pagesPerDay, 10);
      expect(data.sessions.single.timeOfDayMinutes, 20 * 60);
      expect(data.logEntries.single.pagesRead, 10);
    });

    test('carries removals, so a restore does not resurrect them', () async {
      await addLibrary();
      await db.deleteBook('book-1', DateTime(2026, 1, 3));

      final data = await db.exportLocalData();

      expect(data.books.single.deletedAt, isNotNull);
    });

    test('holds nothing about where the file sits on this phone', () async {
      await addLibrary();

      final json = encodeBackup(await db.exportLocalData(), createdAt: _jan1);

      // The path is device-local and means nothing on the next phone — and the
      // PDF itself is the one thing this app never copies anywhere.
      expect(json.contains('books/book-1.pdf'), isFalse);
      expect(json.contains('relativePath'), isFalse);
    });
  });

  group('restoring', () {
    late AppDatabase source;
    late AppDatabase target;

    setUp(() {
      source = AppDatabase(NativeDatabase.memory());
      target = AppDatabase(NativeDatabase.memory());
    });

    tearDown(() async {
      await source.close();
      await target.close();
    });

    Future<void> seed(AppDatabase db, {int lastPageRead = 0}) async {
      await db.insertImportedBook(
        bookId: 'book-1',
        fingerprintId: 'fp-1',
        title: 'The Muqaddimah',
        pageCount: 300,
        sha256: 'a' * 64,
        sizeBytes: 1024,
        originalFileName: 'book.pdf',
        relativePath: 'books/book-1.pdf',
        now: _jan1,
      );
      await db.savePlan(
        bookId: 'book-1',
        spec: PlanSpec(
          mode: PlanMode.byPagesPerDay,
          startPage: 1,
          endPage: 300,
          startDate: _jan1,
          targetEndDate: DateTime(2026, 2, 1),
          pagesPerDay: 10,
        ),
        now: _jan1,
        newPlanId: 'plan-1',
      );
      await (db.update(db.readingPlans)..where((p) => p.id.equals('plan-1')))
          .write(ReadingPlansCompanion(lastPageRead: Value(lastPageRead)));
    }

    /// The whole trip: export one phone, write the file, read it on another.
    Future<void> restoreOnto(AppDatabase db) async {
      final file = encodeBackup(
        await source.exportLocalData(),
        createdAt: _jan1,
      );
      await db.importBackup(decodeBackup(file));
    }

    test('puts a library onto a phone that had none', () async {
      await seed(source, lastPageRead: 120);

      await restoreOnto(target);

      expect((await target.findBook('book-1'))!.title, 'The Muqaddimah');
      expect((await target.activePlanFor('book-1'))!.lastPageRead, 120);
      // The file is not part of a backup, so the book arrives needing one.
      expect(await target.hasLocalFile('book-1'), isFalse);
    });

    test('never walks progress backwards', () async {
      await seed(source, lastPageRead: 40);
      await seed(target, lastPageRead: 120);

      await restoreOnto(target);

      // Restoring an older backup onto a phone that has been read on since
      // must not throw that reading away.
      expect((await target.activePlanFor('book-1'))!.lastPageRead, 120);
    });

    test('is idempotent — restoring twice changes nothing', () async {
      await seed(source, lastPageRead: 50);

      await restoreOnto(target);
      await restoreOnto(target);

      expect(await target.select(target.books).get(), hasLength(1));
      expect(await target.select(target.readingPlans).get(), hasLength(1));
      expect(await target.select(target.bookFingerprints).get(), hasLength(1));
    });

    test('leaves a book the backup never heard of alone', () async {
      await seed(source);
      await target.insertImportedBook(
        bookId: 'book-2',
        fingerprintId: 'fp-2',
        title: 'A Book Added Since',
        pageCount: 100,
        sha256: 'b' * 64,
        sizeBytes: 10,
        originalFileName: 'other.pdf',
        relativePath: 'books/book-2.pdf',
        now: DateTime(2026, 2, 1),
      );

      await restoreOnto(target);

      expect(await target.select(target.books).get(), hasLength(2));
      expect((await target.findBook('book-2'))!.title, 'A Book Added Since');
    });

    test('keeps every reading-log entry from both phones', () async {
      await seed(source);
      await seed(target);
      await source.recordReading(
        planId: 'plan-1',
        fromPage: 1,
        toPage: 10,
        readAt: DateTime(2026, 1, 2, 20),
        logId: 'log-source',
      );
      await target.recordReading(
        planId: 'plan-1',
        fromPage: 11,
        toPage: 20,
        readAt: DateTime(2026, 1, 3, 20),
        logId: 'log-target',
      );

      await restoreOnto(target);

      // The log is append-only: it is the record of what actually happened, and
      // a merge that dropped either day would be rewriting it.
      final ids = (await target.select(target.readingLog).get())
          .map((entry) => entry.id)
          .toSet();
      expect(ids, {'log-source', 'log-target'});
    });
  });
}
