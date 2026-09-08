import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../auth/auth_state.dart';
import '../db/app_database.dart';
import '../settings/app_settings.dart';
import 'sync_client.dart';
import 'sync_mappers.dart';
import 'sync_models.dart';
import 'sync_status.dart';

/// Drains the outbox to the server, then merges back what the server has.
///
/// Push runs first. The alternative — pulling first — would merge the server's
/// view into a database that still has unsent local writes in it, and the
/// reader would watch their own edits lose to an older copy for one round. By
/// pushing first, the pull that follows sees the merged result and the device
/// converges in a single pass.
class SyncEngine {
  SyncEngine({
    required this.db,
    required this.client,
    required this.prefs,
    required this.userId,
  });

  final AppDatabase db;
  final SyncApi client;
  final SharedPreferences prefs;

  /// Whose sync this is. Part of the cursor key, so signing into a second
  /// account on the same phone does not inherit the first one's position and
  /// skip everything written before it.
  final String userId;

  String get _cursorKey => 'sync.cursor.$userId';

  /// Where the last successful pull left off, or null on a new account.
  DateTime? get cursor {
    final raw = prefs.getString(_cursorKey);
    return raw == null ? null : DateTime.parse(raw);
  }

  Future<void> _saveCursor(DateTime serverTime) =>
      prefs.setString(_cursorKey, wireInstant(serverTime));

  /// Forgets the cursor, so the next sync pulls the whole account again.
  Future<void> resetCursor() => prefs.remove(_cursorKey);

  /// One full round trip.
  ///
  /// Every failure comes back as [SyncFailed] rather than being thrown. A sync
  /// runs behind a button that has to stop spinning, and an exception escaping
  /// here would leave the reader looking at "syncing…" for the rest of the
  /// session. The cursor is untouched either way, so whatever failed is asked
  /// for again next time.
  Future<SyncStatus> syncNow() async {
    try {
      final pushed = await _push();
      final pulled = await _pull();
      return SyncComplete(pushed: pushed, pulled: pulled);
    } catch (error) {
      return SyncFailed(error.toString());
    }
  }

  /// Sends queued changes and clears the rows that were sent.
  Future<int> _push() async {
    // Snapshotted before the request, and deleted afterwards *by id*. Reading
    // continues while the push is in flight, and anything queued in the
    // meantime has to survive to the next round rather than be swept up as
    // though it had been sent.
    final pending = await db.pendingOutboxEntries();
    if (pending.isEmpty) return 0;

    final payload = _payloadOf(pending);
    final SyncPushResponse response;
    try {
      response = await client.push(payload);
    } on SyncException {
      await db.incrementOutboxAttempts([for (final e in pending) e.id]);
      // A row the server keeps refusing is a row the server will never take.
      // Retrying it forever would wedge the queue and block everything behind
      // it, so it is dropped after a handful of tries.
      await db.deleteStaleOutboxEntries();
      rethrow;
    }

    await db.deleteOutboxEntries([for (final e in pending) e.id]);
    return response.applied;
  }

  /// Fetches everything that changed since the cursor and merges it.
  Future<int> _pull() async {
    final response = await client.pull(since: cursor);
    final changes = response.changes;

    // In foreign-key order: a plan whose book has not landed yet would fail
    // the constraint, and the pull would abort halfway through.
    await db.mergeBooks(changes.books);
    await db.mergeFingerprints(changes.fingerprints);
    await db.mergePlans(changes.plans);
    await db.mergeSessions(changes.sessions);
    await db.mergeLogEntries(changes.logEntries);

    // Advanced only now. A cursor moved before the merge would, if the merge
    // failed, skip the very rows that failed on every future pull.
    await _saveCursor(response.serverTime);

    return changes.books.length +
        changes.fingerprints.length +
        changes.plans.length +
        changes.sessions.length +
        changes.logEntries.length;
  }

  /// Regroups queued rows into the single payload the server expects.
  ///
  /// Deletes ride along with upserts: every deletable row here is soft-deleted,
  /// so a delete is just an upsert carrying a `deletedAt`.
  SyncPayload _payloadOf(List<SyncOutboxData> entries) {
    final books = <BookDto>[];
    final fingerprints = <FingerprintDto>[];
    final plans = <PlanDto>[];
    final sessions = <SessionDto>[];
    final logEntries = <LogEntryDto>[];

    for (final entry in entries) {
      final json = jsonDecode(entry.payloadJson) as Map<String, dynamic>;
      switch (entry.entity) {
        case SyncEntity.books:
          books.add(BookDto.fromJson(json));
        case SyncEntity.fingerprints:
          fingerprints.add(FingerprintDto.fromJson(json));
        case SyncEntity.plans:
          plans.add(PlanDto.fromJson(json));
        case SyncEntity.sessions:
          sessions.add(SessionDto.fromJson(json));
        case SyncEntity.logEntries:
          logEntries.add(LogEntryDto.fromJson(json));
      }
    }

    return SyncPayload(
      books: books,
      fingerprints: fingerprints,
      plans: plans,
      sessions: sessions,
      logEntries: logEntries,
    );
  }
}

/// The engine for the signed-in reader, or null while nobody is signed in.
///
/// Watching the session rather than reading it is what rebuilds the engine —
/// and its cursor key — when the reader signs out and someone else signs in.
final syncEngineProvider = Provider<SyncEngine?>((ref) {
  final session = ref.watch(authStateProvider);
  if (session == null) return null;

  return SyncEngine(
    db: ref.watch(appDatabaseProvider),
    client: ref.watch(syncClientProvider),
    prefs: ref.watch(sharedPreferencesProvider),
    userId: session.userId,
  );
});

/// How many local changes are still waiting to be sent.
final pendingSyncCountProvider = StreamProvider<int>((ref) {
  return ref.watch(appDatabaseProvider).watchPendingSyncCount();
});

/// Runs a sync and reports how it went, for the settings screen to show.
class SyncController extends Notifier<SyncStatus> {
  @override
  SyncStatus build() => const SyncIdle();

  /// Syncs now, unless one is already running.
  Future<void> syncNow() async {
    if (state is SyncInProgress) return;

    final engine = ref.read(syncEngineProvider);
    if (engine == null) return;

    state = const SyncInProgress();
    state = await engine.syncNow();
  }
}

final syncControllerProvider = NotifierProvider<SyncController, SyncStatus>(
  SyncController.new,
);
