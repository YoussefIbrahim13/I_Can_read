import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:i_can_read/core/files/book_file_store.dart';
import 'package:i_can_read/core/files/pdf_fingerprint.dart';
import 'package:i_can_read/features/add_book/data/book_importer.dart';
import 'package:path/path.dart' as p;

/// Minimal bytes that pass the signature check.
Uint8List _fakePdf([String body = 'test book']) =>
    Uint8List.fromList(utf8.encode('%PDF-1.7\n$body\n%%EOF'));

Stream<Uint8List> Function() _streamOf(Uint8List bytes) =>
    () => Stream<Uint8List>.value(bytes);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory documents;
  late BookFileStore store;

  setUp(() async {
    documents = await Directory.systemTemp.createTemp('i_can_read_test');
    store = BookFileStore(documents);
  });

  tearDown(() async {
    if (documents.existsSync()) await documents.delete(recursive: true);
  });

  group('BookFileStore', () {
    test('stores a device-independent relative path', () {
      // Must stay POSIX-style: the same string is read back on iOS, where the
      // container prefix differs but the suffix must not.
      expect(store.relativePathFor('abc-123'), 'books/abc-123.pdf');
    });

    test('resolves a relative path under the documents directory', () {
      final file = store.resolve('books/abc-123.pdf');
      expect(p.isWithin(documents.path, file.path), isTrue);
      expect(p.basename(file.path), 'abc-123.pdf');
    });

    test('writes the stream and creates the books directory', () async {
      final bytes = _fakePdf();
      final relativePath = await store.write('abc-123', _streamOf(bytes)());

      expect(await store.exists(relativePath), isTrue);
      expect(await store.resolve(relativePath).readAsBytes(), bytes);
    });

    test('leaves no partial file behind after a successful write', () async {
      await store.write('abc-123', _streamOf(_fakePdf())());

      final leftovers = Directory(p.join(documents.path, 'books'))
          .listSync()
          .map((e) => p.basename(e.path))
          .where((name) => name.endsWith('.part'));
      expect(leftovers, isEmpty);
    });

    test(
      'a failed write cleans up and does not publish a truncated file',
      () async {
        Stream<Uint8List> failing() async* {
          yield Uint8List.fromList([1, 2, 3]);
          throw const FileSystemException('source disappeared');
        }

        await expectLater(
          store.write('abc-123', failing()),
          throwsA(isA<FileSystemException>()),
        );

        expect(await store.exists('books/abc-123.pdf'), isFalse);
        final booksDir = Directory(p.join(documents.path, 'books'));
        expect(booksDir.listSync(), isEmpty);
      },
    );

    test('delete is a no-op when the file is already gone', () async {
      await store.delete('books/never-existed.pdf');
    });
  });

  group('hashFile', () {
    test('matches the known SHA-256 of its contents', () async {
      final file = File(p.join(documents.path, 'hello.txt'));
      await file.writeAsString('hello');

      expect(
        await hashFile(file.path),
        '2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824',
      );
    });

    test(
      'identical contents hash identically, different contents do not',
      () async {
        final a = File(p.join(documents.path, 'a.pdf'))
          ..writeAsBytesSync(_fakePdf());
        final b = File(p.join(documents.path, 'b.pdf'))
          ..writeAsBytesSync(_fakePdf());
        final c = File(p.join(documents.path, 'c.pdf'))
          ..writeAsBytesSync(_fakePdf('a different edition'));

        expect(await hashFile(a.path), await hashFile(b.path));
        expect(await hashFile(a.path), isNot(await hashFile(c.path)));
      },
    );

    test('handles a file large enough to span many chunks', () async {
      final file = File(p.join(documents.path, 'big.pdf'));
      final sink = file.openWrite();
      for (var i = 0; i < 200; i++) {
        sink.add(Uint8List(64 * 1024)..fillRange(0, 64 * 1024, i % 256));
      }
      await sink.close();

      final digest = await hashFile(file.path);
      expect(digest, hasLength(64));
      // Stable across runs, which is what makes it usable as an identity.
      expect(await hashFile(file.path), digest);
    });
  });

  group('BookImporter', () {
    test('imports a PDF and reports everything a book record needs', () async {
      final importer = BookImporter(store, pageCounter: (_) async => 342);
      final bytes = _fakePdf();

      final result = await importer.import(
        bookId: 'book-1',
        fileName: 'the-muqaddimah_vol2.pdf',
        sizeBytes: bytes.length,
        openStream: _streamOf(bytes),
      );

      expect(result.relativePath, 'books/book-1.pdf');
      expect(result.pageCount, 342);
      expect(result.sizeBytes, bytes.length);
      expect(result.originalFileName, 'the-muqaddimah_vol2.pdf');
      expect(result.suggestedTitle, 'the muqaddimah vol2');
      expect(
        result.sha256,
        await hashFile(store.resolve(result.relativePath).path),
      );
      expect(await store.exists(result.relativePath), isTrue);
    });

    test('reports each stage in order', () async {
      final importer = BookImporter(store, pageCounter: (_) async => 10);
      final stages = <ImportStage>[];

      await importer.import(
        bookId: 'book-1',
        fileName: 'book.pdf',
        sizeBytes: 20,
        openStream: _streamOf(_fakePdf()),
        onStage: stages.add,
      );

      expect(stages, [
        ImportStage.copying,
        ImportStage.hashing,
        ImportStage.readingPages,
      ]);
    });

    test('rejects a file that is not a PDF and keeps no copy', () async {
      final importer = BookImporter(store, pageCounter: (_) async => 10);
      final notAPdf = Uint8List.fromList(utf8.encode('PK zip file'));

      await expectLater(
        importer.import(
          bookId: 'book-1',
          fileName: 'archive.zip',
          sizeBytes: notAPdf.length,
          openStream: _streamOf(notAPdf),
        ),
        throwsA(
          isA<PdfImportException>().having(
            (e) => e.failure,
            'failure',
            PdfImportFailure.notAPdf,
          ),
        ),
      );

      expect(await store.exists('books/book-1.pdf'), isFalse);
    });

    test('rejects an empty file', () async {
      final importer = BookImporter(store, pageCounter: (_) async => 10);

      await expectLater(
        importer.import(
          bookId: 'book-1',
          fileName: 'empty.pdf',
          sizeBytes: 0,
          openStream: () => Stream<Uint8List>.value(Uint8List(0)),
        ),
        throwsA(isA<PdfImportException>()),
      );
      expect(await store.exists('books/book-1.pdf'), isFalse);
    });

    test('rejects a PDF the engine cannot open and keeps no copy', () async {
      final importer = BookImporter(
        store,
        pageCounter: (_) async => throw StateError('encrypted'),
      );

      await expectLater(
        importer.import(
          bookId: 'book-1',
          fileName: 'locked.pdf',
          sizeBytes: 20,
          openStream: _streamOf(_fakePdf()),
        ),
        throwsA(
          isA<PdfImportException>().having(
            (e) => e.failure,
            'failure',
            PdfImportFailure.unreadable,
          ),
        ),
      );

      expect(await store.exists('books/book-1.pdf'), isFalse);
    });

    test('rejects a PDF that reports no pages', () async {
      final importer = BookImporter(store, pageCounter: (_) async => 0);

      await expectLater(
        importer.import(
          bookId: 'book-1',
          fileName: 'blank.pdf',
          sizeBytes: 20,
          openStream: _streamOf(_fakePdf()),
        ),
        throwsA(isA<PdfImportException>()),
      );
      expect(await store.exists('books/book-1.pdf'), isFalse);
    });

    test('the same file imported twice produces the same hash', () async {
      final importer = BookImporter(store, pageCounter: (_) async => 42);
      final bytes = _fakePdf();

      final first = await importer.import(
        bookId: 'book-1',
        fileName: 'book.pdf',
        sizeBytes: bytes.length,
        openStream: _streamOf(bytes),
      );
      final second = await importer.import(
        bookId: 'book-2',
        fileName: 'a copy of book.pdf',
        sizeBytes: bytes.length,
        openStream: _streamOf(bytes),
      );

      // This equality is what the cross-device relink flow depends on.
      expect(first.sha256, second.sha256);
      expect(first.relativePath, isNot(second.relativePath));
    });
  });

  group('titleFromFileName', () {
    test('cleans separators and extensions', () {
      expect(titleFromFileName('the-muqaddimah.pdf'), 'the muqaddimah');
      expect(titleFromFileName('ibn_khaldun__vol_2.pdf'), 'ibn khaldun vol 2');
      expect(titleFromFileName('  spaced   out .pdf'), 'spaced out');
    });

    test('keeps Arabic file names intact', () {
      expect(titleFromFileName('مقدمة_ابن_خلدون.pdf'), 'مقدمة ابن خلدون');
    });

    test('falls back to the raw name when nothing is left', () {
      expect(titleFromFileName('.pdf'), '.pdf');
    });
  });
}
