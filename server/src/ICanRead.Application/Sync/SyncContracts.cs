namespace ICanRead.Application.Sync;

/// <summary>
/// One book, as it travels. There is no <c>UserId</c> on purpose: ownership is
/// taken from the token, never from the body.
/// </summary>
public record BookDto(
    Guid Id,
    string Title,
    string? Author,
    int PageCount,
    int PageLabelOffset,
    string Status,
    DateTimeOffset CreatedAt,
    DateTimeOffset UpdatedAt,
    DateTimeOffset? DeletedAt);

public record FingerprintDto(
    Guid Id,
    Guid BookId,
    string Sha256,
    int PageCount,
    long SizeBytes,
    string? OriginalFileName,
    DateTimeOffset CreatedAt);

public record PlanDto(
    Guid Id,
    Guid BookId,
    string Mode,
    int StartPage,
    int EndPage,
    DateOnly StartDate,
    DateOnly TargetEndDate,
    int PagesPerDay,
    int LastPageRead,
    bool IsActive,
    DateTimeOffset? PausedAt,
    int PausedDays,
    DateTimeOffset CreatedAt,
    DateTimeOffset UpdatedAt);

/// <param name="DeletedAt">
/// Set when the session was removed. Sessions are soft-deleted for the same
/// reason books are: the client rebuilds the whole list whenever the reader
/// edits a reminder time, and a row that just disappeared from a device cannot
/// be described in a push — the copy here would survive and come back down as
/// a duplicate reminder.
/// </param>
public record SessionDto(
    Guid Id,
    Guid PlanId,
    int Ordinal,
    int TimeOfDayMinutes,
    int PagesShare,
    int DaysOfWeek,
    bool IsEnabled,
    DateTimeOffset UpdatedAt,
    DateTimeOffset? DeletedAt);

public record LogEntryDto(
    Guid Id,
    Guid PlanId,
    Guid? SessionId,
    DateOnly ReadDate,
    int FromPage,
    int ToPage,
    int PagesRead,
    int DurationSeconds,
    DateTimeOffset CreatedAt);

/// <summary>
/// The whole payload, in both directions. Push and pull are the same shape so
/// a device can round-trip what it received without translating it.
/// </summary>
public record SyncPayload
{
    public IReadOnlyList<BookDto> Books { get; init; } = [];
    public IReadOnlyList<FingerprintDto> Fingerprints { get; init; } = [];
    public IReadOnlyList<PlanDto> Plans { get; init; } = [];
    public IReadOnlyList<SessionDto> Sessions { get; init; } = [];
    public IReadOnlyList<LogEntryDto> LogEntries { get; init; } = [];
}

/// <summary>
/// A pull result, and the cursor to hand back on the next one.
/// </summary>
/// <param name="ServerTime">
/// Pass this as <c>since</c> next time. It is this server's clock, not the
/// device's, so it means the same thing on every phone the reader owns.
/// </param>
public record SyncPullResponse(DateTimeOffset ServerTime, SyncPayload Changes);

/// <summary>
/// What a push actually did.
/// </summary>
/// <param name="Rejected">
/// Rows that name a book or plan the caller does not own. Reported rather than
/// silently dropped so a client bug does not look like a working sync.
/// </param>
public record SyncPushResponse(
    DateTimeOffset ServerTime,
    int Applied,
    int Ignored,
    IReadOnlyList<Guid> Rejected);

public record LookupByHashRequest(string Sha256);

public record LookupByHashResponse(BookDto? Book);
