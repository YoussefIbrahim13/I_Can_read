namespace ICanRead.Domain.Entities;

/// <summary>
/// A stretch of reading actually done.
/// </summary>
/// <remarks>
/// Append-only. Never updated, never deleted, and merged across devices by id
/// alone — last-write-wins here would silently drop entries two devices wrote
/// while offline, and the log is the one table whose whole value is that it is
/// complete.
/// </remarks>
public class ReadingLogEntry : ISyncedEntity
{
    /// <summary>Client-generated, and the idempotency key for pushes.</summary>
    public Guid Id { get; set; }

    public Guid PlanId { get; set; }
    public ReadingPlan? Plan { get; set; }

    /// <summary>Null when the reader read outside any scheduled session.</summary>
    public Guid? SessionId { get; set; }

    /// <summary>
    /// The local calendar day the reading is credited to. The client rolls the
    /// day over at 04:00, not midnight, so late-night reading belongs to the
    /// day the reader is still awake in.
    /// </summary>
    public DateOnly ReadDate { get; set; }

    public int FromPage { get; set; }
    public int ToPage { get; set; }
    public int PagesRead { get; set; }
    public int DurationSeconds { get; set; }

    public DateTimeOffset CreatedAt { get; set; }

    /// <inheritdoc />
    public DateTimeOffset ServerUpdatedAt { get; set; }
}
