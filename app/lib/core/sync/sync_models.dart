/// Data transfer objects mirroring the server's sync contracts.
///
/// All classes are immutable with [const] constructors, [fromJson] factories,
/// and [toJson] methods following ASP.NET Core camelCase serialization.
library;

/// Instants cross the wire as UTC with an explicit `Z`.
///
/// [DateTime.toIso8601String] on a local time emits no offset at all, and a
/// `DateTimeOffset` parsed from an offset-less string is read as the *server's*
/// local time. A phone three hours ahead would then have every timestamp
/// silently shifted by three hours, and last-write-wins would start picking
/// the wrong winner.
String wireInstant(DateTime instant) => instant.toUtc().toIso8601String();

/// [wireInstant] for a field that may be absent.
String? wireInstantOrNull(DateTime? instant) =>
    instant == null ? null : wireInstant(instant);

/// Calendar days cross the wire as a bare `YYYY-MM-DD` built from *local*
/// components.
///
/// Deliberately not routed through [wireInstant]: local midnight on the 8th is
/// still the 7th in UTC anywhere east of Greenwich, so a reading date sent as
/// an instant would arrive a day early — and a day is exactly the unit this
/// whole app counts in.
String wireDate(DateTime day) =>
    '${day.year.toString().padLeft(4, '0')}-'
    '${day.month.toString().padLeft(2, '0')}-'
    '${day.day.toString().padLeft(2, '0')}';

/// Data transfer object for a book.
class BookDto {
  /// Unique identifier (UUID string).
  final String id;

  /// Book title.
  final String title;

  /// Optional author name.
  final String? author;

  /// Physical page count of the book.
  final int pageCount;

  /// Offset added to physical page index to get printed page number.
  final int pageLabelOffset;

  /// Reading status (e.g. 'reading', 'finished').
  final String status;

  /// Timestamp when the book was created.
  final DateTime createdAt;

  /// Timestamp when the book was last updated.
  final DateTime updatedAt;

  /// Timestamp when the book was soft deleted, or null if active.
  final DateTime? deletedAt;

  const BookDto({
    required this.id,
    required this.title,
    this.author,
    required this.pageCount,
    required this.pageLabelOffset,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
    this.deletedAt,
  });

  factory BookDto.fromJson(Map<String, dynamic> json) {
    return BookDto(
      id: json['id'] as String,
      title: json['title'] as String,
      author: json['author'] as String?,
      pageCount: json['pageCount'] as int,
      pageLabelOffset: json['pageLabelOffset'] as int,
      status: json['status'] as String,
      createdAt: DateTime.parse(json['createdAt'] as String),
      updatedAt: DateTime.parse(json['updatedAt'] as String),
      deletedAt: json['deletedAt'] != null
          ? DateTime.parse(json['deletedAt'] as String)
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'id': id,
      'title': title,
      'author': author,
      'pageCount': pageCount,
      'pageLabelOffset': pageLabelOffset,
      'status': status,
      'createdAt': wireInstant(createdAt),
      'updatedAt': wireInstant(updatedAt),
      'deletedAt': wireInstantOrNull(deletedAt),
    };
  }
}

/// Data transfer object for a file fingerprint linked to a book.
class FingerprintDto {
  /// Unique identifier (UUID string).
  final String id;

  /// Associated book identifier (UUID string).
  final String bookId;

  /// SHA-256 hash (64-character lowercase hex string).
  final String sha256;

  /// Physical page count of this specific PDF file.
  final int pageCount;

  /// File size in bytes.
  final int sizeBytes;

  /// Original filename, if preserved.
  final String? originalFileName;

  /// Timestamp when this fingerprint record was created.
  final DateTime createdAt;

  const FingerprintDto({
    required this.id,
    required this.bookId,
    required this.sha256,
    required this.pageCount,
    required this.sizeBytes,
    this.originalFileName,
    required this.createdAt,
  });

  factory FingerprintDto.fromJson(Map<String, dynamic> json) {
    return FingerprintDto(
      id: json['id'] as String,
      bookId: json['bookId'] as String,
      sha256: json['sha256'] as String,
      pageCount: json['pageCount'] as int,
      sizeBytes: json['sizeBytes'] as int,
      originalFileName: json['originalFileName'] as String?,
      createdAt: DateTime.parse(json['createdAt'] as String),
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'id': id,
      'bookId': bookId,
      'sha256': sha256,
      'pageCount': pageCount,
      'sizeBytes': sizeBytes,
      'originalFileName': originalFileName,
      'createdAt': wireInstant(createdAt),
    };
  }
}

/// Data transfer object for a reading plan.
class PlanDto {
  /// Unique identifier (UUID string).
  final String id;

  /// Associated book identifier (UUID string).
  final String bookId;

  /// Plan calculation mode (e.g. 'byPace', 'byTargetDate').
  final String mode;

  /// First page of the reading range.
  final int startPage;

  /// Last page of the reading range.
  final int endPage;

  /// Plan start date as an ISO date string (YYYY-MM-DD).
  final String startDate;

  /// Target completion date as an ISO date string (YYYY-MM-DD).
  final String targetEndDate;

  /// Planned reading pace in pages per day.
  final int pagesPerDay;

  /// Last physical page read.
  final int lastPageRead;

  /// Whether the plan is currently active.
  final bool isActive;

  /// Timestamp when the plan was paused, or null if active.
  final DateTime? pausedAt;

  /// Number of days the plan has spent paused.
  final int pausedDays;

  /// Timestamp when the plan was created.
  final DateTime createdAt;

  /// Timestamp when the plan was last updated.
  final DateTime updatedAt;

  const PlanDto({
    required this.id,
    required this.bookId,
    required this.mode,
    required this.startPage,
    required this.endPage,
    required this.startDate,
    required this.targetEndDate,
    required this.pagesPerDay,
    required this.lastPageRead,
    required this.isActive,
    this.pausedAt,
    required this.pausedDays,
    required this.createdAt,
    required this.updatedAt,
  });

  factory PlanDto.fromJson(Map<String, dynamic> json) {
    return PlanDto(
      id: json['id'] as String,
      bookId: json['bookId'] as String,
      mode: json['mode'] as String,
      startPage: json['startPage'] as int,
      endPage: json['endPage'] as int,
      startDate: json['startDate'] as String,
      targetEndDate: json['targetEndDate'] as String,
      pagesPerDay: json['pagesPerDay'] as int,
      lastPageRead: json['lastPageRead'] as int,
      isActive: json['isActive'] as bool,
      pausedAt: json['pausedAt'] != null
          ? DateTime.parse(json['pausedAt'] as String)
          : null,
      pausedDays: json['pausedDays'] as int,
      createdAt: DateTime.parse(json['createdAt'] as String),
      updatedAt: DateTime.parse(json['updatedAt'] as String),
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'id': id,
      'bookId': bookId,
      'mode': mode,
      'startPage': startPage,
      'endPage': endPage,
      'startDate': startDate,
      'targetEndDate': targetEndDate,
      'pagesPerDay': pagesPerDay,
      'lastPageRead': lastPageRead,
      'isActive': isActive,
      'pausedAt': wireInstantOrNull(pausedAt),
      'pausedDays': pausedDays,
      'createdAt': wireInstant(createdAt),
      'updatedAt': wireInstant(updatedAt),
    };
  }
}

/// Data transfer object for a recurring reading session slot.
class SessionDto {
  /// Unique identifier (UUID string).
  final String id;

  /// Associated plan identifier (UUID string).
  final String planId;

  /// Order within the day (0-indexed).
  final int ordinal;

  /// Minutes past midnight for scheduled reminder (0-1439).
  final int timeOfDayMinutes;

  /// Target reading share (weight or percentage).
  final int pagesShare;

  /// Bitmask of days of week (bit 0 = Monday, ..., bit 6 = Sunday).
  final int daysOfWeek;

  /// Whether reminders for this session are enabled.
  final bool isEnabled;

  /// Timestamp when the session was last updated.
  final DateTime updatedAt;

  /// Timestamp when the session was removed, or null while it is live.
  ///
  /// Sessions are soft-deleted for the same reason books are: editing the
  /// reminder times rebuilds the whole list, and without a tombstone the old
  /// rows would sit on the server and be pulled back down as duplicate
  /// reminders on every device.
  final DateTime? deletedAt;

  const SessionDto({
    required this.id,
    required this.planId,
    required this.ordinal,
    required this.timeOfDayMinutes,
    required this.pagesShare,
    required this.daysOfWeek,
    required this.isEnabled,
    required this.updatedAt,
    this.deletedAt,
  });

  factory SessionDto.fromJson(Map<String, dynamic> json) {
    return SessionDto(
      id: json['id'] as String,
      planId: json['planId'] as String,
      ordinal: json['ordinal'] as int,
      timeOfDayMinutes: json['timeOfDayMinutes'] as int,
      pagesShare: json['pagesShare'] as int,
      daysOfWeek: json['daysOfWeek'] as int,
      isEnabled: json['isEnabled'] as bool,
      updatedAt: DateTime.parse(json['updatedAt'] as String),
      deletedAt: json['deletedAt'] != null
          ? DateTime.parse(json['deletedAt'] as String)
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'id': id,
      'planId': planId,
      'ordinal': ordinal,
      'timeOfDayMinutes': timeOfDayMinutes,
      'pagesShare': pagesShare,
      'daysOfWeek': daysOfWeek,
      'isEnabled': isEnabled,
      'updatedAt': wireInstant(updatedAt),
      'deletedAt': wireInstantOrNull(deletedAt),
    };
  }
}

/// Data transfer object for a reading log entry.
class LogEntryDto {
  /// Unique identifier (UUID string).
  final String id;

  /// Associated plan identifier (UUID string).
  final String planId;

  /// Associated session identifier (UUID string), or null if logged ad-hoc.
  final String? sessionId;

  /// Date the reading occurred as an ISO date string (YYYY-MM-DD).
  final String readDate;

  /// Physical start page of the reading increment.
  final int fromPage;

  /// Physical end page of the reading increment.
  final int toPage;

  /// Number of pages read in this increment.
  final int pagesRead;

  /// Duration spent reading in seconds.
  final int durationSeconds;

  /// Timestamp when the log entry was recorded.
  final DateTime createdAt;

  const LogEntryDto({
    required this.id,
    required this.planId,
    this.sessionId,
    required this.readDate,
    required this.fromPage,
    required this.toPage,
    required this.pagesRead,
    required this.durationSeconds,
    required this.createdAt,
  });

  factory LogEntryDto.fromJson(Map<String, dynamic> json) {
    return LogEntryDto(
      id: json['id'] as String,
      planId: json['planId'] as String,
      sessionId: json['sessionId'] as String?,
      readDate: json['readDate'] as String,
      fromPage: json['fromPage'] as int,
      toPage: json['toPage'] as int,
      pagesRead: json['pagesRead'] as int,
      durationSeconds: json['durationSeconds'] as int,
      createdAt: DateTime.parse(json['createdAt'] as String),
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'id': id,
      'planId': planId,
      'sessionId': sessionId,
      'readDate': readDate,
      'fromPage': fromPage,
      'toPage': toPage,
      'pagesRead': pagesRead,
      'durationSeconds': durationSeconds,
      'createdAt': wireInstant(createdAt),
    };
  }
}

/// Full synchronization payload containing entities in both push and pull directions.
class SyncPayload {
  /// Books included in the synchronization payload.
  final List<BookDto> books;

  /// File fingerprints included in the synchronization payload.
  final List<FingerprintDto> fingerprints;

  /// Reading plans included in the synchronization payload.
  final List<PlanDto> plans;

  /// Reading sessions included in the synchronization payload.
  final List<SessionDto> sessions;

  /// Log entries included in the synchronization payload.
  final List<LogEntryDto> logEntries;

  const SyncPayload({
    this.books = const [],
    this.fingerprints = const [],
    this.plans = const [],
    this.sessions = const [],
    this.logEntries = const [],
  });

  factory SyncPayload.fromJson(Map<String, dynamic> json) {
    return SyncPayload(
      books:
          (json['books'] as List<dynamic>?)
              ?.map((dynamic e) => BookDto.fromJson(e as Map<String, dynamic>))
              .toList() ??
          const [],
      fingerprints:
          (json['fingerprints'] as List<dynamic>?)
              ?.map(
                (dynamic e) =>
                    FingerprintDto.fromJson(e as Map<String, dynamic>),
              )
              .toList() ??
          const [],
      plans:
          (json['plans'] as List<dynamic>?)
              ?.map((dynamic e) => PlanDto.fromJson(e as Map<String, dynamic>))
              .toList() ??
          const [],
      sessions:
          (json['sessions'] as List<dynamic>?)
              ?.map(
                (dynamic e) => SessionDto.fromJson(e as Map<String, dynamic>),
              )
              .toList() ??
          const [],
      logEntries:
          (json['logEntries'] as List<dynamic>?)
              ?.map(
                (dynamic e) => LogEntryDto.fromJson(e as Map<String, dynamic>),
              )
              .toList() ??
          const [],
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'books': books.map((BookDto e) => e.toJson()).toList(),
      'fingerprints': fingerprints
          .map((FingerprintDto e) => e.toJson())
          .toList(),
      'plans': plans.map((PlanDto e) => e.toJson()).toList(),
      'sessions': sessions.map((SessionDto e) => e.toJson()).toList(),
      'logEntries': logEntries.map((LogEntryDto e) => e.toJson()).toList(),
    };
  }
}

/// Server response returned from a sync pull operation.
class SyncPullResponse {
  /// Server timestamp to be used as cursor for subsequent pulls.
  final DateTime serverTime;

  /// Payload of modified entities since requested timestamp.
  final SyncPayload changes;

  const SyncPullResponse({required this.serverTime, required this.changes});

  factory SyncPullResponse.fromJson(Map<String, dynamic> json) {
    return SyncPullResponse(
      serverTime: DateTime.parse(json['serverTime'] as String),
      changes: SyncPayload.fromJson(json['changes'] as Map<String, dynamic>),
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'serverTime': wireInstant(serverTime),
      'changes': changes.toJson(),
    };
  }
}

/// Server response returned after pushing local changes.
class SyncPushResponse {
  /// Server timestamp when the push was evaluated.
  final DateTime serverTime;

  /// Number of records applied on the server.
  final int applied;

  /// Number of records ignored (e.g. server copy was newer).
  final int ignored;

  /// Identifiers of records rejected by authorization or foreign-key mismatch.
  final List<String> rejected;

  const SyncPushResponse({
    required this.serverTime,
    required this.applied,
    required this.ignored,
    this.rejected = const [],
  });

  factory SyncPushResponse.fromJson(Map<String, dynamic> json) {
    return SyncPushResponse(
      serverTime: DateTime.parse(json['serverTime'] as String),
      applied: json['applied'] as int,
      ignored: json['ignored'] as int,
      rejected:
          (json['rejected'] as List<dynamic>?)
              ?.map((dynamic e) => e as String)
              .toList() ??
          const [],
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'serverTime': wireInstant(serverTime),
      'applied': applied,
      'ignored': ignored,
      'rejected': rejected,
    };
  }
}

/// Request to look up an existing book matching a file's SHA-256 hash.
class LookupByHashRequest {
  /// SHA-256 hash of the file.
  final String sha256;

  const LookupByHashRequest({required this.sha256});

  factory LookupByHashRequest.fromJson(Map<String, dynamic> json) {
    return LookupByHashRequest(sha256: json['sha256'] as String);
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{'sha256': sha256};
  }
}

/// Response returned when looking up a book by file hash.
class LookupByHashResponse {
  /// The matched book DTO, or null if no matching fingerprint exists.
  final BookDto? book;

  const LookupByHashResponse({this.book});

  factory LookupByHashResponse.fromJson(Map<String, dynamic> json) {
    return LookupByHashResponse(
      book: json['book'] != null
          ? BookDto.fromJson(json['book'] as Map<String, dynamic>)
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{'book': book?.toJson()};
  }
}
