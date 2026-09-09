import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../core/db/app_database.dart';
import '../../../core/files/book_file_store.dart';

/// The book's PDF on this device, or null when the file is missing.
///
/// Missing is a normal state, not an error: the account restores plans and
/// progress but never the files, so a reader who signed in on a new phone has
/// books whose PDFs they have not relinked yet.
final bookFilePathProvider = FutureProvider.autoDispose.family<String?, String>(
  (ref, bookId) async {
    final relativePath = await ref
        .watch(appDatabaseProvider)
        .localFilePath(bookId);
    if (relativePath == null) return null;

    // The row can outlive the file — an OS clean-up or a restore from backup
    // leaves the record behind — so the path is checked, not trusted.
    final file = ref.watch(bookFileStoreProvider).resolve(relativePath);
    return file.existsSync() ? file.path : null;
  },
);

/// Writes what was read back to the plan.
class ProgressWriter {
  const ProgressWriter(this._db);

  static const _uuid = Uuid();

  final AppDatabase _db;

  /// Records a stretch of reading. Returns true when it finished the book.
  ///
  /// The reader hands over the page it is *showing*, which is the last page the
  /// reader has actually looked at — pages are credited on being reached, not
  /// on being turned past, so finishing on the last page of a portion counts.
  /// [spent] is time with the book actually open, not wall time since the
  /// reader was opened. Defaults to zero so a caller that does not measure
  /// records nothing rather than a guess.
  Future<bool> record({
    required String planId,
    String? sessionId,
    required int fromPage,
    required int toPage,
    Duration spent = Duration.zero,
  }) {
    return _db.recordReading(
      planId: planId,
      sessionId: sessionId,
      fromPage: fromPage,
      toPage: toPage,
      readAt: DateTime.now(),
      durationSeconds: spent.inSeconds,
      logId: _uuid.v4(),
    );
  }
}

final progressWriterProvider = Provider<ProgressWriter>((ref) {
  return ProgressWriter(ref.watch(appDatabaseProvider));
});
