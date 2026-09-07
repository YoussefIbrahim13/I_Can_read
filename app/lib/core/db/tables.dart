import 'package:drift/drift.dart';

import '../planning/plan_math.dart' show PlanMode;

/// Where a book sits in the reader's library.
enum BookStatus { reading, finished, archived }

/// What a queued sync operation does to the server.
enum SyncOp { upsert, delete }

// ---------------------------------------------------------------------------
// Synced tables — these mirror the server schema and travel with the account.
// Every id is a client-generated UUID so records can be created offline.
// ---------------------------------------------------------------------------

class Books extends Table {
  TextColumn get id => text()();
  TextColumn get title => text().withLength(min: 1, max: 500)();
  TextColumn get author => text().nullable()();

  /// Physical page count of the PDF, not the printed numbering.
  IntColumn get pageCount => integer()();

  /// Added to a physical index to get the number printed on the page.
  /// Display only — all stored page numbers stay physical.
  IntColumn get pageLabelOffset => integer().withDefault(const Constant(0))();

  TextColumn get status =>
      textEnum<BookStatus>().withDefault(const Constant('reading'))();

  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  /// Soft delete, so the tombstone can be synced to other devices.
  DateTimeColumn get deletedAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

/// SHA-256 fingerprints of PDF files that have been accepted as this book.
///
/// A book can have several: a reader may re-add a different scan or edition on
/// another device, and we want that file to relink to the same plan rather than
/// start a new book.
class BookFingerprints extends Table {
  TextColumn get id => text()();
  TextColumn get bookId =>
      text().references(Books, #id, onDelete: KeyAction.cascade)();

  /// Lowercase hex SHA-256 of the whole file.
  TextColumn get sha256 => text().withLength(min: 64, max: 64)();

  /// Page count of *this* file, which may differ from [Books.pageCount] when
  /// the reader links a different edition.
  IntColumn get pageCount => integer()();
  IntColumn get sizeBytes => integer()();
  TextColumn get originalFileName => text().nullable()();
  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}

class ReadingPlans extends Table {
  TextColumn get id => text()();
  TextColumn get bookId =>
      text().references(Books, #id, onDelete: KeyAction.cascade)();

  TextColumn get mode => textEnum<PlanMode>()();

  /// Inclusive physical page range the plan covers.
  IntColumn get startPage => integer()();
  IntColumn get endPage => integer()();

  DateTimeColumn get startDate => dateTime()();

  /// What the reader originally aimed for. The live projection is derived from
  /// actual progress and is never written back here.
  DateTimeColumn get targetEndDate => dateTime()();

  /// Fixed daily quota. Missed days extend the finish date instead of raising
  /// this, which is the behaviour the reader chose.
  IntColumn get pagesPerDay => integer()();

  /// Highest page completed. Synced by taking the MAX across devices rather
  /// than last-write-wins, because reading only ever moves forward.
  IntColumn get lastPageRead => integer().withDefault(const Constant(0))();

  BoolColumn get isActive => boolean().withDefault(const Constant(true))();

  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}

/// One recurring daily reading slot, e.g. "20:00, 5 pages".
class ReadingSessions extends Table {
  TextColumn get id => text()();
  TextColumn get planId =>
      text().references(ReadingPlans, #id, onDelete: KeyAction.cascade)();

  /// Position within the day, 0-based. Also seeds the notification id.
  IntColumn get ordinal => integer()();

  /// Minutes after local midnight. Stored as a plain integer so it is immune to
  /// timezone and DST shifts; the zone is applied when scheduling.
  IntColumn get timeOfDayMinutes => integer()();

  /// This session's slice of the daily quota, from `splitAcrossSessions`.
  IntColumn get pagesShare => integer()();

  /// Bitmask, bit 0 = Monday .. bit 6 = Sunday. 127 means every day.
  IntColumn get daysOfWeek => integer().withDefault(const Constant(127))();

  BoolColumn get isEnabled => boolean().withDefault(const Constant(true))();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}

/// Append-only record of reading actually done. Never updated or deleted, so
/// it merges across devices by id without losing entries.
class ReadingLog extends Table {
  TextColumn get id => text()();
  TextColumn get planId =>
      text().references(ReadingPlans, #id, onDelete: KeyAction.cascade)();

  /// Null when the reader read outside any scheduled session.
  TextColumn get sessionId => text().nullable()();

  /// Local calendar day the reading is credited to.
  DateTimeColumn get readDate => dateTime()();

  IntColumn get fromPage => integer()();
  IntColumn get toPage => integer()();
  IntColumn get pagesRead => integer()();
  IntColumn get durationSeconds => integer().withDefault(const Constant(0))();
  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}

// ---------------------------------------------------------------------------
// Device-only tables — never synced. The PDF stays on this phone.
// ---------------------------------------------------------------------------

/// Where this device keeps a book's PDF.
class LocalBookFiles extends Table {
  TextColumn get bookId =>
      text().references(Books, #id, onDelete: KeyAction.cascade)();

  /// Relative to the app documents directory, e.g. `books/<uuid>.pdf`.
  ///
  /// Deliberately not absolute: the iOS app-container path contains a UUID that
  /// changes on reinstall and update, which would break every stored path.
  TextColumn get relativePath => text()();

  /// False once the file goes missing, which drives the "locate this PDF" flow.
  BoolColumn get isAvailable => boolean().withDefault(const Constant(true))();

  DateTimeColumn get linkedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {bookId};
}

/// Last viewport per book, so reopening lands where the reader left off.
class ReaderStates extends Table {
  TextColumn get bookId =>
      text().references(Books, #id, onDelete: KeyAction.cascade)();
  IntColumn get lastPage => integer().withDefault(const Constant(1))();
  RealColumn get zoom => real().withDefault(const Constant(1))();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {bookId};
}

/// Pending writes waiting to reach the server. Phase 2 drains this; Phase 1
/// simply accumulates nothing because there is no account yet.
class SyncOutbox extends Table {
  IntColumn get id => integer().autoIncrement()();

  /// Table name the change belongs to, e.g. `books`.
  TextColumn get entity => text()();
  TextColumn get entityId => text()();
  TextColumn get op => textEnum<SyncOp>()();

  /// Full row snapshot as JSON; the server upserts it wholesale.
  TextColumn get payloadJson => text()();

  DateTimeColumn get createdAt => dateTime()();
  IntColumn get attempts => integer().withDefault(const Constant(0))();
}
