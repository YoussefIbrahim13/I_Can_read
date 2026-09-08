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

    /// <summary>Set when the token is rotated or the session is signed out.</summary>
    public DateTimeOffset? RevokedAt { get; set; }

    /// <summary>The token issued in its place, for detecting replay.</summary>
    public Guid? ReplacedByTokenId { get; set; }

    public bool IsActive(DateTimeOffset now) =>
        RevokedAt is null && now < ExpiresAt;
}
