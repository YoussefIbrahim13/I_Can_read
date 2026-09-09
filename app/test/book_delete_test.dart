import 'dart:typed_data';

import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:i_can_read/core/db/app_database.dart';
import 'package:i_can_read/core/files/book_file_store.dart';
import 'package:i_can_read/core/planning/plan_math.dart';
import 'package:i_can_read/core/sync/sync_mappers.dart';
import 'package:i_can_read/core/theme/app_theme.dart';
import 'package:i_can_read/features/book_detail/application/book_detail_providers.dart';
import 'package:i_can_read/features/book_detail/presentation/book_detail_screen.dart';
import 'package:i_can_read/features/today/application/today_providers.dart';
import 'package:i_can_read/l10n/app_localizations.dart';

final _jan1 = DateTime(2026, 1, 1);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory documents;
  late BookFileStore store;
  late AppDatabase db;
  late ProviderContainer container;

  setUp(() async {
    documents = await Directory.systemTemp.createTemp('i_can_read_delete');
    store = BookFileStore(documents);
    db = AppDatabase(NativeDatabase.memory());
    container = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        bookFileStoreProvider.overrideWithValue(store),
        todayProvider.overrideWithValue(DateTime(2026, 1, 5)),
      ],
    );
  });

  tearDown(() async {
    container.dispose();
    await db.close();
    if (documents.existsSync()) await documents.delete(recursive: true);
  });

  /// A book with a file on this device, a plan, and a reminder.
  Future<void> addBook({bool withFile = true}) async {
    final relativePath = store.relativePathFor('book-1');
    if (withFile) {
      await store.write('book-1', Stream.value(Uint8List.fromList([1, 2, 3])));
    }

    await db.insertImportedBook(
      bookId: 'book-1',
      fingerprintId: 'fp-1',
      title: 'The Muqaddimah',
      pageCount: 300,
      sha256: 'a' * 64,
      sizeBytes: 3,
      originalFileName: 'book.pdf',
      relativePath: relativePath,
      now: _jan1,
    );
    await db.savePlan(
      bookId: 'book-1',
      spec: PlanSpec(
        mode: PlanMode.byPagesPerDay,
        startPage: 1,
        endPage: 300,
        startDate: _jan1,
        targetEndDate: DateTime(2026, 1, 30),
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
    await db.clearOutbox();
  }

  BookActions actions() => container.read(bookActionsProvider);

  group('removing a book', () {
    test('takes it off every shelf without erasing the row', () async {
      await addBook();

      await actions().delete('book-1');

      expect(await db.watchBooks(BookStatus.reading).first, isEmpty);
      expect(await db.watchBooksByPause(paused: false).first, isEmpty);
      // The row survives as a tombstone: a book that simply vanished from this
      // phone could not be described in a push, and the server would hand it
      // straight back on the next pull.
      expect((await db.findBook('book-1'))!.deletedAt, isNotNull);
    });

    test('queues the removal for the other devices', () async {
      await addBook();

      await actions().delete('book-1');

      final queued = await db.pendingOutboxEntries();
      final book = queued.singleWhere((e) => e.entity == SyncEntity.books);
      expect(book.op, SyncOp.delete);
      expect(book.entityId, 'book-1');
    });

    test('deletes the copy of the PDF this app made', () async {
      await addBook();
      final relativePath = store.relativePathFor('book-1');
      expect(await store.exists(relativePath), isTrue);

      await actions().delete('book-1');

      expect(await store.exists(relativePath), isFalse);
      // And the record of where it was, which is device-local and never synced.
      expect(await db.hasLocalFile('book-1'), isFalse);
    });

    test('stops its reminders', () async {
      await addBook();
      expect(await db.watchDueReminders().first, hasLength(1));

      await actions().delete('book-1');

      // Through the same stream that scheduled them, rather than a second path
      // that could disagree with the first.
      expect(await db.watchDueReminders().first, isEmpty);
    });

    test('takes it out of today without touching another book', () async {
      await addBook();
      await db
          .into(db.books)
          .insert(
            BooksCompanion.insert(
              id: 'book-2',
              title: 'Another Book',
              pageCount: 100,
              createdAt: _jan1,
              updatedAt: _jan1,
            ),
          );

      await actions().delete('book-1');

      final remaining = await db.watchBooks(BookStatus.reading).first;
      expect(remaining.single.id, 'book-2');
    });

    test('survives a book whose file was already gone', () async {
      await addBook(withFile: false);
      await db
          .update(db.localBookFiles)
          .write(const LocalBookFilesCompanion(isAvailable: Value(false)));

      await actions().delete('book-1');

      expect((await db.findBook('book-1'))!.deletedAt, isNotNull);
    });

    test(
      'a removed file no longer relinks to the book it belonged to',
      () async {
        await addBook();

        await actions().delete('book-1');

        // Otherwise re-adding the same PDF would silently reattach it to a book
        // the reader deliberately removed, instead of starting a new one.
        expect(await db.findBookByFileHash('a' * 64), isNull);
      },
    );
  });

  group('the detail screen', () {
    Future<AppLocalizations> open(
      WidgetTester tester, {
      Locale locale = const Locale('en'),
    }) async {
      // A phone-height viewport rather than the 600px default. The screen is a
      // lazy list and the removal sits at the very bottom of it, so on a short
      // viewport the button is never built and cannot be found at all.
      tester.view.physicalSize = const Size(400 * 3, 1400 * 3);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            locale: locale,
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            theme: AppTheme.of(brightness: Brightness.light, locale: locale),
            home: const BookDetailScreen(bookId: 'book-1'),
          ),
        ),
      );
      await tester.pumpAndSettle();
      return AppLocalizations.delegate.load(locale);
    }

    Future<void> tap(WidgetTester tester, String label) async {
      final button = find.text(label);
      await tester.ensureVisible(button);
      await tester.pumpAndSettle();
      await tester.tap(button);
      await tester.pumpAndSettle();
    }

    testWidgets('asks first, and the first tap removes nothing', (
      tester,
    ) async {
      await addBook(withFile: false);
      final l10n = await open(tester);

      await tap(tester, l10n.bookDelete);

      expect(find.text(l10n.bookDeleteConfirm), findsOneWidget);
      expect((await db.findBook('book-1'))!.deletedAt, isNull);

      // And backing out leaves the book exactly as it was.
      await tap(tester, l10n.actionCancel);
      expect(find.text(l10n.bookDeleteConfirm), findsNothing);
      expect((await db.findBook('book-1'))!.deletedAt, isNull);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 1));
    });

    testWidgets('removes the book on the second tap', (tester) async {
      // No file on disk, deliberately. The widget tester's fake clock never
      // completes real file I/O, so a book with a PDF to delete would leave the
      // removal half-done forever. What happens to the file is covered above,
      // on the real clock; what this test is about is the second tap.
      await addBook(withFile: false);
      final l10n = await open(tester);

      await tap(tester, l10n.bookDelete);
      await tap(tester, l10n.bookDeleteYes);

      expect((await db.findBook('book-1'))!.deletedAt, isNotNull);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 1));
    });
  });
}
