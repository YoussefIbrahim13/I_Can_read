import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../planning/plan_math.dart';
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
  int get schemaVersion => 2;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onUpgrade: (m, from, to) async {
      if (from < 2) {
        // Pausing a plan, added once it was clear that a deliberate break and
        // a missed day are not the same thing.
        await m.addColumn(readingPlans, readingPlans.pausedAt);
        await m.addColumn(readingPlans, readingPlans.pausedDays);
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

  Future<Book?> findBook(String id) =>
      (select(books)..where((b) => b.id.equals(id))).getSingleOrNull();

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
      return newPlanId;
    });
  }

  /// Stops the plan reminding and stops the clock counting against it.
  ///
  /// Pausing twice is a no-op rather than an error: the caller is a button,
  /// and a double tap should not lose the original pause date.
  Future<void> pausePlan(String planId, DateTime now) async {
    await (update(readingPlans)
          ..where((p) => p.id.equals(planId) & p.pausedAt.isNull()))
        .write(
          ReadingPlansCompanion(
            pausedAt: Value(now),
            updatedAt: Value(now),
          ),
        );
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
    });
  }

  Stream<List<ReadingSession>> watchSessionsFor(String planId) {
    return (select(readingSessions)
          ..where((s) => s.planId.equals(planId))
          ..orderBy([(s) => OrderingTerm.asc(s.ordinal)]))
        .watch();
  }

  /// Rebuilds a plan's session list in one transaction.
  ///
  /// Sessions are replaced wholesale rather than diffed: the ordinals seed
  /// notification ids, so a stable full rewrite is easier to reason about than
  /// patching individual rows.
  Future<void> replaceSessions(
    String planId,
    List<ReadingSessionsCompanion> sessions,
  ) {
    return transaction(() async {
      await (delete(
        readingSessions,
      )..where((s) => s.planId.equals(planId))).go();
      await batch((b) => b.insertAll(readingSessions, sessions));
    });
  }

  /// Every session of every book still being read, in time order.
  ///
  /// Finished and archived books fall out on their own: [recordReading] flips
  /// the book's status, so completing a book drops off both the day's list and
  /// the reminder schedule without anything having to clean up after it.
  Stream<List<({Book book, ReadingPlan plan, ReadingSession session})>>
  watchLivePlanSessions({bool remindersOnly = false}) {
    final query =
        select(readingSessions).join([
          innerJoin(
            readingPlans,
            readingPlans.id.equalsExp(readingSessions.planId),
          ),
          innerJoin(books, books.id.equalsExp(readingPlans.bookId)),
        ])..orderBy([OrderingTerm.asc(readingSessions.ordinal)]);

    // A paused plan owes nothing today and reminds about nothing. It stays in
    // the library, where the reader can see it and resume it.
    var filter =
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
}

/// Single database instance for the app, closed when the app shuts down.
final appDatabaseProvider = Provider<AppDatabase>((ref) {
  final db = AppDatabase();
  ref.onDispose(db.close);
  return db;
});
