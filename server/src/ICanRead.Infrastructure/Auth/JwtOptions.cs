namespace ICanRead.Infrastructure.Auth;

public class JwtOptions
{
    public const string Section = "Jwt";

    public string Issuer { get; set; } = "i-can-read";
    public string Audience { get; set; } = "i-can-read-app";

    /// <summary>
    /// Short, because nothing revokes an access token before it expires. The
    /// refresh token is the long-lived half and that one is revocable.
    /// </summary>
    public int AccessTokenMinutes { get; set; } = 30;

    public int RefreshTokenDays { get; set; } = 60;

    /// <summary>
    /// HMAC signing key. Must be at least 32 bytes for HS256; validated on
    /// startup rather than at first sign-in, so a misconfigured deployment
    /// fails immediately instead of when the first reader tries to log in.
    /// </summary>
    public string SigningKey { get; set; } = "";
}
