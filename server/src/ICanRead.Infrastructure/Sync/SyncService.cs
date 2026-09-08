using ICanRead.Application.Sync;
using ICanRead.Domain.Entities;
using ICanRead.Infrastructure.Persistence;
using Microsoft.EntityFrameworkCore;

namespace ICanRead.Infrastructure.Sync;

/// <summary>
/// Pulls changes down and merges pushes up.
/// </summary>
/// <remarks>
/// Three different conflict rules, because the three kinds of row mean
/// different things:
///
/// <list type="bullet">
/// <item>Books, plans and sessions are <b>last write wins</b> on the client's
/// own <c>UpdatedAt</c> — they describe an intention, and the most recent
/// intention is the one the reader holds.</item>
/// <item><c>LastPageRead</c> takes the <b>maximum</b>, never the latest. Reading
/// only moves forward, so a stale device pushing an older number must not walk
/// real progress backwards.</item>
/// <item>The reading log is <b>append-only</b> and merges by id. Last-write-wins
/// here would drop entries two devices wrote while offline, and a log whose
/// value is being complete cannot afford that.</item>
/// </list>
/// </remarks>
public class SyncService(AppDbContext db, TimeProvider clock)
{
    public async Task<SyncPullResponse> PullAsync(
        Guid userId,
        DateTimeOffset? since,
        CancellationToken ct)
    {
        // `>=`, not `>`. Two rows written in the same tick as the previous
        // cursor would otherwise be skipped for good; re-delivering the
        // boundary costs one redundant row and every merge on the device is
        // idempotent, so it cannot do harm.
        var from = since ?? DateTimeOffset.MinValue;

        var books = db.Books.Where(b => b.UserId == userId);
        var plans = db.ReadingPlans.Where(p => books.Any(b => b.Id == p.BookId));

        var response = new SyncPayload
        {
            Books = await books
                .Where(b => b.ServerUpdatedAt >= from)
                .Select(b => new BookDto(
                    b.Id, b.Title, b.Author, b.PageCount, b.PageLabelOffset,
                    b.Status.ToString(), b.CreatedAt, b.UpdatedAt, b.DeletedAt))
                .ToListAsync(ct),

            Fingerprints = await db.BookFingerprints
                .Where(f => books.Any(b => b.Id == f.BookId) && f.ServerUpdatedAt >= from)
                .Select(f => new FingerprintDto(
                    f.Id, f.BookId, f.Sha256, f.PageCount, f.SizeBytes,
                    f.OriginalFileName, f.CreatedAt))
                .ToListAsync(ct),

            Plans = await plans
                .Where(p => p.ServerUpdatedAt >= from)
                .Select(p => new PlanDto(
                    p.Id, p.BookId, p.Mode.ToString(), p.StartPage, p.EndPage,
                    p.StartDate, p.TargetEndDate, p.PagesPerDay, p.LastPageRead,
                    p.IsActive, p.PausedAt, p.PausedDays, p.CreatedAt, p.UpdatedAt))
                .ToListAsync(ct),

            Sessions = await db.ReadingSessions
                .Where(s => plans.Any(p => p.Id == s.PlanId) && s.ServerUpdatedAt >= from)
                .Select(s => new SessionDto(
                    s.Id, s.PlanId, s.Ordinal, s.TimeOfDayMinutes, s.PagesShare,
                    s.DaysOfWeek, s.IsEnabled, s.UpdatedAt, s.DeletedAt))
                .ToListAsync(ct),

            LogEntries = await db.ReadingLog
                .Where(l => plans.Any(p => p.Id == l.PlanId) && l.ServerUpdatedAt >= from)
                .Select(l => new LogEntryDto(
                    l.Id, l.PlanId, l.SessionId, l.ReadDate, l.FromPage, l.ToPage,
                    l.PagesRead, l.DurationSeconds, l.CreatedAt))
                .ToListAsync(ct)
        };

        return new SyncPullResponse(clock.GetUtcNow(), response);
    }

    public async Task<SyncPushResponse> PushAsync(
        Guid userId,
        SyncPayload payload,
        CancellationToken ct)
    {
        var now = clock.GetUtcNow();
        var tally = new MergeTally();

        // Books first, then plans, then their children: a device that created
        // a book and a plan in one offline session pushes both together, and
        // the plan's foreign key needs the book to already be there.
        var ownedBookIds = await MergeBooksAsync(userId, payload.Books, now, tally, ct);
        await MergeFingerprintsAsync(payload.Fingerprints, ownedBookIds, now, tally, ct);
        var ownedPlanIds = await MergePlansAsync(payload.Plans, ownedBookIds, now, tally, ct);
        await MergeSessionsAsync(payload.Sessions, ownedPlanIds, now, tally, ct);
        await MergeLogAsync(payload.LogEntries, ownedPlanIds, now, tally, ct);

        await db.SaveChangesAsync(ct);
        return new SyncPushResponse(now, tally.Applied, tally.Ignored, tally.Rejected);
    }

    /// <summary>
    /// Running totals for one push. A class rather than <c>ref int</c> counters
    /// because the merge steps are async, which rules those out.
    /// </summary>
    private sealed class MergeTally
    {
        public int Applied;
        public int Ignored;
        public List<Guid> Rejected { get; } = [];
    }

    /// <returns>Every book id this user owns that the push touched or already had.</returns>
    private async Task<HashSet<Guid>> MergeBooksAsync(
        Guid userId,
        IReadOnlyList<BookDto> incoming,
        DateTimeOffset now,
        MergeTally tally,
        CancellationToken ct)
    {
        var ids = incoming.Select(b => b.Id).ToList();
        var existing = await db.Books
            .Where(b => ids.Contains(b.Id))
            .ToDictionaryAsync(b => b.Id, ct);

        foreach (var dto in incoming)
        {
            if (!Enum.TryParse<BookStatus>(dto.Status, ignoreCase: true, out var status))
            {
                tally.Rejected.Add(dto.Id);
                continue;
            }

            if (existing.TryGetValue(dto.Id, out var book))
            {
                // Looked up by id alone, then checked: a client that guesses
                // another reader's book id must not be able to overwrite it,
                // and must not learn that the id exists either.
                if (book.UserId != userId)
                {
                    tally.Rejected.Add(dto.Id);
                    continue;
                }

                if (dto.UpdatedAt < book.UpdatedAt)
                {
                    tally.Ignored++;
                    continue;
                }

                book.Title = dto.Title;
                book.Author = dto.Author;
                book.PageCount = dto.PageCount;
                book.PageLabelOffset = dto.PageLabelOffset;
                book.Status = status;
                book.UpdatedAt = dto.UpdatedAt;
                book.DeletedAt = dto.DeletedAt;
                book.ServerUpdatedAt = now;
                tally.Applied++;
            }
            else
            {
                db.Books.Add(new Book
                {
                    Id = dto.Id,
                    // From the token, never from the body.
                    UserId = userId,
                    Title = dto.Title,
                    Author = dto.Author,
                    PageCount = dto.PageCount,
                    PageLabelOffset = dto.PageLabelOffset,
                    Status = status,
                    CreatedAt = dto.CreatedAt,
                    UpdatedAt = dto.UpdatedAt,
                    DeletedAt = dto.DeletedAt,
                    ServerUpdatedAt = now
                });
                tally.Applied++;
            }
        }

        // Everything the user owns, not just what this push touched: a device
        // may push a plan for a book the server already had.
        return (await db.Books.Where(b => b.UserId == userId).Select(b => b.Id).ToListAsync(ct))
            .Concat(db.ChangeTracker.Entries<Book>()
                .Where(e => e.State == EntityState.Added && e.Entity.UserId == userId)
                .Select(e => e.Entity.Id))
            .ToHashSet();
    }

    private async Task MergeFingerprintsAsync(
        IReadOnlyList<FingerprintDto> incoming,
        HashSet<Guid> ownedBookIds,
        DateTimeOffset now,
        MergeTally tally,
        CancellationToken ct)
    {
        var ids = incoming.Select(f => f.Id).ToList();
        var existing = await db.BookFingerprints
            .Where(f => ids.Contains(f.Id))
            .Select(f => f.Id)
            .ToListAsync(ct);
        var seen = existing.ToHashSet();

        foreach (var dto in incoming)
        {
            if (!ownedBookIds.Contains(dto.BookId))
            {
                tally.Rejected.Add(dto.Id);
                continue;
            }

            // A fingerprint is a fact about a file that was already read. It
            // never changes, so there is nothing to update and a repeat is
            // simply a push the device sent twice.
            if (!seen.Add(dto.Id))
            {
                tally.Ignored++;
                continue;
            }

            db.BookFingerprints.Add(new BookFingerprint
            {
                Id = dto.Id,
                BookId = dto.BookId,
                Sha256 = dto.Sha256.ToLowerInvariant(),
                PageCount = dto.PageCount,
                SizeBytes = dto.SizeBytes,
                OriginalFileName = dto.OriginalFileName,
                CreatedAt = dto.CreatedAt,
                ServerUpdatedAt = now
            });
            tally.Applied++;
        }
    }

    private async Task<HashSet<Guid>> MergePlansAsync(
        IReadOnlyList<PlanDto> incoming,
        HashSet<Guid> ownedBookIds,
        DateTimeOffset now,
        MergeTally tally,
        CancellationToken ct)
    {
        var ids = incoming.Select(p => p.Id).ToList();
        var existing = await db.ReadingPlans
            .Where(p => ids.Contains(p.Id))
            .ToDictionaryAsync(p => p.Id, ct);

        foreach (var dto in incoming)
        {
            if (!ownedBookIds.Contains(dto.BookId) ||
                !Enum.TryParse<PlanMode>(dto.Mode, ignoreCase: true, out var mode))
            {
                tally.Rejected.Add(dto.Id);
                continue;
            }

            if (existing.TryGetValue(dto.Id, out var plan))
            {
                if (!ownedBookIds.Contains(plan.BookId))
                {
                    tally.Rejected.Add(dto.Id);
                    continue;
                }

                // Progress is merged even when the rest of the row loses the
                // last-write-wins comparison. A device can be behind on the
                // plan's settings and still be the one that read furthest.
                var furthest = Math.Max(plan.LastPageRead, dto.LastPageRead);

                if (dto.UpdatedAt < plan.UpdatedAt)
                {
                    if (furthest != plan.LastPageRead)
                    {
                        plan.LastPageRead = furthest;
                        plan.ServerUpdatedAt = now;
                        tally.Applied++;
                    }
                    else
                    {
                        tally.Ignored++;
                    }
                    continue;
                }

                plan.Mode = mode;
                plan.StartPage = dto.StartPage;
                plan.EndPage = dto.EndPage;
                plan.StartDate = dto.StartDate;
                plan.TargetEndDate = dto.TargetEndDate;
                plan.PagesPerDay = dto.PagesPerDay;
                plan.LastPageRead = furthest;
                plan.IsActive = dto.IsActive;
                plan.PausedAt = dto.PausedAt;
                plan.PausedDays = dto.PausedDays;
                plan.UpdatedAt = dto.UpdatedAt;
                plan.ServerUpdatedAt = now;
                tally.Applied++;
            }
            else
            {
                db.ReadingPlans.Add(new ReadingPlan
                {
                    Id = dto.Id,
                    BookId = dto.BookId,
                    Mode = mode,
                    StartPage = dto.StartPage,
                    EndPage = dto.EndPage,
                    StartDate = dto.StartDate,
                    TargetEndDate = dto.TargetEndDate,
                    PagesPerDay = dto.PagesPerDay,
                    LastPageRead = dto.LastPageRead,
                    IsActive = dto.IsActive,
                    PausedAt = dto.PausedAt,
                    PausedDays = dto.PausedDays,
                    CreatedAt = dto.CreatedAt,
                    UpdatedAt = dto.UpdatedAt,
                    ServerUpdatedAt = now
                });
                tally.Applied++;
            }
        }

        return (await db.ReadingPlans
                .Where(p => ownedBookIds.Contains(p.BookId))
                .Select(p => p.Id)
                .ToListAsync(ct))
            .Concat(db.ChangeTracker.Entries<ReadingPlan>()
                .Where(e => e.State == EntityState.Added)
                .Select(e => e.Entity.Id))
            .ToHashSet();
    }

    private async Task MergeSessionsAsync(
        IReadOnlyList<SessionDto> incoming,
        HashSet<Guid> ownedPlanIds,
        DateTimeOffset now,
        MergeTally tally,
        CancellationToken ct)
    {
        var ids = incoming.Select(s => s.Id).ToList();
        var existing = await db.ReadingSessions
            .Where(s => ids.Contains(s.Id))
            .ToDictionaryAsync(s => s.Id, ct);

        foreach (var dto in incoming)
        {
            if (!ownedPlanIds.Contains(dto.PlanId))
            {
                tally.Rejected.Add(dto.Id);
                continue;
            }

            if (existing.TryGetValue(dto.Id, out var session))
            {
                if (dto.UpdatedAt < session.UpdatedAt)
                {
                    tally.Ignored++;
                    continue;
                }

                session.Ordinal = dto.Ordinal;
                session.TimeOfDayMinutes = dto.TimeOfDayMinutes;
                session.PagesShare = dto.PagesShare;
                session.DaysOfWeek = dto.DaysOfWeek;
                session.IsEnabled = dto.IsEnabled;
                session.DeletedAt = dto.DeletedAt;
                session.UpdatedAt = dto.UpdatedAt;
                session.ServerUpdatedAt = now;
                tally.Applied++;
            }
            else
            {
                db.ReadingSessions.Add(new ReadingSession
                {
                    Id = dto.Id,
                    PlanId = dto.PlanId,
                    Ordinal = dto.Ordinal,
                    TimeOfDayMinutes = dto.TimeOfDayMinutes,
                    PagesShare = dto.PagesShare,
                    DaysOfWeek = dto.DaysOfWeek,
                    IsEnabled = dto.IsEnabled,
                    DeletedAt = dto.DeletedAt,
                    UpdatedAt = dto.UpdatedAt,
                    ServerUpdatedAt = now
                });
                tally.Applied++;
            }
        }
    }

    private async Task MergeLogAsync(
        IReadOnlyList<LogEntryDto> incoming,
        HashSet<Guid> ownedPlanIds,
        DateTimeOffset now,
        MergeTally tally,
        CancellationToken ct)
    {
        var ids = incoming.Select(l => l.Id).ToList();
        var existing = await db.ReadingLog
            .Where(l => ids.Contains(l.Id))
            .Select(l => l.Id)
            .ToListAsync(ct);
        var seen = existing.ToHashSet();

        foreach (var dto in incoming)
        {
            if (!ownedPlanIds.Contains(dto.PlanId))
            {
                tally.Rejected.Add(dto.Id);
                continue;
            }

            // Append-only: an id already here is a push the device repeated,
            // and the existing row is left exactly as it is. Never updated,
            // because there is no version of "the reader read these pages"
            // that a later push knows better.
            if (!seen.Add(dto.Id))
            {
                tally.Ignored++;
                continue;
            }

            db.ReadingLog.Add(new ReadingLogEntry
            {
                Id = dto.Id,
                PlanId = dto.PlanId,
                SessionId = dto.SessionId,
                ReadDate = dto.ReadDate,
                FromPage = dto.FromPage,
                ToPage = dto.ToPage,
                PagesRead = dto.PagesRead,
                DurationSeconds = dto.DurationSeconds,
                CreatedAt = dto.CreatedAt,
                ServerUpdatedAt = now
            });
            tally.Applied++;
        }
    }

    /// <summary>
    /// Finds this user's book matching a file's hash, for the new-device relink.
    /// </summary>
    public async Task<BookDto?> LookupByHashAsync(
        Guid userId,
        string sha256,
        CancellationToken ct)
    {
        var hash = sha256.Trim().ToLowerInvariant();

        return await db.BookFingerprints
            .Where(f => f.Sha256 == hash)
            .Join(db.Books.Where(b => b.UserId == userId && b.DeletedAt == null),
                f => f.BookId, b => b.Id, (f, b) => b)
            .Select(b => new BookDto(
                b.Id, b.Title, b.Author, b.PageCount, b.PageLabelOffset,
                b.Status.ToString(), b.CreatedAt, b.UpdatedAt, b.DeletedAt))
            .FirstOrDefaultAsync(ct);
    }
}
