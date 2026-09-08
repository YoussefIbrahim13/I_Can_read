using System.ComponentModel.DataAnnotations;

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
/// What a reset attempt did.
/// </summary>
/// <remarks>
/// One failure value, as with sign-in: a wrong code, an expired code, a code
/// already spent and an address with no account are all
/// <see cref="Invalid"/>, because telling them apart is a way to find out which
/// addresses have accounts.
/// </remarks>
public enum PasswordResetOutcome
{
    Reset,
    Invalid
}

/// <summary>
/// A Google ID token, straight from the device.
/// </summary>
/// <remarks>
/// The token, not the email or the subject. Those are claims the caller could
/// simply assert; this is a statement signed by Google that the server checks
/// for itself.
/// </remarks>
public record GoogleSignInRequest([Required] string IdToken);

/// <summary>What the client gets back from every successful auth call.</summary>
public record AuthResponse(
    string AccessToken,
    string RefreshToken,
    DateTimeOffset AccessTokenExpiresAt,
    UserResponse User);

public record UserResponse(Guid Id, string Email, string? DisplayName);

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
    /// The Google account's email already belongs to a password account, and
    /// the two are deliberately not joined up. See <c>GoogleSignInAsync</c>.
    /// </summary>
    EmailBelongsToPasswordAccount
}

public record AuthResult(AuthError Error, AuthResponse? Response)
{
    public static AuthResult Ok(AuthResponse response) => new(AuthError.None, response);
    public static AuthResult Fail(AuthError error) => new(error, null);
    public bool Succeeded => Error == AuthError.None;
}
