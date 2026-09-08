namespace ICanRead.Domain.Entities;

/// <summary>
/// A row that travels between devices.
/// </summary>
public interface ISyncedEntity
{
    /// <summary>
    /// When this server last wrote the row. The cursor every pull is filtered
    /// on.
    /// </summary>
    /// <remarks>
    /// Deliberately separate from the client's own <c>UpdatedAt</c>. That one
    /// is a device clock, and two phones disagreeing by a few minutes is
    /// ordinary — a pull filtered on it would silently skip rows written by a
    /// device whose clock runs behind. This column is only ever set here, from
    /// one clock, so "everything since X" means the same thing to every device.
    ///
    /// The client's <c>UpdatedAt</c> is still what decides conflicts; it is a
    /// statement about when the reader made a change, which is exactly the
    /// right question for last-write-wins and the wrong one for a cursor.
    /// </remarks>
    DateTimeOffset ServerUpdatedAt { get; set; }
}
