import 'dart:io';

// Also the source of `Uint8List` here; a separate `dart:typed_data` import
// would be flagged as redundant.
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Owns the app's private copy of every book PDF.
///
/// Two rules drive this class:
///
/// 1. **Always copy.** A file picked through Android's Storage Access Framework
///    arrives as a `content://` URI backed by a cache entry the system is free
///    to delete, and on many devices [PlatformFile.path] is null outright. The
///    only durable option is to stream the bytes into our own directory.
/// 2. **Store paths relative.** The iOS app-container path contains a UUID that
///    changes on reinstall and on some updates, so an absolute path saved today
///    is dead tomorrow. Only `books/<id>.pdf` is persisted; the container is
///    resolved fresh at every launch.
class BookFileStore {
  BookFileStore(this.documentsDirectory);

  static Future<BookFileStore> open() async {
    final store = BookFileStore(await getApplicationDocumentsDirectory());
    await store._excludeBooksFromICloud();
    return store;
  }

  /// Resolved at runtime, never persisted.
  final Directory documentsDirectory;

  static const _booksDirectory = 'books';

  /// Talks to `AppDelegate.swift`. iOS only; nothing implements it elsewhere.
  static const _platform = MethodChannel('icanread/book_files');

  /// Keeps the reader's PDFs out of iCloud.
  ///
  /// iOS backs the documents directory up by default, which would upload every
  /// imported book — the one thing the app promises not to do. The Android
  /// equivalent is `android:allowBackup="false"` in the manifest.
  ///
  /// The flag lives on the directory itself and is inherited by everything
  /// created inside it, so it is set on `books/` rather than on each file, and
  /// the directory has to exist first — hence the [Directory.create] here as
  /// well as in [write]. Re-applying it at every launch is one syscall and it
  /// is what repairs an install that was made before this code existed.
  Future<void> _excludeBooksFromICloud() async {
    if (!Platform.isIOS) return;

    final books = Directory(p.join(documentsDirectory.path, _booksDirectory));
    await books.create(recursive: true);
    try {
      await _platform.invokeMethod<void>('excludeFromBackup', books.path);
    } catch (error) {
      // Refusing to start would be worse than starting: the reader has no way
      // to act on this, and the books are already on the device. Loud in debug,
      // survivable in release, retried on the next launch.
      debugPrint('Could not exclude books/ from iCloud backup: $error');
      assert(false, 'Could not exclude books/ from iCloud backup: $error');
    }
  }

  /// The stable, device-independent path recorded in the database.
  String relativePathFor(String bookId) =>
      p.posix.join(_booksDirectory, '$bookId.pdf');

  /// Turns a stored relative path into a file on this device.
  File resolve(String relativePath) => File(
    p.join(documentsDirectory.path, p.joinAll(p.posix.split(relativePath))),
  );

  Future<bool> exists(String relativePath) => resolve(relativePath).exists();

  /// Streams [bytes] into the store and returns the relative path.
  ///
  /// Writes to a temporary sibling first and renames on success, so an
  /// interrupted import can never leave a truncated file that later looks like
  /// a valid book.
  Future<String> write(String bookId, Stream<Uint8List> bytes) async {
    final relativePath = relativePathFor(bookId);
    final target = resolve(relativePath);
    await target.parent.create(recursive: true);

    final partial = File('${target.path}.part');
    try {
      final sink = partial.openWrite();
      try {
        await sink.addStream(bytes);
      } finally {
        await sink.close();
      }
      await partial.rename(target.path);
      return relativePath;
    } on Object {
      if (partial.existsSync()) await partial.delete();
      rethrow;
    }
  }

  Future<void> delete(String relativePath) async {
    final file = resolve(relativePath);
    if (file.existsSync()) await file.delete();
  }
}

/// Resolved once at startup; see `main()`.
final bookFileStoreProvider = Provider<BookFileStore>(
  (ref) => throw StateError('bookFileStoreProvider was not overridden'),
);
