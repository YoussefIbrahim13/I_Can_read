using System.IdentityModel.Tokens.Jwt;
using System.Security.Claims;
using System.Security.Cryptography;
using System.Text;
using ICanRead.Domain.Entities;
using Microsoft.Extensions.Options;
using Microsoft.IdentityModel.Tokens;

namespace ICanRead.Infrastructure.Auth;

/// <summary>
/// Mints access tokens and the opaque refresh tokens that renew them.
/// </summary>
public class TokenService(IOptions<JwtOptions> options, TimeProvider clock)
{
    /// <summary>
    /// The claim naming the session an access token belongs to.
    /// </summary>
    /// <remarks>
    /// Written as the bare <c>sid</c>, but read back as
    /// <see cref="System.Security.Claims.ClaimTypes.Sid"/>: the JWT handler's
    /// inbound map rewrites it on the way in. Anything reading it should use
    /// <c>SessionIdFrom</c> rather than either name directly.
    /// </remarks>
    public const string SessionClaim = "sid";

    private readonly JwtOptions _options = options.Value;

    /// <summary>
    /// The session an incoming request's token names, if it names one.
    /// </summary>
    /// <remarks>
    /// Null for a token minted before the claim existed. Those are valid for
    /// the half hour they have left, and the endpoints that need a session
    /// treat "which one?" as unanswerable rather than as an error — the reader
    /// gets a sessions list with nothing marked current until the next refresh.
    /// </remarks>
    public static Guid? SessionIdFrom(ClaimsPrincipal principal)
    {
        var raw = principal.FindFirstValue(ClaimTypes.Sid)
                  ?? principal.FindFirstValue(SessionClaim);

        return Guid.TryParse(raw, out var id) ? id : null;
    }

    public DateTimeOffset AccessTokenExpiry =>
        clock.GetUtcNow().AddMinutes(_options.AccessTokenMinutes);

    public DateTimeOffset RefreshTokenExpiry =>
        clock.GetUtcNow().AddDays(_options.RefreshTokenDays);

    /// <summary>
    /// Mints an access token for one session.
    /// </summary>
    /// <param name="sessionId">
    /// The refresh token row this token was issued alongside. It travels as the
    /// <c>sid</c> claim so the sessions list can mark the device the request
    /// arrived on, and so signing out "everywhere else" knows what "else"
    /// means. It is an id, not a credential: knowing it lets a caller name a
    /// session, and every endpoint that acts on one checks it belongs to the
    /// account in the token first.
    /// </param>
    public string CreateAccessToken(User user, Guid sessionId)
    {
        var key = new SymmetricSecurityKey(Encoding.UTF8.GetBytes(_options.SigningKey));

        var claims = new List<Claim>
        {
            new(JwtRegisteredClaimNames.Sub, user.Id.ToString()),
            new(JwtRegisteredClaimNames.Email, user.Email),
            new(SessionClaim, sessionId.ToString()),
            // A unique token id, so a future revocation list has something to
            // name a single token by.
            new(JwtRegisteredClaimNames.Jti, Guid.NewGuid().ToString())
        };

        var token = new JwtSecurityToken(
            issuer: _options.Issuer,
            audience: _options.Audience,
            claims: claims,
            notBefore: clock.GetUtcNow().UtcDateTime,
            expires: AccessTokenExpiry.UtcDateTime,
            signingCredentials: new SigningCredentials(key, SecurityAlgorithms.HmacSha256));

        return new JwtSecurityTokenHandler().WriteToken(token);
    }

    /// <summary>
    /// A refresh token: 256 bits of cryptographic randomness, and nothing else.
    /// </summary>
    /// <remarks>
    /// Deliberately opaque rather than a second JWT. It carries no claims, so
    /// there is nothing in it to go stale, and it is only ever meaningful by
    /// matching a row that the server can revoke.
    /// </remarks>
    public static string CreateRefreshToken() =>
        Convert.ToBase64String(RandomNumberGenerator.GetBytes(32));

    /// <summary>
    /// Hashes a refresh token for storage.
    /// </summary>
    /// <remarks>
    /// Plain SHA-256, not a password hash. The token is already 256 bits of
    /// uniform randomness, so there is no dictionary to attack and no reason to
    /// pay a work factor on every refresh; the hash is here so that a leaked
    /// database is not a set of usable credentials.
    /// </remarks>
    public static string HashRefreshToken(string token) =>
        Convert.ToHexStringLower(SHA256.HashData(Encoding.UTF8.GetBytes(token)));
}
