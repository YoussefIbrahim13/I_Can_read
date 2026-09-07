import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:i_can_read/core/db/app_database.dart';
import 'package:i_can_read/core/files/book_file_store.dart';
import 'package:i_can_read/features/add_book/application/add_book_controller.dart';
import 'package:i_can_read/features/add_book/data/book_importer.dart';

Uint8List _pdfBytes([String body = 'a book']) =>
    Uint8List.fromList(utf8.encode('%PDF-1.7\n$body\n%%EOF'));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory documents;
  late BookFileStore store;
  late AppDatabase db;
  late ProviderContainer container;

  /// Builds a container whose PDF page count is stubbed, so no native engine is
  /// needed. The real engine is covered by `integration_test/`.
  ProviderContainer buildContainer({int pageCount = 300}) {
    return ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        bookFileStoreProvider.overrideWithValue(store),
        bookImporterProvider.overrideWithValue(
          BookImporter(store, pageCounter: (_) async => pageCount),
        ),
      ],
    );
  }

  setUp(() async {
    documents = await Directory.systemTemp.createTemp('i_can_read_addbook');
    store = BookFileStore(documents);
    db = AppDatabase(NativeDatabase.memory());
    container = buildContainer();
  });

  tearDown(() async {
    container.dispose();
    await db.close();
    if (documents.existsSync()) await documents.delete(recursive: true);
  });

  AddBookController controller() =>
      container.read(addBookControllerProvider.notifier);

  AddBookState currentState() => container.read(addBookControllerProvider);

  Future<void> importBytes(
    Uint8List bytes, {
    String fileName = 'ibn-khaldun.pdf',
  }) {
    return controller().importPicked(
      fileName: fileName,
      sizeBytes: bytes.length,
      openStream: () => Stream<Uint8List>.value(bytes),
    );
  }

  group('importing', () {
    test('a new PDF becomes ready to name', () async {
      await importBytes(_pdfBytes());

      final state = currentState();
      expect(state, isA<AddBookReady>());
      final ready = state as AddBookReady;
      expect(ready.pdf.pageCount, 300);
      expect(ready.pdf.suggestedTitle, 'ibn khaldun');
      expect(await store.exists(ready.pdf.relativePath), isTrue);
    });

    test('reports progress stages while importing', () async {
      final seen = <ImportStage>[];
      container.listen(addBookControllerProvider, (_, next) {
        if (next is AddBookImporting) seen.add(next.stage);
      });

      await importBytes(_pdfBytes());

      expect(seen, contains(ImportStage.hashing));
      expect(seen, contains(ImportStage.readingPages));
    });

    test('a non-PDF fails without leaving a copy', () async {
      await importBytes(Uint8List.fromList(utf8.encode('PK not a pdf')));

      expect(
        currentState(),
        isA<AddBookFailed>().having(
          (s) => s.failure,
          'failure',
          PdfImportFailure.notAPdf,
        ),
      );
      final booksDir = Directory('${documents.path}/books');
      expect(booksDir.existsSync() ? booksDir.listSync() : [], isEmpty);
    });
  });

  group('saving', () {
    test('writes the book, its fingerprint and its local file', () async {
      await importBytes(_pdfBytes());
      final ready = currentState() as AddBookReady;

      await controller().save(
        title: '  مقدمة ابن خلدون  ',
        author: ' ابن خلدون ',
      );

      final book = await db.findBook(ready.bookId);
      expect(book!.title, 'مقدمة ابن خلدون');
      expect(book.author, 'ابن خلدون');
      expect(book.pageCount, 300);
      expect(book.status, BookStatus.reading);

      expect(await db.findBookByFileHash(ready.pdf.sha256), isNotNull);
      expect(await db.hasLocalFile(ready.bookId), isTrue);
      expect(currentState(), isA<AddBookSaved>());
    });

    test(
      'a blank author is stored as absent, not as an empty string',
      () async {
        await importBytes(_pdfBytes());
        final ready = currentState() as AddBookReady;

        await controller().save(title: 'A Book', author: '   ');

        expect((await db.findBook(ready.bookId))!.author, isNull);
      },
    );

    test('saving does nothing unless an import is ready', () async {
      await controller().save(title: 'Nothing');

      expect(await db.select(db.books).get(), isEmpty);
      expect(currentState(), isA<AddBookIdle>());
    });
  });

  group('a file already in the library', () {
    setUp(() async {
      await importBytes(_pdfBytes());
      await controller().save(title: 'The Muqaddimah');
      controller().reset();
    });

    test('is recognised and the redundant copy is discarded', () async {
      final before = Directory('${documents.path}/books').listSync().length;

      await importBytes(_pdfBytes(), fileName: 'a copy.pdf');

      final state = currentState();
      expect(state, isA<AddBookDuplicate>());
      expect((state as AddBookDuplicate).existing.title, 'The Muqaddimah');
      expect(state.relinked, isFalse);

      // No second book, and no second copy of identical bytes on disk.
      expect(await db.select(db.books).get(), hasLength(1));
      expect(
        Directory('${documents.path}/books').listSync(),
        hasLength(before),
      );
    });

    test('relinks instead when the device no longer has the file', () async {
      // Simulate the new-device case: the book is known, the file is not here.
      await (db.delete(db.localBookFiles)).go();

      await importBytes(_pdfBytes(), fileName: 'redownloaded.pdf');

      final state = currentState();
      expect(state, isA<AddBookDuplicate>());
      expect((state as AddBookDuplicate).relinked, isTrue);

      final book = (await db.select(db.books).get()).single;
      expect(await db.hasLocalFile(book.id), isTrue);
      expect(await db.select(db.books).get(), hasLength(1));
    });

    test('an unavailable file is relinked rather than duplicated', () async {
      await db
          .update(db.localBookFiles)
          .write(const LocalBookFilesCompanion(isAvailable: Value(false)));

      await importBytes(_pdfBytes());

      expect((currentState() as AddBookDuplicate).relinked, isTrue);
      final book = (await db.select(db.books).get()).single;
      expect(await db.hasLocalFile(book.id), isTrue);
    });

    test('a genuinely different file is added as its own book', () async {
      await importBytes(_pdfBytes('a different scan'), fileName: 'other.pdf');

      expect(currentState(), isA<AddBookReady>());
      await controller().save(title: 'Another Book');
      expect(await db.select(db.books).get(), hasLength(2));
    });
  });

  group('abandoning the flow', () {
    test('discarding removes the copied file and resets', () async {
      await importBytes(_pdfBytes());
      final ready = currentState() as AddBookReady;

      await controller().discardPending();

      expect(await store.exists(ready.pdf.relativePath), isFalse);
      expect(currentState(), isA<AddBookIdle>());
      expect(await db.select(db.books).get(), isEmpty);
    });

    test('discarding is harmless when nothing is pending', () async {
      await controller().discardPending();
      expect(currentState(), isA<AddBookIdle>());
    });
  });
}
