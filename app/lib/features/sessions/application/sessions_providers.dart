import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../core/db/app_database.dart';
import '../domain/session_plan.dart';

/// A plan's reminders, in time order.
final planSessionsProvider = StreamProvider.autoDispose
    .family<List<ReadingSession>, String>((ref, planId) {
      return ref.watch(appDatabaseProvider).watchSessionsFor(planId);
    });

/// Writes a whole session list back to the database.
class SessionWriter {
  const SessionWriter(this._db);

  static const _uuid = Uuid();

  final AppDatabase _db;

  /// Replaces the plan's sessions wholesale.
  ///
  /// Rows are rebuilt rather than diffed because the ordinal — which seeds each
  /// notification id — is positional: inserting an early-morning session
  /// renumbers everything after it anyway.
  Future<void> save({required String planId, required SessionPlan plan}) {
    final now = DateTime.now();
    return _db.replaceSessions(planId, [
      for (final (ordinal, slot) in plan.slots.indexed)
        ReadingSessionsCompanion.insert(
          id: _uuid.v4(),
          planId: planId,
          ordinal: ordinal,
          timeOfDayMinutes: slot.minutes,
          pagesShare: slot.pages,
          updatedAt: now,
        ),
    ]);
  }
}

final sessionWriterProvider = Provider<SessionWriter>((ref) {
  return SessionWriter(ref.watch(appDatabaseProvider));
});
