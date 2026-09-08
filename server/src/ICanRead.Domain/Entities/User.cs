namespace ICanRead.Domain.Entities;

/// <summary>
/// An account. Owns everything else in the schema.
/// </summary>
/// <remarks>
/// A user may have a password, a Google subject, or both: someone who signed
/// up with email can later link Google, and someone who came in through Google
/// can set a password. Neither column is required on its own, but a row with
/// neither cannot sign in, which the registration paths are responsible for.
/// </remarks>
public class User
{
    public Guid Id { get; set; }

    /// <summary>Stored lower-cased; the unique index is what enforces it.</summary>
    public required string Email { get; set; }

    /// <summary>Null for an account that only ever signs in with Google.</summary>
    public string? PasswordHash { get; set; }

    /// <summary>Google's stable subject claim, never the email.</summary>
    public string? GoogleSubject { get; set; }

    public string? DisplayName { get; set; }

    public DateTimeOffset CreatedAt { get; set; }
    public DateTimeOffset UpdatedAt { get; set; }

    public ICollection<Book> Books { get; set; } = [];
    public ICollection<RefreshToken> RefreshTokens { get; set; } = [];
}
