import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../core/db/app_database.dart';
import '../../../core/files/book_file_store.dart';
import '../../add_book/data/book_importer.dart';

/// Where the "locate this book's PDF" flow is.
///
/// Separate from the add-book flow even though the first half is identical:
/// there, an unrecognised file is a new book, which is the happy path. Here the
/// book already exists and the reader has asserted that this file *is* it, so
/// an unrecognised file is a question — and possibly a rewrite of their
/// progress — rather than an import.
sealed class LocateFileState {
  const LocateFileState();
}

final class LocateIdle extends LocateFileState {
  const LocateIdle();
}

final class LocateImporting extends LocateFileState {
  const LocateImporting(this.stage);
  final ImportStage stage;
}

/// The file is now this book's, and the reader can read.
final class LocateLinked extends LocateFileState {
  const LocateLinked({required this.bookId, required this.title});
  final String bookId;
  final String title;
}

/// The hash belongs to a different book in the library.
///
/// Linking it here would give two books the same file and the same
/// fingerprint, so the copy is discarded and the reader is told where the file
/// actually lives.
final class LocateWrongBook extends LocateFileState {
  const LocateWrongBook(this.owner);
  final Book owner;
}

/// A file this book has never seen. Waiting for the reader to confirm it is
/// another copy of the same book.
final class LocateUnrecognised extends LocateFileState {
  const LocateUnrecognised({
    required this.bookId,
    required this.pdf,
    required this.recordedPageCount,
  });

  final String bookId;
  final ImportedPdf pdf;

  /// The page count the book was recorded with, to compare against
  /// `pdf.pageCount`. Equal counts make this a formality; different ones mean
  /// the plan's page numbers have to move.
  final int recordedPageCount;

  bool get pageCountDiffers => pdf.pageCount != recordedPageCount;
}

final class LocateFailed extends LocateFileState {
  const LocateFailed(this.failure);

  /// Null when the import failed for a reason that is not about the PDF.
  final PdfImportFailure? failure;
}

class LocateFileController extends Notifier<LocateFileState> {
  static const _uuid = Uuid();

  @override
  LocateFileState build() => const LocateIdle();

  AppDatabase get _db => ref.read(appDatabaseProvider);
  BookFileStore get _store => ref.read(bookFileStoreProvider);

  /// Copies the picked PDF in and works out whether it is this book.
  Future<void> offerFile({
    required String bookId,
    required String fileName,
    required int sizeBytes,
    required Stream<Uint8List> Function() openStream,
  }) async {
    final book = await _db.findBook(bookId);
    if (book == null) {
      state = const LocateFailed(null);
      return;
    }

    state = const LocateImporting(ImportStage.copying);

    final ImportedPdf pdf;
    try {
      pdf = await ref
          .read(bookImporterProvider)
          .import(
            // Written straight to this book's own slot: the reader is not
            // adding anything, so there is no second place for it to live.
            bookId: bookId,
            fileName: fileName,
            sizeBytes: sizeBytes,
            openStream: openStream,
            onStage: (stage) => state = LocateImporting(stage),
          );
    } on PdfImportException catch (error) {
      state = LocateFailed(error.failure);
      return;
    } on Object {
      state = const LocateFailed(null);
      return;
    }

    final owner = await _db.findBookByFileHash(pdf.sha256);

    if (owner != null && owner.id != bookId) {
      await _store.delete(pdf.relativePath);
      state = LocateWrongBook(owner);
      return;
    }

    if (owner != null) {
      // A copy this book already knows: nothing to confirm and nothing to
      // rewrite, so the file is simply back.
      await _db.linkBookFile(
        bookId: bookId,
        relativePath: pdf.relativePath,
        now: DateTime.now(),
      );
      state = LocateLinked(bookId: bookId, title: book.title);
      return;
    }

    state = LocateUnrecognised(
      bookId: bookId,
      pdf: pdf,
      recordedPageCount: book.pageCount,
    );
  }

  /// Accepts the unrecognised file as another copy of the book.
  ///
  /// [rescaleProgress] only matters when the page counts differ; it is what the
  /// reader answered when asked whether their page numbers should move with the
  /// new copy or stay where they are.
  Future<void> confirmUnrecognised({bool rescaleProgress = false}) async {
    final pending = state;
    if (pending is! LocateUnrecognised) return;

    final book = await _db.findBook(pending.bookId);
    if (book == null) {
      state = const LocateFailed(null);
      return;
    }

    await _db.relinkBookFile(
      bookId: pending.bookId,
      relativePath: pending.pdf.relativePath,
      fingerprintId: _uuid.v4(),
      sha256: pending.pdf.sha256,
      filePageCount: pending.pdf.pageCount,
      sizeBytes: pending.pdf.sizeBytes,
      originalFileName: pending.pdf.originalFileName,
      rescaleProgress: rescaleProgress,
      now: DateTime.now(),
    );

    state = LocateLinked(bookId: pending.bookId, title: book.title);
  }

  /// Drops a copy the reader decided against, so declining the question does
  /// not leave an orphan PDF in app storage.
  Future<void> discardPending() async {
    final pending = state;
    if (pending is LocateUnrecognised) {
      await _store.delete(pending.pdf.relativePath);
    }
    state = const LocateIdle();
  }

  void reset() => state = const LocateIdle();
}

final locateFileControllerProvider =
    NotifierProvider<LocateFileController, LocateFileState>(
      LocateFileController.new,
    );
