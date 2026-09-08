import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../core/db/app_database.dart';
import '../../../core/planning/plan_math.dart';

/// One book, for the screens that are opened by id rather than handed a row.
///
/// Auto-disposing because it is keyed by book: without it, every book the
/// reader opens would leave a live entry — and a live query — behind for the
/// rest of the session.
final bookProvider = StreamProvider.autoDispose.family<Book?, String>((
  ref,
  bookId,
) {
  return ref.watch(appDatabaseProvider).watchBook(bookId);
});

/// The book's plan, or null while it has none.
final activePlanProvider = StreamProvider.autoDispose
    .family<ReadingPlan?, String>((ref, bookId) {
      return ref.watch(appDatabaseProvider).watchActivePlanFor(bookId);
    });

/// Active plans keyed by book, for the library shelf.
final activePlansProvider = StreamProvider<Map<String, ReadingPlan>>((ref) {
  return ref.watch(appDatabaseProvider).watchActivePlans();
});

/// Writes a resolved plan back to the database.
///
/// Thin on purpose: all the arithmetic lives in `plan_math.dart` and all the
/// form state in `PlanDraft`, so the only thing left here is minting an id and
/// stamping the time — the two pieces the pure code cannot supply.
class PlanWriter {
  const PlanWriter(this._db);

  static const _uuid = Uuid();

  final AppDatabase _db;

  Future<String> save({required String bookId, required PlanSpec spec}) {
    return _db.savePlan(
      bookId: bookId,
      spec: spec,
      now: DateTime.now(),
      newPlanId: _uuid.v4(),
    );
  }
}

final planWriterProvider = Provider<PlanWriter>((ref) {
  return PlanWriter(ref.watch(appDatabaseProvider));
});
