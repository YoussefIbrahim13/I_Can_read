import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:i_can_read/core/files/book_file_store.dart';
import 'package:i_can_read/features/add_book/data/book_importer.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path/path.dart' as p;

import 'support/minimal_pdf.dart';

/// Exercises the real PDF engine instead of a stubbed page counter.
///
/// This is the integration everything else rests on: if page counts are wrong,
/// every plan derived from them is wrong. It lives here rather than in `test/`
/// because `pdfrxFlutterInitialize` needs platform plugins that the host test
/// VM does not provide.
///
/// Run with: `flutter test integration_test/pdf_engine_test.dart -d windows`
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late Directory documents;
  late BookFileStore store;

  setUp(() async {
    documents = await Directory.systemTemp.createTemp('i_can_read_engine');
    store = BookFileStore(documents);
  });

  tearDown(() async {
    if (documents.existsSync()) await documents.delete(recursive: true);
  });

  Future<File> writePdf(String name, int pageCount) async {
    final file = File(p.join(documents.path, name));
    await file.writeAsBytes(minimalPdf(pageCount: pageCount));
    return file;
  }

  testWidgets('counts the pages of a real PDF', (tester) async {
    final file = await writePdf('sample.pdf', 7);
    expect(await countPdfPages(file.path), 7);
  });

  testWidgets('counts a single-page PDF', (tester) async {
    final file = await writePdf('one.pdf', 1);
    expect(await countPdfPages(file.path), 1);
  });

  testWidgets('counts a book-sized PDF', (tester) async {
    final file = await writePdf('book.pdf', 512);
    expect(await countPdfPages(file.path), 512);
  });

  testWidgets('a full import reads the page count from the engine', (
    tester,
  ) async {
    final bytes = minimalPdf(pageCount: 123);
    final importer = BookImporter(store);

    final result = await importer.import(
      bookId: 'book-1',
      fileName: 'مقدمة_ابن_خلدون.pdf',
      sizeBytes: bytes.length,
      openStream: () => Stream.value(bytes),
    );

    expect(result.pageCount, 123);
    expect(result.suggestedTitle, 'مقدمة ابن خلدون');
    expect(result.sha256, hasLength(64));
    expect(await store.exists(result.relativePath), isTrue);
  });

  testWidgets('a corrupt PDF is rejected and leaves no copy behind', (
    tester,
  ) async {
    // Keep the %PDF header so the cheap signature check passes and the engine
    // is what has to reject it.
    final corrupt = minimalPdf(pageCount: 5).sublist(0, 20);
    final importer = BookImporter(store);

    await expectLater(
      importer.import(
        bookId: 'book-1',
        fileName: 'broken.pdf',
        sizeBytes: corrupt.length,
        openStream: () => Stream.value(corrupt),
      ),
      throwsA(isA<PdfImportException>()),
    );
    expect(await store.exists('books/book-1.pdf'), isFalse);
  });
}
