import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:i_can_read/core/db/app_database.dart';
import 'package:i_can_read/core/files/book_file_store.dart';
import 'package:i_can_read/core/files/pdf_fingerprint.dart';
import 'package:i_can_read/core/theme/app_theme.dart';
import 'package:i_can_read/features/add_book/data/book_importer.dart';
import 'package:i_can_read/features/relink/application/locate_file_controller.dart';
import 'package:i_can_read/features/relink/presentation/locate_file_screen.dart';
import 'package:i_can_read/l10n/app_localizations.dart';

final _jan1 = DateTime(2026, 1, 1);

Uint8List _pdfBytes(String body) =>
    Uint8List.fromList(utf8.encode('%PDF-1.7\n$body\n%%EOF'));

void main() {
  late Directory documents;
  late BookFileStore store;
  late AppDatabase db;
  late ProviderContainer container;
  var reportedPageCount = 240;

  setUp(() async {
    documents = await Directory.systemTemp.createTemp('i_can_read_locate_ui');
    store = BookFileStore(documents);
    db = AppDatabase(NativeDatabase.memory());
    reportedPageCount = 240;
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

  /// A book in the library whose file is not on this device — the state a new
  /// phone leaves every book in.
  ///
  /// Hashing runs in an isolate, which the widget tester's fake clock never
  /// pumps, so every call that reaches it has to be wrapped in `runAsync`.
  Future<void> addBookWithoutItsFile() async {
    final path = await store.write('book-1', Stream.value(_pdfBytes('original')));
    final sha = await hashFile(store.resolve(path).path);
    await db.insertImportedBook(
      bookId: 'book-1',
      fingerprintId: 'fp-1',
      title: 'The Muqaddimah',
      pageCount: 240,
      sha256: sha,
      sizeBytes: 1,
      originalFileName: 'original.pdf',
      relativePath: path,
      now: _jan1,
    );
    await db.delete(db.localBookFiles).go();
    await store.delete(path);
  }

  Future<void> offer(String body) {
    final bytes = _pdfBytes(body);
    return container
        .read(locateFileControllerProvider.notifier)
        .offerFile(
          bookId: 'book-1',
          fileName: 'redownloaded.pdf',
          sizeBytes: bytes.length,
          openStream: () => Stream<Uint8List>.value(bytes),
        );
  }

  Future<void> pumpScreen(WidgetTester tester) async {
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          theme: AppTheme.of(
            brightness: Brightness.light,
            locale: const Locale('en'),
          ),
          home: const LocateFileScreen(bookId: 'book-1'),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> closeApp(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
  }

  testWidgets('opens by naming the book it is looking for', (tester) async {
    await tester.runAsync(addBookWithoutItsFile);
    await pumpScreen(tester);

    expect(
      find.text('Choose the PDF of "The Muqaddimah" on this device.'),
      findsOneWidget,
    );
    expect(find.text('Choose a PDF file'), findsOneWidget);

    await closeApp(tester);
  });

  testWidgets('the same file links with nothing to answer', (tester) async {
    await tester.runAsync(addBookWithoutItsFile);
    await pumpScreen(tester);

    await tester.runAsync(() => offer('original'));
    await tester.pumpAndSettle();

    expect(find.text('"The Muqaddimah" is ready to read'), findsOneWidget);
    expect(await db.hasLocalFile('book-1'), isTrue);

    await closeApp(tester);
  });

  testWidgets('a copy with a different page count asks before it moves anything', (
    tester,
  ) async {
    await tester.runAsync(addBookWithoutItsFile);
    await pumpScreen(tester);

    reportedPageCount = 480;
    await tester.runAsync(() => offer('a bigger scan'));
    await tester.pumpAndSettle();

    expect(find.text('This is a different copy'), findsOneWidget);
    expect(
      find.textContaining('This copy has 480 pages'),
      findsOneWidget,
    );
    // Keeping the numbers is the default, so its hint is the one on screen.
    expect(find.textContaining('Page 120 stays page 120'), findsOneWidget);

    await tester.tap(find.text('Move my progress across'));
    await tester.pumpAndSettle();
    expect(find.textContaining('kept as a position in the book'), findsOneWidget);

    await tester.tap(find.text('Link this file'));
    await tester.pumpAndSettle();

    expect(await db.hasLocalFile('book-1'), isTrue);
    expect((await db.findBook('book-1'))!.pageCount, 480);
    expect(find.text('"The Muqaddimah" is ready to read'), findsOneWidget);

    await closeApp(tester);
  });

  testWidgets('a copy with the same page count is a formality', (tester) async {
    await tester.runAsync(addBookWithoutItsFile);
    await pumpScreen(tester);

    await tester.runAsync(() => offer('a different scan'));
    await tester.pumpAndSettle();

    expect(find.text('This is a different copy'), findsOneWidget);
    expect(
      find.textContaining('It has the same number of pages'),
      findsOneWidget,
    );
    // No choice is put to the reader, because nothing of theirs moves.
    expect(find.text('Keep my page numbers'), findsNothing);

    await closeApp(tester);
  });
}
