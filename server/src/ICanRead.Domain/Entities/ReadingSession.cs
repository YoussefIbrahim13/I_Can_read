namespace ICanRead.Domain.Entities;

/// <summary>
/// One recurring daily reading slot, e.g. "20:00, 5 pages".
/// </summary>
public class ReadingSession : ISyncedEntity
{
    public Guid Id { get; set; }

    public Guid PlanId { get; set; }
    public ReadingPlan? Plan { get; set; }

    /// <summary>Position within the day, 0-based. Also seeds the notification id.</summary>
    public int Ordinal { get; set; }

    /// <summary>
    /// Minutes after local midnight, stored as a plain integer so it is immune
    /// to timezones and DST. The zone is applied on the device that schedules
    /// the reminder, which is the only place that knows it.
    /// </summary>
    public int TimeOfDayMinutes { get; set; }

    /// <summary>This session's slice of the daily quota.</summary>
    public int PagesShare { get; set; }

    /// <summary>Bitmask, bit 0 = Monday .. bit 6 = Sunday. 127 means every day.</summary>
    public int DaysOfWeek { get; set; } = 127;

    public bool IsEnabled { get; set; } = true;

    public DateTimeOffset UpdatedAt { get; set; }

    /// <summary>
    /// When the session was removed, or null while it is live.
    /// </summary>
    /// <remarks>
    /// A tombstone rather than a real delete, so the removal is something a
    /// pull can carry. Editing the reminder times replaces the whole list on
    /// the device; without this the replaced rows would live on here and be
    /// handed back to every other phone as extra reminders.
    /// </remarks>
    public DateTimeOffset? DeletedAt { get; set; }

    /// <inheritdoc />
    public DateTimeOffset ServerUpdatedAt { get; set; }
}
