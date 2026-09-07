import 'dart:io';
import 'dart:typed_data';

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

  static Future<BookFileStore> open() async =>
      BookFileStore(await getApplicationDocumentsDirectory());

  /// Resolved at runtime, never persisted.
  final Directory documentsDirectory;

  static const _booksDirectory = 'books';

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
