import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../planning/page_rescale.dart';
import '../planning/plan_math.dart';
import '../planning/reading_pace.dart';
import '../sync/sync_mappers.dart';
import '../sync/sync_models.dart';
import 'tables.dart';

export 'tables.dart';

part 'app_database.g.dart';

@DriftDatabase(
  tables: [
    Books,
    BookFingerprints,
    ReadingPlans,
    ReadingSessions,
    ReadingLog,
    LocalBookFiles,
    ReaderStates,
    SyncOutbox,
  ],
)
class AppDatabase extends _$AppDatabase {
  /// Pass an executor in tests; production uses the platform default.
  AppDatabase([QueryExecutor? executor])
    : super(executor ?? driftDatabase(name: 'i_can_read'));

  @override
  int get schemaVersion => 4;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onUpgrade: (m, from, to) async {
      if (from < 2) {
        // Pausing a plan, added once it was clear that a deliberate break and
        // a missed day are not the same thing.
        await m.addColumn(readingPlans, readingPlans.pausedAt);
        await m.addColumn(readingPlans, readingPlans.pausedDays);
      }
      if (from < 3) {
        // `archived` was dropped in favour of pausing the plan. Any book on
        // the old shelf goes back to being read: it is the reversible choice,
        // and the reader can pause it if that is what they meant.
        await customStatement(
          "UPDATE books SET status = 'reading' WHERE status = 'archived'",
        );
      }
      if (from < 4) {
        // Sessions became soft-deletable once they started syncing: a hard
        // delete leaves nothing to tell the other devices it happened.
        await m.addColumn(readingSessions, readingSessions.deletedAt);
      }
    },
    beforeOpen: (details) async {
      // Off by default in SQLite; without it the cascade rules are decorative.
      await customStatement('PRAGMA foreign_keys = ON');
    },
  );

  // -------------------------------------------------------------------------
  // Library
  // -------------------------------------------------------------------------

  /// Books in a given shelf, newest first, excluding soft-deleted rows.
  Stream<List<Book>> watchBooks(BookStatus status) {
    return (select(books)
          ..where((b) => b.status.equalsValue(status) & b.deletedAt.isNull())
          ..orderBy([(b) => OrderingTerm.desc(b.createdAt)]))
        .watch();
  }

  /// Books whose plan is paused, and books still being read — the two halves
  /// of what used to be one "reading" shelf.
  ///
  /// Split here rather than in the widget because a paused book must appear on
  /// exactly one shelf: leaving it on both is how the reader ends up pausing a
  /// book twice and wondering why nothing changed.
  Stream<List<Book>> watchBooksByPause({required bool paused}) {
    final pausedPlan = existsQuery(
      select(readingPlans)..where(
        (p) =>
            p.bookId.equalsExp(books.id) &
            p.isActive.equals(true) &
            p.pausedAt.isNotNull(),
      ),
    );

    return (select(books)
          ..where(
            (b) =>
                b.status.equalsValue(BookStatus.reading) &
                b.deletedAt.isNull() &
                (paused ? pausedPlan : pausedPlan.not()),
          )
          ..orderBy([(b) => OrderingTerm.desc(b.createdAt)]))
        .watch();
  }

  Future<Book?> findBook(String id) =>
      (select(books)..where((b) => b.id.equals(id))).getSingleOrNull();

  /// One book, kept live.
  ///
  /// A stream rather than a one-shot read because the book's status is
  /// editable from the detail screen: shelving a book has to redraw the screen
  /// that shelved it, not leave it offering to shelve it again.
  Stream<Book?> watchBook(String id) =>
      (select(books)..where((b) => b.id.equals(id))).watchSingleOrNull();

  /// Finds the book a previously-seen PDF belongs to.
  ///
  /// This is what lets a reader re-add the same file on a new phone and land
  /// back on their existing plan instead of starting over.
  Future<Book?> findBookByFileHash(String sha256) async {
    final query = select(bookFingerprints).join(
      [innerJoin(books, books.id.equalsExp(bookFingerprints.bookId))],
    )..where(bookFingerprints.sha256.equals(sha256) & books.deletedAt.isNull());

    final row = await query.getSingleOrNull();
    return row?.readTable(books);
  }

  /// Books whose PDF is not on this device, for the "locate your files" flow.
  Stream<List<Book>> watchBooksMissingFiles() {
    final query =
        select(books).join([
          leftOuterJoin(
            localBookFiles,
            localBookFiles.bookId.equalsExp(books.id),
          ),
        ])..where(
          books.deletedAt.isNull() &
              (localBookFiles.bookId.isNull() |
                  localBookFiles.isAvailable.equals(false)),
        );

    return query.map((row) => row.readTable(books)).watch();
  }

  /// Saves a freshly imported PDF as a book, its fingerprint and its local file
  /// in one transaction, so a half-registered book can never exist.
  Future<void> insertImportedBook({
    required String bookId,
    required String fingerprintId,
    required String title,
    String? author,
    required int pageCount,
    required String sha256,
    required int sizeBytes,
    required String originalFileName,
    required String relativePath,
    required DateTime now,
  }) {
    return transaction(() async {
      await into(books).insert(
        BooksCompanion.insert(
          id: bookId,
          title: title,
          author: Value(author),
          pageCount: pageCount,
          createdAt: now,
          updatedAt: now,
        ),
      );
      await into(bookFingerprints).insert(
        BookFingerprintsCompanion.insert(
          id: fingerprintId,
          bookId: bookId,
          sha256: sha256,
          pageCount: pageCount,
          sizeBytes: sizeBytes,
          originalFileName: Value(originalFileName),
          createdAt: now,
        ),
      );
      await into(localBookFiles).insert(
        LocalBookFilesCompanion.insert(
          bookId: bookId,
          relativePath: relativePath,
          linkedAt: now,
        ),
      );

      // The local file row is not queued: the PDF and where it sits on this
      // phone are the two things that deliberately never leave it.
      await _enqueueBook(bookId);
      final fingerprint = await (select(
        bookFingerprints,
      )..where((f) => f.id.equals(fingerprintId))).getSingle();
      await _enqueue(
        SyncEntity.fingerprints,
        fingerprintId,
        SyncOp.upsert,
        fingerprintDto(fingerprint).toJson(),
      );
    });
  }

  /// Points an existing book at a file on this device.
  ///
  /// Used both when a reader re-adds a book whose file went missing and, later,
  /// when signing in on a new phone and locating the PDFs again.
  Future<void> linkBookFile({
    required String bookId,
    required String relativePath,
    required DateTime now,
  }) {
    return into(localBookFiles).insertOnConflictUpdate(
      LocalBookFilesCompanion.insert(
        bookId: bookId,
        relativePath: relativePath,
        isAvailable: const Value(true),
        linkedAt: now,
      ),
    );
  }

  /// Accepts a file the book has never seen as another copy of it.
  ///
  /// This is the manual end of the locate flow: the hash matched nothing, so
  /// the reader vouched for the file themselves. The new fingerprint is added
  /// rather than replacing the old one — the original copy may still exist on
  /// another phone, and it must keep relinking there.
  ///
  /// When the copy has a different page count, every stored page number now
  /// refers to a file that no longer exists on this device, so the plan has to
  /// move with it. [rescaleProgress] picks which way: proportionally, or by
  /// keeping the numbers and clamping what falls off the end.
  ///
  /// The reading log is left alone in both cases. It is append-only history —
  /// what was read on a given day happened, and rewriting it to fit a file the
  /// reader picked today would be inventing a past.
  ///
  /// [pagesPerDay] is left alone too: the daily portion is the promise the
  /// reader made, and a relink is not a renegotiation of it.
  Future<void> relinkBookFile({
    required String bookId,
    required String relativePath,
    required String fingerprintId,
    required String sha256,
    required int filePageCount,
    required int sizeBytes,
    String? originalFileName,
    required bool rescaleProgress,
    required DateTime now,
  }) {
    return transaction(() async {
      final book = await (select(
        books,
      )..where((b) => b.id.equals(bookId))).getSingle();

      await into(bookFingerprints).insert(
        BookFingerprintsCompanion.insert(
          id: fingerprintId,
          bookId: bookId,
          sha256: sha256,
          pageCount: filePageCount,
          sizeBytes: sizeBytes,
          originalFileName: Value(originalFileName),
          createdAt: now,
        ),
      );
      await linkBookFile(bookId: bookId, relativePath: relativePath, now: now);

      final fingerprint = await (select(
        bookFingerprints,
      )..where((f) => f.id.equals(fingerprintId))).getSingle();
      await _enqueue(
        SyncEntity.fingerprints,
        fingerprintId,
        SyncOp.upsert,
        fingerprintDto(fingerprint).toJson(),
      );

      if (filePageCount == book.pageCount) return;

      final was = book.pageCount;
      await (update(books)..where((b) => b.id.equals(bookId))).write(
        BooksCompanion(pageCount: Value(filePageCount), updatedAt: Value(now)),
      );
      await _enqueueBook(bookId);

      int moved(int page) => rescaleProgress
          ? rescalePage(page, fromCount: was, toCount: filePageCount)
          : clampPage(page, toCount: filePageCount);

      final plans = await (select(
        readingPlans,
      )..where((p) => p.bookId.equals(bookId))).get();

      for (final plan in plans) {
        final start = moved(plan.startPage);
        final end = moved(plan.endPage);
        await (update(readingPlans)..where((p) => p.id.equals(plan.id))).write(
          ReadingPlansCompanion(
            // A plan that started on page 1 has to keep starting somewhere, so
            // the floor is a page rather than the zero sentinel.
            startPage: Value(start < 1 ? 1 : start),
            endPage: Value(end < start ? start : end),
            lastPageRead: Value(moved(plan.lastPageRead)),
            updatedAt: Value(now),
          ),
        );
        await _enqueuePlan(plan.id);
      }
    });
  }

  /// The book's stored relative path, or null when no file is linked here.
  Future<String?> localFilePath(String bookId) async {
    final row =
        await (select(localBookFiles)..where(
              (f) => f.bookId.equals(bookId) & f.isAvailable.equals(true),
            ))
            .getSingleOrNull();
    return row?.relativePath;
  }

  /// Whether this device currently holds the book's PDF.
  Future<bool> hasLocalFile(String bookId) async {
    final row =
        await (select(localBookFiles)..where(
              (f) => f.bookId.equals(bookId) & f.isAvailable.equals(true),
            ))
            .getSingleOrNull();
    return row != null;
  }

  // -------------------------------------------------------------------------
  // Plans
  // -------------------------------------------------------------------------

  Future<ReadingPlan?> activePlanFor(String bookId) {
    return (select(readingPlans)
          ..where((p) => p.bookId.equals(bookId) & p.isActive.equals(true))
          ..limit(1))
        .getSingleOrNull();
  }

  Stream<ReadingPlan?> watchActivePlanFor(String bookId) {
    return (select(readingPlans)
          ..where((p) => p.bookId.equals(bookId) & p.isActive.equals(true))
          ..limit(1))
        .watchSingleOrNull();
  }

  /// Every active plan, keyed by book.
  ///
  /// The library draws a progress rule on each row; one query for the whole
  /// shelf beats one per row, and a map is what the row builder actually wants.
  Stream<Map<String, ReadingPlan>> watchActivePlans() {
    return (select(readingPlans)..where((p) => p.isActive.equals(true)))
        .watch()
        .map((plans) => {for (final plan in plans) plan.bookId: plan});
  }

  /// Creates the book's plan, or rewrites it in place if it already has one.
  ///
  /// Editing updates the existing row rather than deactivating it and inserting
  /// a replacement, because [ReadingPlans.lastPageRead] and the reading log both
  /// hang off the plan id — a new row would silently reset the reader to zero.
  /// Progress is deliberately left untouched: changing the goal does not unread
  /// the pages.
  ///
  /// Returns the id of the plan that now holds the goal.
  Future<String> savePlan({
    required String bookId,
    required PlanSpec spec,
    required DateTime now,
    required String newPlanId,
  }) {
    return transaction(() async {
      final existing = await activePlanFor(bookId);
      if (existing != null) {
        await (update(
          readingPlans,
        )..where((p) => p.id.equals(existing.id))).write(
          ReadingPlansCompanion(
            mode: Value(spec.mode),
            startPage: Value(spec.startPage),
            endPage: Value(spec.endPage),
            startDate: Value(spec.startDate),
            targetEndDate: Value(spec.targetEndDate),
            pagesPerDay: Value(spec.pagesPerDay),
            updatedAt: Value(now),
          ),
        );
        await _enqueuePlan(existing.id);
        return existing.id;
      }

      await into(readingPlans).insert(
        ReadingPlansCompanion.insert(
          id: newPlanId,
          bookId: bookId,
          mode: spec.mode,
          startPage: spec.startPage,
          endPage: spec.endPage,
          startDate: spec.startDate,
          targetEndDate: spec.targetEndDate,
          pagesPerDay: spec.pagesPerDay,
          createdAt: now,
          updatedAt: now,
        ),
      );
      await _enqueuePlan(newPlanId);
      return newPlanId;
    });
  }

  /// Stops the plan reminding and stops the clock counting against it.
  ///
  /// Pausing twice is a no-op rather than an error: the caller is a button,
  /// and a double tap should not lose the original pause date.
  Future<void> pausePlan(String planId, DateTime now) {
    return transaction(() async {
      final changed =
          await (update(
            readingPlans,
          )..where((p) => p.id.equals(planId) & p.pausedAt.isNull())).write(
            ReadingPlansCompanion(pausedAt: Value(now), updatedAt: Value(now)),
          );
      // Nothing changed means the plan was already paused. Queueing anyway
      // would push a row whose `updatedAt` moved for no reason, and hand the
      // conflict to a device that has something newer to say.
      if (changed > 0) await _enqueuePlan(planId);
    });
  }

  /// Restarts the plan, banking the days it spent paused.
  ///
  /// The days are added to a running total rather than kept as a history: only
  /// the total is ever used, by [scheduleStatus], and a pause log nobody reads
  /// is a table to migrate for nothing.
  Future<void> resumePlan(String planId, DateTime now) {
    return transaction(() async {
      final plan = await (select(
        readingPlans,
      )..where((p) => p.id.equals(planId))).getSingleOrNull();
      final pausedAt = plan?.pausedAt;
      if (plan == null || pausedAt == null) return;

      final elapsed = daysBetween(pausedAt, now);
      await (update(readingPlans)..where((p) => p.id.equals(planId))).write(
        ReadingPlansCompanion(
          pausedAt: const Value(null),
          pausedDays: Value(plan.pausedDays + (elapsed < 0 ? 0 : elapsed)),
          updatedAt: Value(now),
        ),
      );
      await _enqueuePlan(planId);
    });
  }

  Stream<List<ReadingSession>> watchSessionsFor(String planId) {
    return (select(readingSessions)
          ..where((s) => s.planId.equals(planId) & s.deletedAt.isNull())
          ..orderBy([(s) => OrderingTerm.asc(s.ordinal)]))
        .watch();
  }

  /// Rebuilds a plan's session list in one transaction.
  ///
  /// Sessions are replaced wholesale rather than diffed: the ordinals seed
  /// notification ids, so a stable full rewrite is easier to reason about than
  /// patching individual rows.
  ///
  /// The outgoing rows are tombstoned rather than dropped. A row that simply
  /// vanishes cannot be described to the server, and the copy left behind
  /// there would come back on the next pull as a second reminder.
  Future<void> replaceSessions(
    String planId,
    List<ReadingSessionsCompanion> sessions, {
    DateTime? now,
  }) {
    final at = now ?? DateTime.now();
    final keep = {for (final s in sessions) s.id.value};

    return transaction(() async {
      // Only the ids that are genuinely gone are tombstoned. A caller is free
      // to reuse an id — the ordinal-based scheme rather invites it — and an
      // id that comes back was never removed in the first place.
      final retired =
          await (select(readingSessions)..where(
                (s) =>
                    s.planId.equals(planId) &
                    s.deletedAt.isNull() &
                    s.id.isNotIn(keep),
              ))
              .get();

      for (final row in retired) {
        final tombstone = row.copyWith(deletedAt: Value(at), updatedAt: at);
        await (update(
          readingSessions,
        )..where((s) => s.id.equals(row.id))).write(
          ReadingSessionsCompanion(deletedAt: Value(at), updatedAt: Value(at)),
        );
        await _enqueue(
          SyncEntity.sessions,
          row.id,
          SyncOp.delete,
          sessionDto(tombstone).toJson(),
        );
      }

      for (final companion in sessions) {
        // Explicitly un-tombstoned: an id that was retired and is now being
        // written again is a session the reader brought back, and an absent
        // `deletedAt` on the companion would leave the old one in place.
        await into(readingSessions).insertOnConflictUpdate(
          companion.copyWith(deletedAt: const Value(null)),
        );
        final row = await (select(
          readingSessions,
        )..where((s) => s.id.equals(companion.id.value))).getSingle();
        await _enqueue(
          SyncEntity.sessions,
          row.id,
          SyncOp.upsert,
          sessionDto(row).toJson(),
        );
      }
    });
  }

  /// Every session of every book still being read, in time order.
  ///
  /// Finished and archived books fall out on their own: [recordReading] flips
  /// the book's status, so completing a book drops off both the day's list and
  /// the reminder schedule without anything having to clean up after it.
  Stream<List<({Book book, ReadingPlan plan, ReadingSession session})>>
  watchLivePlanSessions({bool remindersOnly = false}) {
    final query = select(readingSessions).join([
      innerJoin(
        readingPlans,
        readingPlans.id.equalsExp(readingSessions.planId),
      ),
      innerJoin(books, books.id.equalsExp(readingPlans.bookId)),
    ])..orderBy([OrderingTerm.asc(readingSessions.ordinal)]);

    // A paused plan owes nothing today and reminds about nothing. It stays in
    // the library, where the reader can see it and resume it.
    var filter =
        readingSessions.deletedAt.isNull() &
        readingPlans.isActive.equals(true) &
        readingPlans.pausedAt.isNull() &
        books.status.equalsValue(BookStatus.reading) &
        books.deletedAt.isNull();
    // A session with its reminder switched off still owes its pages; only the
    // notification layer cares about the flag.
    if (remindersOnly) filter = filter & readingSessions.isEnabled.equals(true);
    query.where(filter);

    return query
        .map(
          (row) => (
            book: row.readTable(books),
            plan: row.readTable(readingPlans),
            session: row.readTable(readingSessions),
          ),
        )
        .watch();
  }

  /// Every session that should currently have a reminder scheduled.
  Stream<List<({Book book, ReadingPlan plan, ReadingSession session})>>
  watchDueReminders() => watchLivePlanSessions(remindersOnly: true);

  /// Pages credited to [day], per plan.
  ///
  /// One query for the whole screen: the day's layout needs to know where each
  /// book stood when the day began, which is today's total subtracted from
  /// current progress.
  Stream<Map<String, int>> watchPagesReadOn(DateTime day) {
    final total = readingLog.pagesRead.sum();
    final query = selectOnly(readingLog)
      ..addColumns([readingLog.planId, total])
      ..where(readingLog.readDate.equals(dateOnly(day)))
      ..groupBy([readingLog.planId]);

    return query.watch().map(
      (rows) => {
        for (final row in rows)
          row.read(readingLog.planId)!: row.read(total) ?? 0,
      },
    );
  }

  /// Pages a day the reader is currently committed to, across every book.
  ///
  /// What a full day means for the library calendar. Only plans that owe
  /// something today count: a finished book, a paused plan or a removed book
  /// owes nothing, and counting them would make every day look like a shortfall
  /// against a promise nobody made.
  Stream<int> watchCommittedPagesPerDay() {
    final total = readingPlans.pagesPerDay.sum();
    final query =
        selectOnly(
            readingPlans,
          ).join([innerJoin(books, books.id.equalsExp(readingPlans.bookId))])
          ..addColumns([total])
          ..where(
            readingPlans.isActive.equals(true) &
                readingPlans.pausedAt.isNull() &
                books.status.equalsValue(BookStatus.reading) &
                books.deletedAt.isNull(),
          );

    return query.watchSingle().map((row) => row.read(total) ?? 0);
  }

  /// Pages read per calendar day from [from] onward, for one plan or for all.
  ///
  /// Keyed by the day rather than returned as rows, because both callers are
  /// charts: they walk a fixed range of dates and ask each one what it holds,
  /// and days with no reading have to come back as absent rather than missing.
  ///
  /// [planId] null totals every book, which is what the stats screen means by
  /// "pages a day" — the reader read them all, whichever book they came from.
  Stream<Map<DateTime, int>> watchDailyPagesFor(
    String? planId, {
    required DateTime from,
  }) {
    final total = readingLog.pagesRead.sum();
    final query = selectOnly(readingLog)
      ..addColumns([readingLog.readDate, total])
      ..where(
        (planId == null
                ? const Constant(true)
                : readingLog.planId.equals(planId)) &
            readingLog.readDate.isBiggerOrEqualValue(dateOnly(from)),
      )
      ..groupBy([readingLog.readDate]);

    return query.watch().map(
      (rows) => {
        for (final row in rows)
          row.read(readingLog.readDate)!: row.read(total) ?? 0,
      },
    );
  }

  /// Every finished book together with the plan it was finished under.
  ///
  /// An inner join, so a book finished before it ever had a plan does not
  /// appear: the stats screen reports how long each ختمة took, and a book with
  /// no plan has no start date to measure from.
  Stream<List<({Book book, ReadingPlan plan})>> watchFinishedBooks() {
    final query =
        select(books).join([
          innerJoin(readingPlans, readingPlans.bookId.equalsExp(books.id)),
        ])..where(
          books.status.equalsValue(BookStatus.finished) &
              books.deletedAt.isNull() &
              readingPlans.isActive.equals(true),
        );

    return query
        .map(
          (row) =>
              (book: row.readTable(books), plan: row.readTable(readingPlans)),
        )
        .watch();
  }

  /// The last day each plan was read on, for measuring how long a book took.
  Stream<Map<String, DateTime>> watchLastReadDates() {
    final last = readingLog.readDate.max();
    final query = selectOnly(readingLog)
      ..addColumns([readingLog.planId, last])
      ..groupBy([readingLog.planId]);

    return query.watch().map(
      (rows) => Map.fromEntries(
        rows
            .map(
              (row) => (id: row.read(readingLog.planId)!, date: row.read(last)),
            )
            // A group with no maximum cannot happen in SQL, but the column is
            // typed nullable and a silent `!` here would be a crash later.
            .where((row) => row.date != null)
            .map((row) => MapEntry(row.id, row.date!)),
      ),
    );
  }

  /// Moves a book between shelves.
  ///
  /// The plan is left alone. Archiving a half-read book and putting it back
  /// months later should find the goal exactly where it was — and a plan on a
  /// non-reading book already owes nothing, because every query that drives
  /// today's list and the reminders filters on the book's status.
  Future<void> setBookStatus(String bookId, BookStatus status, DateTime now) {
    return transaction(() async {
      await (update(books)..where((b) => b.id.equals(bookId))).write(
        BooksCompanion(status: Value(status), updatedAt: Value(now)),
      );
      await _enqueueBook(bookId);
    });
  }

  /// Removes a book from the library.
  ///
  /// A tombstone rather than a real delete, because the removal has to travel:
  /// a row that simply vanished from this phone cannot be described in a push,
  /// so the server would keep its copy and hand the book back on the next pull.
  ///
  /// The plan, its sessions and the reading log are left in place. They hang off
  /// the book, and every query that drives a screen or a reminder already
  /// filters on `books.deletedAt` — so the reminders stop on their own, through
  /// the same stream that scheduled them, rather than through a second path
  /// that could disagree with the first.
  ///
  /// What does go, immediately and completely, is everything device-local: the
  /// file record and the saved reading position. The PDF itself is the caller's
  /// to delete — this class does not own the filesystem.
  Future<void> deleteBook(String bookId, DateTime now) {
    return transaction(() async {
      await (update(books)..where((b) => b.id.equals(bookId))).write(
        BooksCompanion(deletedAt: Value(now), updatedAt: Value(now)),
      );
      // Queued as a delete rather than an upsert: `_enqueueBook` reads the row
      // back and sees the tombstone.
      await _enqueueBook(bookId);

      await (delete(
        localBookFiles,
      )..where((f) => f.bookId.equals(bookId))).go();
      await (delete(readerStates)..where((s) => s.bookId.equals(bookId))).go();
    });
  }

  /// Reconstructs the pure [PlanSpec] used by all scheduling arithmetic.
  PlanSpec specOf(ReadingPlan plan) => PlanSpec(
    mode: plan.mode,
    startPage: plan.startPage,
    endPage: plan.endPage,
    startDate: plan.startDate,
    targetEndDate: plan.targetEndDate,
    pagesPerDay: plan.pagesPerDay,
  );

  // -------------------------------------------------------------------------
  // Progress
  // -------------------------------------------------------------------------

  /// Records a stretch of reading and advances the plan.
  ///
  /// The log is append-only and [ReadingPlans.lastPageRead] only ever moves
  /// forward, so re-reading an earlier chapter cannot walk progress backwards.
  /// Returns true when this reading finished the book.
  Future<bool> recordReading({
    required String planId,
    String? sessionId,
    required int fromPage,
    required int toPage,
    required DateTime readAt,
    int durationSeconds = 0,
    required String logId,
  }) {
    return transaction(() async {
      final plan = await (select(
        readingPlans,
      )..where((p) => p.id.equals(planId))).getSingle();

      await into(readingLog).insert(
        ReadingLogCompanion.insert(
          id: logId,
          planId: planId,
          sessionId: Value(sessionId),
          // Not `dateOnly`: reading at one in the morning belongs to the day
          // the reader is still awake in. See [readingDay].
          readDate: readingDay(readAt),
          fromPage: fromPage,
          toPage: toPage,
          pagesRead: toPage - fromPage + 1,
          durationSeconds: Value(durationSeconds),
          createdAt: readAt,
        ),
      );

      final advanced = toPage > plan.lastPageRead ? toPage : plan.lastPageRead;
      await (update(readingPlans)..where((p) => p.id.equals(planId))).write(
        ReadingPlansCompanion(
          lastPageRead: Value(advanced),
          updatedAt: Value(readAt),
        ),
      );

      final finished = advanced >= plan.endPage;
      if (finished) {
        await (update(books)..where((b) => b.id.equals(plan.bookId))).write(
          BooksCompanion(
            status: const Value(BookStatus.finished),
            updatedAt: Value(readAt),
          ),
        );
      }

      final entry = await (select(
        readingLog,
      )..where((l) => l.id.equals(logId))).getSingle();
      await _enqueue(
        SyncEntity.logEntries,
        logId,
        SyncOp.upsert,
        logEntryDto(entry).toJson(),
      );
      await _enqueuePlan(planId);
      if (finished) await _enqueueBook(plan.bookId);

      return finished;
    });
  }

  /// Pages credited to [day] for a plan, used to knock down today's quota.
  Future<int> pagesReadOn(String planId, DateTime day) async {
    final total = readingLog.pagesRead.sum();
    final query = selectOnly(readingLog)
      ..addColumns([total])
      ..where(
        readingLog.planId.equals(planId) &
            readingLog.readDate.equals(dateOnly(day)),
      );
    final row = await query.getSingle();
    return row.read(total) ?? 0;
  }

  /// Every minute the reader has spent inside this plan, added up.
  ///
  /// Sittings are summed rather than kept as a running total on the plan: the
  /// log already owns when reading happened, and a second copy of the same
  /// number is a second thing that can be wrong. Sittings logged before the
  /// clock existed count as zero, which is honest — nobody measured them.
  Future<Duration> readingTimeFor(String planId) async {
    final total = readingLog.durationSeconds.sum();
    final query = selectOnly(readingLog)
      ..addColumns([total])
      ..where(readingLog.planId.equals(planId));
    final row = await query.getSingle();
    return Duration(seconds: row.read(total) ?? 0);
  }

  /// The reader's measured pace, for one plan or for the whole library.
  ///
  /// Sittings with a zero duration are excluded from *both* totals, not just
  /// from the time. They are the ones logged before the clock existed, and
  /// letting their pages through would divide a real number of seconds by an
  /// inflated number of pages and report every reader as twice as fast as they
  /// are. Excluding them makes the sample smaller and honest.
  ///
  /// [planId] null covers every book, which is what an estimate for today
  /// wants: the reader has one reading speed, not one per book.
  ///
  /// [from] limits the sample to reading on or after that day, for the screens
  /// that report a window rather than a lifetime.
  Stream<ReadingPace> watchReadingPace({String? planId, DateTime? from}) {
    final pages = readingLog.pagesRead.sum();
    final seconds = readingLog.durationSeconds.sum();
    final query = selectOnly(readingLog)
      ..addColumns([pages, seconds])
      ..where(
        readingLog.durationSeconds.isBiggerThanValue(0) &
            (planId == null
                ? const Constant(true)
                : readingLog.planId.equals(planId)) &
            (from == null
                ? const Constant(true)
                : readingLog.readDate.isBiggerOrEqualValue(dateOnly(from))),
      );

    return query.watchSingle().map(
      (row) => ReadingPace(
        pages: row.read(pages) ?? 0,
        time: Duration(seconds: row.read(seconds) ?? 0),
      ),
    );
  }

  // -------------------------------------------------------------------------
  // Sync outbox
  // -------------------------------------------------------------------------

  /// Inserts one outbox row. Called inside the same transaction as the
  /// original mutation so the two are atomic.
  Future<void> _enqueue(
    String entity,
    String entityId,
    SyncOp op,
    Map<String, dynamic> json,
  ) {
    return into(syncOutbox).insert(
      SyncOutboxCompanion.insert(
        entity: entity,
        entityId: entityId,
        op: op,
        payloadJson: jsonEncode(json),
        createdAt: DateTime.now(),
      ),
    );
  }

  /// Queues a book as it now stands.
  ///
  /// The row is re-read rather than assembled from the caller's arguments, so
  /// what gets queued is what was actually stored — a snapshot that disagrees
  /// with the database is a divergence waiting for the next device.
  Future<void> _enqueueBook(String bookId) async {
    final row = await (select(
      books,
    )..where((b) => b.id.equals(bookId))).getSingle();
    await _enqueue(
      SyncEntity.books,
      bookId,
      row.deletedAt == null ? SyncOp.upsert : SyncOp.delete,
      bookDto(row).toJson(),
    );
  }

  Future<void> _enqueuePlan(String planId) async {
    final row = await (select(
      readingPlans,
    )..where((p) => p.id.equals(planId))).getSingle();
    await _enqueue(
      SyncEntity.plans,
      planId,
      SyncOp.upsert,
      planDto(row).toJson(),
    );
  }

  /// Every unsent outbox row, oldest first.
  Future<List<SyncOutboxData>> pendingOutboxEntries() {
    return (select(
      syncOutbox,
    )..orderBy([(e) => OrderingTerm.asc(e.createdAt)])).get();
  }

  /// How many changes are still waiting to be sent, kept live.
  ///
  /// Shown on the settings screen, where "everything is saved" has to be
  /// something the reader can check rather than something we assert.
  Stream<int> watchPendingSyncCount() {
    final count = syncOutbox.id.count();
    return (selectOnly(
      syncOutbox,
    )..addColumns([count])).map((row) => row.read(count) ?? 0).watchSingle();
  }

  /// Removes outbox rows that were successfully pushed.
  Future<void> deleteOutboxEntries(List<int> ids) {
    return (delete(syncOutbox)..where((e) => e.id.isIn(ids))).go();
  }

  /// Bumps the attempt counter for rows that failed.
  Future<void> incrementOutboxAttempts(List<int> ids) async {
    for (final id in ids) {
      await (update(syncOutbox)..where((e) => e.id.equals(id))).write(
        SyncOutboxCompanion.custom(
          attempts: syncOutbox.attempts + const Constant(1),
        ),
      );
    }
  }

  /// Queues every synced row this device holds.
  ///
  /// Called once, when a reader who has been using the app without an account
  /// signs in for the first time. Everything they built as a guest was written
  /// before there was anywhere to send it, so the outbox is empty and the
  /// library would otherwise look, from the server's side, like a brand new
  /// and empty account.
  /// Everything on this phone that is worth keeping, as one payload.
  ///
  /// Exactly what the account carries and nothing more: no PDFs, no local file
  /// paths, no reading positions, no outbox. The same rule the sync follows,
  /// for the same reason — the file is the reader's and never leaves the phone,
  /// and where it happens to sit on *this* phone means nothing on the next one.
  ///
  /// Tombstones travel too. A backup that quietly resurrected every book the
  /// reader had removed would be worse than no backup.
  Future<SyncPayload> exportLocalData() async {
    return SyncPayload(
      books: [for (final row in await select(books).get()) bookDto(row)],
      fingerprints: [
        for (final row in await select(bookFingerprints).get())
          fingerprintDto(row),
      ],
      plans: [for (final row in await select(readingPlans).get()) planDto(row)],
      sessions: [
        for (final row in await select(readingSessions).get()) sessionDto(row),
      ],
      logEntries: [
        for (final row in await select(readingLog).get()) logEntryDto(row),
      ],
    );
  }

  /// Folds a backup into whatever is already here.
  ///
  /// A merge, not a replacement, and deliberately the same merge a pull from
  /// the server uses: restoring onto a phone that has been read on since must
  /// not throw that reading away. So progress takes the larger page, the log is
  /// appended by id, and everything else is decided by which copy was edited
  /// last.
  ///
  /// The order matters — a plan cannot be inserted before its book, and a
  /// session cannot be inserted before its plan.
  Future<void> importBackup(SyncPayload backup) async {
    await mergeBooks(backup.books);
    await mergeFingerprints(backup.fingerprints);
    await mergePlans(backup.plans);
    await mergeSessions(backup.sessions);
    await mergeLogEntries(backup.logEntries);
  }

  Future<void> seedOutboxFromLocalData() {
    return transaction(() async {
      for (final row in await select(books).get()) {
        await _enqueue(
          SyncEntity.books,
          row.id,
          row.deletedAt == null ? SyncOp.upsert : SyncOp.delete,
          bookDto(row).toJson(),
        );
      }
      for (final row in await select(bookFingerprints).get()) {
        await _enqueue(
          SyncEntity.fingerprints,
          row.id,
          SyncOp.upsert,
          fingerprintDto(row).toJson(),
        );
      }
      for (final row in await select(readingPlans).get()) {
        await _enqueue(
          SyncEntity.plans,
          row.id,
          SyncOp.upsert,
          planDto(row).toJson(),
        );
      }
      for (final row in await select(readingSessions).get()) {
        await _enqueue(
          SyncEntity.sessions,
          row.id,
          row.deletedAt == null ? SyncOp.upsert : SyncOp.delete,
          sessionDto(row).toJson(),
        );
      }
      for (final row in await select(readingLog).get()) {
        await _enqueue(
          SyncEntity.logEntries,
          row.id,
          SyncOp.upsert,
          logEntryDto(row).toJson(),
        );
      }
    });
  }

  /// Empties the outbox without sending anything.
  ///
  /// Used on sign-out: the queue belongs to the account that filled it, and
  /// carrying it into the next sign-in would push one reader's library into
  /// another reader's account.
  Future<void> clearOutbox() => delete(syncOutbox).go();

  /// Discards outbox rows that failed too many times.
  Future<void> deleteStaleOutboxEntries({int maxAttempts = 5}) {
    return (delete(
      syncOutbox,
    )..where((e) => e.attempts.isBiggerOrEqualValue(maxAttempts))).go();
  }

  // -------------------------------------------------------------------------
  // Merge (pull phase) — same three rules as the server
  // -------------------------------------------------------------------------

  /// Merges remote books using last-write-wins on [BookDto.updatedAt].
  Future<void> mergeBooks(List<BookDto> remote) {
    return transaction(() async {
      for (final dto in remote) {
        final local = await (select(
          books,
        )..where((b) => b.id.equals(dto.id))).getSingleOrNull();

        if (local == null) {
          await into(books).insert(
            BooksCompanion.insert(
              id: dto.id,
              title: dto.title,
              author: Value(dto.author),
              pageCount: dto.pageCount,
              pageLabelOffset: Value(dto.pageLabelOffset),
              status: Value(
                BookStatus.values.firstWhere(
                  (s) => s.name.toLowerCase() == dto.status.toLowerCase(),
                  orElse: () => BookStatus.reading,
                ),
              ),
              createdAt: dto.createdAt,
              updatedAt: dto.updatedAt,
              deletedAt: Value(dto.deletedAt),
            ),
          );
        } else if (!dto.updatedAt.isBefore(local.updatedAt)) {
          await (update(books)..where((b) => b.id.equals(dto.id))).write(
            BooksCompanion(
              title: Value(dto.title),
              author: Value(dto.author),
              pageCount: Value(dto.pageCount),
              pageLabelOffset: Value(dto.pageLabelOffset),
              status: Value(
                BookStatus.values.firstWhere(
                  (s) => s.name.toLowerCase() == dto.status.toLowerCase(),
                  orElse: () => BookStatus.reading,
                ),
              ),
              updatedAt: Value(dto.updatedAt),
              deletedAt: Value(dto.deletedAt),
            ),
          );
        }
      }
    });
  }

  /// Merges remote fingerprints. Insert-if-absent by id.
  Future<void> mergeFingerprints(List<FingerprintDto> remote) {
    return transaction(() async {
      for (final dto in remote) {
        final exists = await (select(
          bookFingerprints,
        )..where((f) => f.id.equals(dto.id))).getSingleOrNull();
        if (exists != null) continue;

        await into(bookFingerprints).insert(
          BookFingerprintsCompanion.insert(
            id: dto.id,
            bookId: dto.bookId,
            sha256: dto.sha256.toLowerCase(),
            pageCount: dto.pageCount,
            sizeBytes: dto.sizeBytes,
            originalFileName: Value(dto.originalFileName),
            createdAt: dto.createdAt,
          ),
        );
      }
    });
  }

  /// Merges remote plans: last-write-wins on [PlanDto.updatedAt], but
  /// [PlanDto.lastPageRead] always takes the MAX.
  Future<void> mergePlans(List<PlanDto> remote) {
    return transaction(() async {
      for (final dto in remote) {
        final local = await (select(
          readingPlans,
        )..where((p) => p.id.equals(dto.id))).getSingleOrNull();

        final mode = PlanMode.values.firstWhere(
          (m) => m.name.toLowerCase() == dto.mode.toLowerCase(),
          orElse: () => PlanMode.byPagesPerDay,
        );
        final startDate = DateTime.parse(dto.startDate);
        final targetEndDate = DateTime.parse(dto.targetEndDate);

        if (local == null) {
          await into(readingPlans).insert(
            ReadingPlansCompanion.insert(
              id: dto.id,
              bookId: dto.bookId,
              mode: mode,
              startPage: dto.startPage,
              endPage: dto.endPage,
              startDate: startDate,
              targetEndDate: targetEndDate,
              pagesPerDay: dto.pagesPerDay,
              lastPageRead: Value(dto.lastPageRead),
              isActive: Value(dto.isActive),
              pausedAt: Value(dto.pausedAt),
              pausedDays: Value(dto.pausedDays),
              createdAt: dto.createdAt,
              updatedAt: dto.updatedAt,
            ),
          );
        } else {
          // Progress always takes the maximum, regardless of who wins LWW.
          final furthest = dto.lastPageRead > local.lastPageRead
              ? dto.lastPageRead
              : local.lastPageRead;

          if (dto.updatedAt.isBefore(local.updatedAt)) {
            // The remote row is older — only its progress can contribute.
            if (furthest != local.lastPageRead) {
              await (update(readingPlans)..where((p) => p.id.equals(dto.id)))
                  .write(ReadingPlansCompanion(lastPageRead: Value(furthest)));
            }
          } else {
            await (update(
              readingPlans,
            )..where((p) => p.id.equals(dto.id))).write(
              ReadingPlansCompanion(
                mode: Value(mode),
                startPage: Value(dto.startPage),
                endPage: Value(dto.endPage),
                startDate: Value(startDate),
                targetEndDate: Value(targetEndDate),
                pagesPerDay: Value(dto.pagesPerDay),
                lastPageRead: Value(furthest),
                isActive: Value(dto.isActive),
                pausedAt: Value(dto.pausedAt),
                pausedDays: Value(dto.pausedDays),
                updatedAt: Value(dto.updatedAt),
              ),
            );
          }
        }
      }
    });
  }

  /// Merges remote sessions using last-write-wins on [SessionDto.updatedAt].
  Future<void> mergeSessions(List<SessionDto> remote) {
    return transaction(() async {
      for (final dto in remote) {
        final local = await (select(
          readingSessions,
        )..where((s) => s.id.equals(dto.id))).getSingleOrNull();

        if (local == null) {
          await into(readingSessions).insert(
            ReadingSessionsCompanion.insert(
              id: dto.id,
              planId: dto.planId,
              ordinal: dto.ordinal,
              timeOfDayMinutes: dto.timeOfDayMinutes,
              pagesShare: dto.pagesShare,
              daysOfWeek: Value(dto.daysOfWeek),
              isEnabled: Value(dto.isEnabled),
              updatedAt: dto.updatedAt,
              deletedAt: Value(dto.deletedAt),
            ),
          );
        } else if (!dto.updatedAt.isBefore(local.updatedAt)) {
          await (update(
            readingSessions,
          )..where((s) => s.id.equals(dto.id))).write(
            ReadingSessionsCompanion(
              ordinal: Value(dto.ordinal),
              timeOfDayMinutes: Value(dto.timeOfDayMinutes),
              pagesShare: Value(dto.pagesShare),
              daysOfWeek: Value(dto.daysOfWeek),
              isEnabled: Value(dto.isEnabled),
              updatedAt: Value(dto.updatedAt),
              deletedAt: Value(dto.deletedAt),
            ),
          );
        }
      }
    });
  }

  /// Merges remote log entries. Append-only: existing entries are never
  /// modified, and a duplicate id is silently ignored.
  Future<void> mergeLogEntries(List<LogEntryDto> remote) {
    return transaction(() async {
      for (final dto in remote) {
        final exists = await (select(
          readingLog,
        )..where((l) => l.id.equals(dto.id))).getSingleOrNull();
        if (exists != null) continue;

        await into(readingLog).insert(
          ReadingLogCompanion.insert(
            id: dto.id,
            planId: dto.planId,
            sessionId: Value(dto.sessionId),
            readDate: DateTime.parse(dto.readDate),
            fromPage: dto.fromPage,
            toPage: dto.toPage,
            pagesRead: dto.pagesRead,
            durationSeconds: Value(dto.durationSeconds),
            createdAt: dto.createdAt,
          ),
        );
      }
    });
  }
}

/// Single database instance for the app, closed when the app shuts down.
final appDatabaseProvider = Provider<AppDatabase>((ref) {
  final db = AppDatabase();
  ref.onDispose(db.close);
  return db;
});
