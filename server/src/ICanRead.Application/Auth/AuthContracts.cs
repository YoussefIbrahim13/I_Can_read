using System.ComponentModel.DataAnnotations;
using ICanRead.Domain.Entities;

namespace ICanRead.Application.Auth;

// Attributes sit on the constructor parameters, not on the generated
// properties: for a record, MVC's validator refuses to run at all if the
// metadata is on the property instead.
public record RegisterRequest(
    [Required, EmailAddress, MaxLength(320)] string Email,
    // Length is the only rule. Composition rules ("one capital, one symbol")
    // push people towards shorter, more guessable passwords and are no longer
    // recommended by NIST.
    [Required, MinLength(8), MaxLength(256)] string Password,
    [MaxLength(200)] string? DisplayName);

public record LoginRequest(
    [Required, EmailAddress] string Email,
    [Required] string Password);

public record RefreshRequest([Required] string RefreshToken);

public record ForgotPasswordRequest([Required, EmailAddress, MaxLength(320)] string Email);

/// <summary>
/// The address, the code that was emailed to it, and the new password.
/// </summary>
/// <remarks>
/// The address travels with the code so the code itself can stay six digits.
/// Without it the server would have to find an account by code alone, which
/// means the code has to be unique across every account at once, and six digits
/// is nowhere near enough for that.
/// </remarks>
public record ResetPasswordRequest(
    [Required, EmailAddress, MaxLength(320)] string Email,
    [Required, StringLength(6, MinimumLength = 6)] string Code,
    [Required, MinLength(8), MaxLength(256)] string NewPassword);

/// <summary>
/// Proof that the caller is the account holder, in whichever form they have.
/// </summary>
/// <remarks>
/// Both are optional here and exactly one is required in practice: the password
/// for an account that has one, a fresh Google ID token for an account that
/// only ever signs in with Google. Which one applies is decided from the stored
/// account, not from what the caller chose to send.
/// </remarks>
public record AccountProof(string? Password, string? GoogleIdToken);

/// <summary>Closing an account: the same proof, and nothing else.</summary>
public record DeleteAccountRequest(string? Password, string? GoogleIdToken)
{
    public AccountProof Proof => new(Password, GoogleIdToken);
}

/// <summary>
/// Setting a password while signed in.
/// </summary>
/// <remarks>
/// The old password is proof, not a formality: an access token lasts half an
/// hour, so a phone left unlocked on a table is a valid access token, and a
/// password change is how an account is taken over for good. An account that
/// only signs in with Google has no old password to give, and proves itself
/// with a fresh Google token instead — the same pair of doors closing an
/// account uses.
/// </remarks>
public record ChangePasswordRequest(
    string? CurrentPassword,
    string? GoogleIdToken,
    [Required, MinLength(8), MaxLength(256)] string NewPassword)
{
    public AccountProof Proof => new(CurrentPassword, GoogleIdToken);
}

/// <summary>What the reader is called, on their own say-so.</summary>
public record UpdateProfileRequest([MaxLength(200)] string? DisplayName);

/// <summary>The six digits emailed to prove the address on the account.</summary>
public record VerifyEmailRequest(
    [Required, StringLength(6, MinimumLength = 6)] string Code);

/// <summary>
/// A Google ID token, straight from the device.
/// </summary>
/// <remarks>
/// The token, not the email or the subject. Those are claims the caller could
/// simply assert; this is a statement signed by Google that the server checks
/// for itself. Used both to sign in and to link Google to an account that
/// already exists.
/// </remarks>
public record GoogleTokenRequest([Required] string IdToken);

/// <summary>
/// Where a session was opened from, for the reader's own device list.
/// </summary>
/// <remarks>
/// Passed in from the API layer rather than read from an
/// <c>IHttpContextAccessor</c> down in the services, so that what the auth
/// rules depend on stays visible in their signatures and Infrastructure keeps
/// knowing nothing about HTTP.
/// </remarks>
public record SessionOrigin(string? IpAddress, string? UserAgent)
{
    /// <summary>For the paths where nobody is watching — tests, seeding.</summary>
    public static readonly SessionOrigin Unknown = new(null, null);
}

/// <summary>One live session, as the reader's device list shows it.</summary>
/// <remarks>
/// No token and no hash of one. This is a list to recognise devices in and
/// throw them out of, and handing the caller anything resembling the
/// credential would defeat the point of never storing it in the first place.
/// </remarks>
public record SessionResponse(
    Guid Id,
    DateTimeOffset CreatedAt,
    DateTimeOffset ExpiresAt,
    string? IpAddress,
    string? Device,
    /// <summary>True for the session the request itself arrived on.</summary>
    bool IsCurrent);

public enum AccountDeletionOutcome
{
    Deleted,

    /// <summary>The password or Google token did not prove it was them.</summary>
    NotConfirmed,

    /// <summary>The token names an account that is already gone.</summary>
    NotFound
}

/// <summary>
/// What a one-time code did.
/// </summary>
/// <remarks>
/// One failure value, as with sign-in: a wrong code, an expired code, a code
/// already spent and an address with no account are all <see cref="Invalid"/>,
/// because telling them apart is a way to find out which addresses have
/// accounts.
/// </remarks>
public enum CodeOutcome
{
    Accepted,
    Invalid
}

/// <summary>
/// What a change to an existing account did.
/// </summary>
/// <remarks>
/// One enum for every <c>/api/me</c> change rather than one per endpoint. They
/// all answer the same question — did it happen, and if not, which of a short
/// list of reasons — and splitting it would mean three near-identical enums
/// that drift.
/// </remarks>
public enum AccountChangeOutcome
{
    Done,

    /// <summary>The token names an account that is gone.</summary>
    NotFound,

    /// <summary>The password or Google token did not prove it was them.</summary>
    NotConfirmed,

    /// <summary>Google would not vouch for the token it was given.</summary>
    InvalidGoogleToken,

    /// <summary>
    /// The address on this account has not been proved yet, so it cannot be
    /// matched against a Google account's.
    /// </summary>
    EmailNotVerified,

    /// <summary>The Google token is for a different address than the account's.</summary>
    GoogleEmailMismatch,

    /// <summary>That Google account is already the way into a different account here.</summary>
    GoogleAlreadyInUse,

    /// <summary>
    /// Doing this would leave the account with no way in at all — unlinking
    /// Google from an account that never had a password.
    /// </summary>
    WouldLockOut
}

/// <summary>
/// The outcome of a change, and the new session when the change made one.
/// </summary>
/// <remarks>
/// <see cref="Session"/> is non-null only for a password change. Changing a
/// password throws out every refresh token the account has, including the
/// caller's own, so it has to hand back a replacement pair or the reader would
/// be signed out of the phone they are holding.
/// </remarks>
public record AccountChangeResult(AccountChangeOutcome Outcome, AuthResponse? Session = null)
{
    public static AccountChangeResult Ok(AuthResponse? session = null) =>
        new(AccountChangeOutcome.Done, session);

    public static AccountChangeResult Fail(AccountChangeOutcome outcome) => new(outcome);

    public bool Succeeded => Outcome == AccountChangeOutcome.Done;
}

/// <summary>What the client gets back from every successful auth call.</summary>
public record AuthResponse(
    string AccessToken,
    string RefreshToken,
    DateTimeOffset AccessTokenExpiresAt,
    UserResponse User);

/// <summary>
/// The account, as its own holder sees it.
/// </summary>
/// <remarks>
/// The three flags are what the client needs to know which doors to offer: an
/// account with no password gets "set one" rather than "change it", an account
/// with Google linked gets "unlink", and an unverified address gets a prompt
/// instead of the link button. Working that out client-side from what happened
/// to be typed on the sign-in screen would be wrong the moment a second device
/// is involved.
/// </remarks>
public record UserResponse(
    Guid Id,
    string Email,
    string? DisplayName,
    bool EmailVerified,
    bool HasPassword,
    bool GoogleLinked);

public static class UserMapping
{
    /// <summary>
    /// The account as its holder sees it.
    /// </summary>
    /// <remarks>
    /// One place, because every auth response carries this shape and six
    /// endpoints build it. The flags are derived rather than copied, so an
    /// account that sets a password stops being offered "set a password"
    /// without anybody having to remember to say so.
    /// </remarks>
    public static UserResponse ToResponse(this User user) => new(
        user.Id,
        user.Email,
        user.DisplayName,
        user.IsEmailVerified,
        user.PasswordHash is not null,
        user.GoogleSubject is not null);
}

/// <summary>
/// The outcome of an auth attempt.
/// </summary>
/// <remarks>
/// One failure value for bad credentials, covering both "no such email" and
/// "wrong password": telling them apart hands an attacker a way to find out
/// which addresses have accounts.
/// </remarks>
public enum AuthError
{
    None,
    EmailAlreadyRegistered,
    InvalidCredentials,
    InvalidRefreshToken,

    /// <summary>Google would not vouch for the token it was given.</summary>
    InvalidGoogleToken,

    /// <summary>
    /// The Google account's email already belongs to a password account that
    /// has never proved it owns the address. See <c>GoogleSignInAsync</c>.
    /// </summary>
    EmailBelongsToPasswordAccount,

    /// <summary>
    /// Too many wrong passwords for this account, too recently.
    /// </summary>
    /// <remarks>
    /// Carries <see cref="AuthResult.RetryAfter"/> so the caller can be told
    /// how long to wait.
    /// </remarks>
    AccountLocked
}

public record AuthResult(AuthError Error, AuthResponse? Response, TimeSpan? RetryAfter = null)
{
    public static AuthResult Ok(AuthResponse response) => new(AuthError.None, response);
    public static AuthResult Fail(AuthError error) => new(error, null);

    public static AuthResult Locked(TimeSpan retryAfter) =>
        new(AuthError.AccountLocked, null, retryAfter);

    public bool Succeeded => Error == AuthError.None;
}
