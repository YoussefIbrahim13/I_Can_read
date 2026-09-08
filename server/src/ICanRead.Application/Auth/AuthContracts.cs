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
