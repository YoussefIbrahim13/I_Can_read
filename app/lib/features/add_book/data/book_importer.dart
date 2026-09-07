import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:pdfrx/pdfrx.dart';

import '../../../core/files/book_file_store.dart';
import '../../../core/files/pdf_fingerprint.dart';

/// Steps the import goes through, surfaced so the UI can say what is happening
/// during what may be a multi-second copy of a large scan.
enum ImportStage { copying, hashing, readingPages }

enum PdfImportFailure {
  /// The chosen file is not a PDF at all.
  notAPdf,

  /// It looks like a PDF but no page could be read — corrupt, or encrypted
  /// with a password we do not have.
  unreadable,
}

class PdfImportException implements Exception {
  const PdfImportException(this.failure, [this.cause]);

  final PdfImportFailure failure;
  final Object? cause;

  @override
  String toString() => 'PdfImportException($failure, $cause)';
}

/// A PDF that now lives in the app's own storage, with everything needed to
/// create a book record.
class ImportedPdf {
  const ImportedPdf({
    required this.relativePath,
    required this.sha256,
    required this.pageCount,
    required this.sizeBytes,
    required this.originalFileName,
    required this.suggestedTitle,
  });

  final String relativePath;
  final String sha256;
  final int pageCount;
  final int sizeBytes;
  final String originalFileName;

  /// The file name tidied into something worth showing as a book title.
  final String suggestedTitle;
}

/// Reads a PDF's page count. Injectable so tests need no native PDF engine.
typedef PdfPageCounter = Future<int> Function(String absolutePath);

/// Physical page count, which is what every stored page number refers to.
Future<int> countPdfPages(String absolutePath) async {
  // The widgets initialise the engine themselves, but we are calling the
  // document API directly, so this has to happen first.
  await pdfrxFlutterInitialize();
  final document = await PdfDocument.openFile(absolutePath);
  try {
    return document.pages.length;
  } finally {
    await document.dispose();
  }
}

class BookImporter {
  BookImporter(this._store, {PdfPageCounter pageCounter = countPdfPages})
    : _countPages = pageCounter;

  final BookFileStore _store;
  final PdfPageCounter _countPages;

  /// Every PDF starts with this signature.
  static const _pdfMagic = [0x25, 0x50, 0x44, 0x46]; // %PDF

  /// Copies a picked file into app storage and describes it.
  ///
  /// [openStream] is a factory rather than a stream so the source is only read
  /// once, on our terms. On failure the partial copy is removed, so a rejected
  /// import leaves nothing behind.
  Future<ImportedPdf> import({
    required String bookId,
    required String fileName,
    required int sizeBytes,
    required Stream<Uint8List> Function() openStream,
    ValueChanged<ImportStage>? onStage,
  }) async {
    onStage?.call(ImportStage.copying);
    final relativePath = await _store.write(bookId, openStream());
    final absolutePath = _store.resolve(relativePath).path;

    try {
      if (!await _looksLikePdf(absolutePath)) {
        throw const PdfImportException(PdfImportFailure.notAPdf);
      }

      onStage?.call(ImportStage.hashing);
      final digest = await hashFile(absolutePath);

      onStage?.call(ImportStage.readingPages);
      final pageCount = await _readPageCount(absolutePath);

      return ImportedPdf(
        relativePath: relativePath,
        sha256: digest,
        pageCount: pageCount,
        sizeBytes: sizeBytes,
        originalFileName: fileName,
        suggestedTitle: titleFromFileName(fileName),
      );
    } on Object {
      await _store.delete(relativePath);
      rethrow;
    }
  }

  Future<int> _readPageCount(String absolutePath) async {
    final int pageCount;
    try {
      pageCount = await _countPages(absolutePath);
    } on Object catch (error) {
      throw PdfImportException(PdfImportFailure.unreadable, error);
    }
    if (pageCount < 1) {
      throw const PdfImportException(PdfImportFailure.unreadable);
    }
    return pageCount;
  }

  /// Cheap signature check, so an obviously wrong file fails fast with a clear
  /// message instead of a native parser error.
  Future<bool> _looksLikePdf(String absolutePath) async {
    final handle = await File(absolutePath).open();
    try {
      final header = await handle.read(_pdfMagic.length);
      if (header.length < _pdfMagic.length) return false;
      for (var i = 0; i < _pdfMagic.length; i++) {
        if (header[i] != _pdfMagic[i]) return false;
      }
      return true;
    } finally {
      await handle.close();
    }
  }
}

/// Turns `the-muqaddimah_vol2.pdf` into `the muqaddimah vol2`, which is a far
/// better starting point for the title field than the raw file name.
String titleFromFileName(String fileName) {
  final withoutExtension = p.basenameWithoutExtension(fileName);
  final spaced = withoutExtension.replaceAll(RegExp(r'[_\-]+'), ' ');
  final collapsed = spaced.replaceAll(RegExp(r'\s+'), ' ').trim();
  return collapsed.isEmpty ? fileName : collapsed;
}

final bookImporterProvider = Provider<BookImporter>(
  (ref) => BookImporter(ref.watch(bookFileStoreProvider)),
);
