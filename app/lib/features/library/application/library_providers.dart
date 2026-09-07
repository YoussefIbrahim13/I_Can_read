import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/db/app_database.dart';

/// The books on one shelf, kept live as the database changes.
final booksByStatusProvider = StreamProvider.family<List<Book>, BookStatus>((
  ref,
  status,
) {
  return ref.watch(appDatabaseProvider).watchBooks(status);
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
