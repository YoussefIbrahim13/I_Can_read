import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/db/app_database.dart';

/// The three shelves the library is divided into.
///
/// Not the same thing as [BookStatus]: "paused" is a property of the book's
/// plan, not of the book, but the reader has no use for that distinction when
/// they are looking for where they put something.
enum LibraryShelf { reading, finished, paused }

/// The books on one shelf, kept live as the database changes.
final booksOnShelfProvider = StreamProvider.family<List<Book>, LibraryShelf>((
  ref,
  shelf,
) {
  final db = ref.watch(appDatabaseProvider);
  return switch (shelf) {
    LibraryShelf.reading => db.watchBooksByPause(paused: false),
    LibraryShelf.paused => db.watchBooksByPause(paused: true),
    LibraryShelf.finished => db.watchBooks(BookStatus.finished),
  };
});

/// Ids of books whose PDF is not on this device.
///
/// Kept separate from the book rows because availability is device-local and
/// never travels with the account.
final missingFileBookIdsProvider = StreamProvider<Set<String>>((ref) {
  return ref
      .watch(appDatabaseProvider)
      .watchBooksMissingFiles()
      .map((books) => books.map((book) => book.id).toSet());
});
