import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../core/db/app_database.dart';
import '../../../core/files/book_file_store.dart';
import '../data/book_importer.dart';

/// Where the add-book flow currently is.
sealed class AddBookState {
  const AddBookState();
}

final class AddBookIdle extends AddBookState {
  const AddBookIdle();
}

final class AddBookImporting extends AddBookState {
  const AddBookImporting(this.stage);
  final ImportStage stage;
}

/// The PDF is in app storage and only needs a title before it becomes a book.
final class AddBookReady extends AddBookState {
  const AddBookReady({required this.bookId, required this.pdf});
  final String bookId;
  final ImportedPdf pdf;
}

/// The file's hash matched a book the reader already has.
final class AddBookDuplicate extends AddBookState {
  const AddBookDuplicate({required this.existing, required this.relinked});
  final Book existing;

  /// True when the existing book had no file on this device and this import
  /// supplied it — the cross-device relink case.
  final bool relinked;
}

final class AddBookFailed extends AddBookState {
  const AddBookFailed(this.failure);

  /// Null when the import blew up for a reason that is not about the PDF.
  final PdfImportFailure? failure;
}

final class AddBookSaved extends AddBookState {
  const AddBookSaved({required this.bookId, required this.title});
  final String bookId;
  final String title;
}

class AddBookController extends Notifier<AddBookState> {
  static const _uuid = Uuid();

  @override
  AddBookState build() => const AddBookIdle();

  AppDatabase get _db => ref.read(appDatabaseProvider);
  BookFileStore get _store => ref.read(bookFileStoreProvider);

  /// Copies the picked PDF into app storage and works out what it is.
  Future<void> importPicked({
    required String fileName,
    required int sizeBytes,
    required Stream<Uint8List> Function() openStream,
  }) async {
    final bookId = _uuid.v4();
    state = const AddBookImporting(ImportStage.copying);

    final ImportedPdf pdf;
    try {
      pdf = await ref
          .read(bookImporterProvider)
          .import(
            bookId: bookId,
            fileName: fileName,
            sizeBytes: sizeBytes,
            openStream: openStream,
            onStage: (stage) => state = AddBookImporting(stage),
          );
    } on PdfImportException catch (error) {
      state = AddBookFailed(error.failure);
      return;
    } on Object {
      state = const AddBookFailed(null);
      return;
    }

    // The hash is the book's identity, so a file we have seen before belongs to
    // an existing book rather than starting a new one.
    final existing = await _db.findBookByFileHash(pdf.sha256);
    if (existing != null) {
      final alreadyHasFile = await _db.hasLocalFile(existing.id);
      if (alreadyHasFile) {
        // Nothing to gain from a second copy of the same bytes.
        await _store.delete(pdf.relativePath);
        state = AddBookDuplicate(existing: existing, relinked: false);
      } else {
        await _db.linkBookFile(
          bookId: existing.id,
          relativePath: pdf.relativePath,
          now: DateTime.now(),
        );
        state = AddBookDuplicate(existing: existing, relinked: true);
      }
      return;
    }

    state = AddBookReady(bookId: bookId, pdf: pdf);
  }

  /// Commits the imported PDF as a book.
  Future<void> save({required String title, String? author}) async {
    final ready = state;
    if (ready is! AddBookReady) return;

    final trimmedAuthor = author?.trim();
    await _db.insertImportedBook(
      bookId: ready.bookId,
      fingerprintId: _uuid.v4(),
      title: title.trim(),
      author: (trimmedAuthor?.isEmpty ?? true) ? null : trimmedAuthor,
      pageCount: ready.pdf.pageCount,
      sha256: ready.pdf.sha256,
      sizeBytes: ready.pdf.sizeBytes,
      originalFileName: ready.pdf.originalFileName,
      relativePath: ready.pdf.relativePath,
      now: DateTime.now(),
    );

    state = AddBookSaved(bookId: ready.bookId, title: title.trim());
  }

  /// Removes an imported-but-unsaved copy.
  ///
  /// Called when the reader backs out of the details form; without it the file
  /// would sit in app storage forever with no book pointing at it.
  Future<void> discardPending() async {
    final pending = state;
    if (pending is AddBookReady) {
      await _store.delete(pending.pdf.relativePath);
    }
    state = const AddBookIdle();
  }

  void reset() => state = const AddBookIdle();
}

final addBookControllerProvider =
    NotifierProvider<AddBookController, AddBookState>(AddBookController.new);
