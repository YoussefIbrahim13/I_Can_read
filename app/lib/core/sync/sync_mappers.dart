/// Turns stored rows into the shapes the server speaks.
///
/// Kept apart from the database so the wire format has one home: every rule
/// about how a timestamp or a date is written down lives either here or in
/// [wireInstant] and [wireDate], and never gets improvised at a call site.
library;

import '../db/app_database.dart';
import 'sync_models.dart';

/// A book row, ready to travel.
BookDto bookDto(Book row) => BookDto(
  id: row.id,
  title: row.title,
  author: row.author,
  pageCount: row.pageCount,
  pageLabelOffset: row.pageLabelOffset,
  status: row.status.name,
  createdAt: row.createdAt,
  updatedAt: row.updatedAt,
  deletedAt: row.deletedAt,
);

FingerprintDto fingerprintDto(BookFingerprint row) => FingerprintDto(
  id: row.id,
  bookId: row.bookId,
  sha256: row.sha256,
  pageCount: row.pageCount,
  sizeBytes: row.sizeBytes,
  originalFileName: row.originalFileName,
  createdAt: row.createdAt,
);

PlanDto planDto(ReadingPlan row) => PlanDto(
  id: row.id,
  bookId: row.bookId,
  mode: row.mode.name,
  startPage: row.startPage,
  endPage: row.endPage,
  // Dates, not instants: see [wireDate].
  startDate: wireDate(row.startDate),
  targetEndDate: wireDate(row.targetEndDate),
  pagesPerDay: row.pagesPerDay,
  lastPageRead: row.lastPageRead,
  isActive: row.isActive,
  pausedAt: row.pausedAt,
  pausedDays: row.pausedDays,
  createdAt: row.createdAt,
  updatedAt: row.updatedAt,
);

SessionDto sessionDto(ReadingSession row) => SessionDto(
  id: row.id,
  planId: row.planId,
  ordinal: row.ordinal,
  timeOfDayMinutes: row.timeOfDayMinutes,
  pagesShare: row.pagesShare,
  daysOfWeek: row.daysOfWeek,
  isEnabled: row.isEnabled,
  updatedAt: row.updatedAt,
  deletedAt: row.deletedAt,
);

LogEntryDto logEntryDto(ReadingLogData row) => LogEntryDto(
  id: row.id,
  planId: row.planId,
  sessionId: row.sessionId,
  readDate: wireDate(row.readDate),
  fromPage: row.fromPage,
  toPage: row.toPage,
  pagesRead: row.pagesRead,
  durationSeconds: row.durationSeconds,
  createdAt: row.createdAt,
);

/// The outbox `entity` names, which double as the payload bucket a queued row
/// lands in when it is pushed.
abstract final class SyncEntity {
  static const books = 'books';
  static const fingerprints = 'book_fingerprints';
  static const plans = 'reading_plans';
  static const sessions = 'reading_sessions';
  static const logEntries = 'reading_log';
}
