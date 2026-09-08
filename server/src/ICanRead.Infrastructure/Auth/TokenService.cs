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
    private readonly JwtOptions _options = options.Value;

    public DateTimeOffset AccessTokenExpiry =>
        clock.GetUtcNow().AddMinutes(_options.AccessTokenMinutes);

    public DateTimeOffset RefreshTokenExpiry =>
        clock.GetUtcNow().AddDays(_options.RefreshTokenDays);

    public string CreateAccessToken(User user)
    {
        var key = new SymmetricSecurityKey(Encoding.UTF8.GetBytes(_options.SigningKey));

        var claims = new List<Claim>
        {
            new(JwtRegisteredClaimNames.Sub, user.Id.ToString()),
            new(JwtRegisteredClaimNames.Email, user.Email),
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
