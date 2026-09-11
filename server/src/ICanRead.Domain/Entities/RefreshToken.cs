namespace ICanRead.Domain.Entities;

/// <summary>
/// One issued refresh token.
/// </summary>
/// <remarks>
/// Only the SHA-256 of the token is stored. A refresh token is a bearer
/// credential with a long life, so a dump of this table must not be enough to
/// sign in as anybody — the same reason passwords are not stored either.
///
/// Rotating a token marks the old row <see cref="RevokedAt"/> and records the
/// one that replaced it, so a token presented twice can be recognised as
/// replayed rather than merely unknown.
/// </remarks>
public class RefreshToken
{
    public Guid Id { get; set; }

    public Guid UserId { get; set; }
    public User? User { get; set; }

    /// <summary>Lower-case hex SHA-256 of the token that was handed out.</summary>
    public required string TokenHash { get; set; }

    public DateTimeOffset CreatedAt { get; set; }
    public DateTimeOffset ExpiresAt { get; set; }

    /// <summary>
    /// The address this session was first opened from, for the sessions list.
    /// </summary>
    /// <remarks>
    /// Recorded so a row in "your devices" says something a person can act on.
    /// Not carried forward when the token rotates: a session that moves from a
    /// café to a train is still the same session, and stamping it with wherever
    /// it last refreshed would make the list about the network rather than the
    /// device. Null for sessions issued before this column existed.
    /// </remarks>
    public string? CreatedFromIp { get; set; }

    /// <summary>The client that opened the session, verbatim and untrusted.</summary>
    /// <remarks>
    /// Shown to the reader and never acted on. It is a header the caller
    /// chooses, so it can say anything; it is here to help somebody recognise
    /// their own phone in a list, not to establish what a request is.
    /// </remarks>
    public string? UserAgent { get; set; }

    /// <summary>Set when the token is rotated or the session is signed out.</summary>
    public DateTimeOffset? RevokedAt { get; set; }

    /// <summary>The token issued in its place, for detecting replay.</summary>
    public Guid? ReplacedByTokenId { get; set; }

    public bool IsActive(DateTimeOffset now) =>
        RevokedAt is null && now < ExpiresAt;
}
