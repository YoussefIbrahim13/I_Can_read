import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:i_can_read/core/db/app_database.dart';
import 'package:i_can_read/core/files/book_file_store.dart';
import 'package:i_can_read/core/files/pdf_fingerprint.dart';
import 'package:i_can_read/core/planning/plan_math.dart';
import 'package:i_can_read/core/sync/sync_mappers.dart';
import 'package:i_can_read/features/add_book/data/book_importer.dart';
import 'package:i_can_read/features/relink/application/locate_file_controller.dart';

Uint8List _pdfBytes([String body = 'a book']) =>
    Uint8List.fromList(utf8.encode('%PDF-1.7\n$body\n%%EOF'));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory documents;
  late BookFileStore store;
  late AppDatabase db;
  late ProviderContainer container;

  /// The page count the stubbed engine reports for the next import, so a test
  /// can hand the flow a copy that is longer or shorter than the book on
  /// record without needing a real PDF.
  var reportedPageCount = 300;

  setUp(() async {
    documents = await Directory.systemTemp.createTemp('i_can_read_locate');
    store = BookFileStore(documents);
    db = AppDatabase(NativeDatabase.memory());
    reportedPageCount = 300;
    container = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        bookFileStoreProvider.overrideWithValue(store),
        bookImporterProvider.overrideWithValue(
          BookImporter(store, pageCounter: (_) async => reportedPageCount),
        ),
      ],
    );
  });

  tearDown(() async {
    container.dispose();
    await db.close();
    if (documents.existsSync()) await documents.delete(recursive: true);
  });

  LocateFileController controller() =>
      container.read(locateFileControllerProvider.notifier);

  LocateFileState currentState() =>
      container.read(locateFileControllerProvider);

  /// A book already in the library, hashed from [body].
  Future<String> addBook({
    required String id,
    String body = 'a book',
    int pageCount = 300,
  }) async {
    // The same hash the importer will compute for these bytes, so the fixture
    // and the flow agree on what "the original file" was.
    final path = await store.write(id, Stream.value(_pdfBytes(body)));
    final sha = await hashFile(store.resolve(path).path);

    await db.insertImportedBook(
      bookId: id,
      fingerprintId: '$id-fp',
      title: 'Book $id',
      pageCount: pageCount,
      sha256: sha,
      sizeBytes: 1,
      originalFileName: 'original.pdf',
      relativePath: path,
      now: DateTime(2026, 1, 1),
    );
    return id;
  }

  Future<String> addPlan(
    String bookId, {
    int startPage = 1,
    int endPage = 300,
    int lastPageRead = 0,
  }) async {
    final planId = await db.savePlan(
      bookId: bookId,
      spec: PlanSpec(
        mode: PlanMode.byPagesPerDay,
        startPage: startPage,
        endPage: endPage,
        startDate: DateTime(2026, 1, 1),
        targetEndDate: DateTime(2026, 2, 1),
        pagesPerDay: 10,
      ),
      now: DateTime(2026, 1, 1),
      newPlanId: '$bookId-plan',
    );
    await (db.update(db.readingPlans)..where((p) => p.id.equals(planId))).write(
      ReadingPlansCompanion(lastPageRead: Value(lastPageRead)),
    );
    return planId;
  }

  /// Puts the book in the state a new phone leaves it in: known, but with no
  /// file here.
  Future<void> forgetFile(String bookId) async {
    await (db.delete(
      db.localBookFiles,
    )..where((f) => f.bookId.equals(bookId))).go();
    final relative = store.relativePathFor(bookId);
    await store.delete(relative);
  }

  Future<void> offer(
    String bookId, {
    String body = 'a book',
    String fileName = 'redownloaded.pdf',
  }) {
    final bytes = _pdfBytes(body);
    return controller().offerFile(
      bookId: bookId,
      fileName: fileName,
      sizeBytes: bytes.length,
      openStream: () => Stream<Uint8List>.value(bytes),
    );
  }

  group('the same file again', () {
    test('links straight back with no questions asked', () async {
      await addBook(id: 'b1');
      await forgetFile('b1');

      await offer('b1');

      expect(currentState(), isA<LocateLinked>());
      expect(await db.hasLocalFile('b1'), isTrue);
      // One fingerprint, because nothing new was learned about the book.
      expect(await db.select(db.bookFingerprints).get(), hasLength(1));
    });
  });

  group('a file that belongs to another book', () {
    test('is refused, and the copy is not left behind', () async {
      await addBook(id: 'b1', body: 'the muqaddimah');
      await addBook(id: 'b2', body: 'another book');
      await forgetFile('b1');

      await offer('b1', body: 'another book');

      final state = currentState();
      expect(state, isA<LocateWrongBook>());
      expect((state as LocateWrongBook).owner.id, 'b2');

      expect(await db.hasLocalFile('b1'), isFalse);
      // b2's own file is untouched.
      expect(await store.exists(store.relativePathFor('b2')), isTrue);
      expect(await store.exists(store.relativePathFor('b1')), isFalse);
    });
  });

  group('a copy the book has never seen', () {
    test('waits for the reader to vouch for it', () async {
      await addBook(id: 'b1');
      await forgetFile('b1');

      await offer('b1', body: 'a different scan');

      final state = currentState();
      expect(state, isA<LocateUnrecognised>());
      expect((state as LocateUnrecognised).pageCountDiffers, isFalse);
      // Nothing is written until the reader answers.
      expect(await db.hasLocalFile('b1'), isFalse);
      expect(await db.select(db.bookFingerprints).get(), hasLength(1));
    });

    test('is linked with a second fingerprint once confirmed', () async {
      await addBook(id: 'b1');
      await forgetFile('b1');
      await offer('b1', body: 'a different scan');

      await controller().confirmUnrecognised();

      expect(currentState(), isA<LocateLinked>());
      expect(await db.hasLocalFile('b1'), isTrue);
      // Two now: the original copy has to keep relinking on the other phone.
      expect(await db.select(db.bookFingerprints).get(), hasLength(2));
    });

    test('declining it leaves no orphan PDF behind', () async {
      await addBook(id: 'b1');
      await forgetFile('b1');
      await offer('b1', body: 'a different scan');

      await controller().discardPending();

      expect(currentState(), isA<LocateIdle>());
      expect(await store.exists(store.relativePathFor('b1')), isFalse);
      expect(await db.hasLocalFile('b1'), isFalse);
    });
  });

  group('a copy with a different page count', () {
    setUp(() async {
      await addBook(id: 'b1', pageCount: 300);
      await addPlan('b1', startPage: 21, endPage: 300, lastPageRead: 150);
      await forgetFile('b1');
      reportedPageCount = 600;
      await offer('b1', body: 'a bigger scan');
    });

    test('is announced as a difference the reader has to answer', () {
      final state = currentState() as LocateUnrecognised;
      expect(state.pageCountDiffers, isTrue);
      expect(state.pdf.pageCount, 600);
      expect(state.recordedPageCount, 300);
    });

    test('keeping the numbers moves only what fell off the end', () async {
      await controller().confirmUnrecognised();

      final plan = (await db.select(db.readingPlans).get()).single;
      expect(plan.startPage, 21);
      expect(plan.endPage, 300);
      expect(plan.lastPageRead, 150);
      expect((await db.findBook('b1'))!.pageCount, 600);
    });

    test('rescaling moves the whole plan across', () async {
      await controller().confirmUnrecognised(rescaleProgress: true);

      final plan = (await db.select(db.readingPlans).get()).single;
      expect(plan.startPage, 42);
      expect(plan.endPage, 600);
      expect(plan.lastPageRead, 300);
      // The promise the reader made is untouched by the file they picked.
      expect(plan.pagesPerDay, 10);
    });

    test(
      'a shorter copy cannot leave the plan past its own last page',
      () async {
        // Start over with a copy that is shorter than the book on record.
        await controller().discardPending();
        reportedPageCount = 200;
        await offer('b1', body: 'an abridged scan');

        await controller().confirmUnrecognised();

        final plan = (await db.select(db.readingPlans).get()).single;
        expect(plan.endPage, 200);
        expect(plan.lastPageRead, 150);
        expect(plan.startPage, 21);
      },
    );

    test('the reading log is left exactly as it was', () async {
      final before = await db.select(db.readingLog).get();
      await controller().confirmUnrecognised(rescaleProgress: true);
      expect(await db.select(db.readingLog).get(), before);
    });

    test('queues the book and the plan for the server', () async {
      await db.clearOutbox();

      await controller().confirmUnrecognised(rescaleProgress: true);

      final queued = await db.pendingOutboxEntries();
      expect(
        queued.map((e) => e.entity),
        containsAll(<String>[
          SyncEntity.books,
          SyncEntity.plans,
          SyncEntity.fingerprints,
        ]),
      );
    });
  });

  group('a book that is gone', () {
    test('fails rather than importing into nothing', () async {
      await offer('missing-book');
      expect(currentState(), isA<LocateFailed>());
    });
  });
}
