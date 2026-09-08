namespace ICanRead.Domain.Entities;

/// <summary>How the reader stated their goal.</summary>
public enum PlanMode
{
    /// <summary>"Finish it by this date."</summary>
    ByDeadline,

    /// <summary>"Read this many pages a day."</summary>
    ByPagesPerDay
}

/// <summary>
/// A goal for a book: a page range, a start, and a fixed daily portion.
/// </summary>
public class ReadingPlan : ISyncedEntity
{
    public Guid Id { get; set; }

    public Guid BookId { get; set; }
    public Book? Book { get; set; }

    public PlanMode Mode { get; set; }

    /// <summary>Inclusive physical page range the plan covers.</summary>
    public int StartPage { get; set; }
    public int EndPage { get; set; }

    /// <summary>Date only; the client has no use for a time here.</summary>
    public DateOnly StartDate { get; set; }

    /// <summary>
    /// What the reader originally aimed for. The live projection is derived
    /// from real progress and is never written back here.
    /// </summary>
    public DateOnly TargetEndDate { get; set; }

    /// <summary>
    /// Fixed daily quota. Missing days extends the finish date rather than
    /// raising this — the rule the whole app is built on.
    /// </summary>
    public int PagesPerDay { get; set; }

    /// <summary>
    /// Highest page completed. Merged across devices by taking the MAX, not by
    /// last-write-wins: reading only ever moves forward, and a stale device
    /// pushing its older number would walk real progress backwards.
    /// </summary>
    public int LastPageRead { get; set; }

    public bool IsActive { get; set; } = true;

    /// <summary>When the reader paused, or null while the plan is running.</summary>
    public DateTimeOffset? PausedAt { get; set; }

    /// <summary>Days spent inside completed pauses, banked on resume.</summary>
    public int PausedDays { get; set; }

    public DateTimeOffset CreatedAt { get; set; }
    public DateTimeOffset UpdatedAt { get; set; }

    /// <inheritdoc />
    public DateTimeOffset ServerUpdatedAt { get; set; }

    public ICollection<ReadingSession> Sessions { get; set; } = [];
    public ICollection<ReadingLogEntry> Log { get; set; } = [];
}
