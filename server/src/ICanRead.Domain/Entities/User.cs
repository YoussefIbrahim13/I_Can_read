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
    /// <summary>Consecutive failures before a sign-in starts being made to wait.</summary>
    /// <remarks>
    /// Far above what a person mistyping their own password reaches, and far
    /// below the million guesses that make a weak password worth attacking.
    /// </remarks>
    public const int SignInFailuresBeforeLockout = 10;

    /// <summary>The longest a lockout is allowed to grow to.</summary>
    /// <remarks>
    /// A ceiling rather than an ever-doubling wait, because the person most
    /// likely to be locked out of an account is the person who owns it. Fifteen
    /// minutes costs an attacker four guesses an hour and costs a reader one
    /// cup of tea.
    /// </remarks>
    public static readonly TimeSpan MaxLockout = TimeSpan.FromMinutes(15);

    public Guid Id { get; set; }

    /// <summary>Stored lower-cased; the unique index is what enforces it.</summary>
    public required string Email { get; set; }

    /// <summary>
    /// When the reader proved they can read mail at <see cref="Email"/>.
    /// </summary>
    /// <remarks>
    /// Null until they spend an emailed code. Registration does not wait for it
    /// — a reader who cannot get into their library until they find an email is
    /// a reader who gives up — but it is what lets a Google account and a
    /// password account with the same address be joined up. See
    /// <c>AuthService.GoogleSignInAsync</c>.
    /// </remarks>
    public DateTimeOffset? EmailVerifiedAt { get; set; }

    public bool IsEmailVerified => EmailVerifiedAt is not null;

    /// <summary>Null for an account that only ever signs in with Google.</summary>
    public string? PasswordHash { get; set; }

    /// <summary>Google's stable subject claim, never the email.</summary>
    public string? GoogleSubject { get; set; }

    public string? DisplayName { get; set; }

    /// <summary>
    /// Failed sign-ins since the last successful one.
    /// </summary>
    /// <remarks>
    /// Per account rather than per address. The IP limiter in front of these
    /// endpoints is the defence against one machine guessing quickly; this is
    /// the defence against many machines guessing at one account slowly, which
    /// the IP limiter cannot see at all.
    /// </remarks>
    public int FailedSignInCount { get; set; }

    /// <summary>Set while the account is refusing sign-ins. Null when it is not.</summary>
    public DateTimeOffset? LockedUntil { get; set; }

    public bool IsLockedAt(DateTimeOffset now) => LockedUntil is { } until && now < until;

    public DateTimeOffset CreatedAt { get; set; }
    public DateTimeOffset UpdatedAt { get; set; }

    public ICollection<Book> Books { get; set; } = [];
    public ICollection<RefreshToken> RefreshTokens { get; set; } = [];
}
