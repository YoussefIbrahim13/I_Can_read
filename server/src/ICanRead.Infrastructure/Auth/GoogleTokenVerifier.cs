using Google.Apis.Auth;
using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Options;

namespace ICanRead.Infrastructure.Auth;

/// <summary>
/// Who Google says the caller is.
/// </summary>
/// <param name="Subject">
/// Google's <c>sub</c> claim: stable for the life of the account, and the only
/// safe key to store. An email can be changed by its owner, and on a Workspace
/// domain it can be handed to somebody else entirely.
/// </param>
public record GooglePrincipal(string Subject, string Email, string? Name);

/// <summary>
/// Checks an ID token against Google's public keys.
/// </summary>
/// <remarks>
/// An interface so tests can stand in a principal without a network call and
/// without a real Google account. The account rules in <see cref="AuthService"/>
/// are what those tests are about; that a signature check works is Google's
/// library's problem, not ours.
/// </remarks>
public interface IGoogleTokenVerifier
{
    /// <summary>The verified principal, or null if the token is not good.</summary>
    Task<GooglePrincipal?> VerifyAsync(string idToken, CancellationToken ct);
}

public class GoogleTokenVerifier(
    IOptions<GoogleOptions> options,
    ILogger<GoogleTokenVerifier> log) : IGoogleTokenVerifier
{
    public async Task<GooglePrincipal?> VerifyAsync(string idToken, CancellationToken ct)
    {
        var config = options.Value;
        if (!config.IsConfigured)
        {
            // Every reason for a refusal is logged, and none of them include
            // the token. A sign-in that fails for a configuration reason is
            // indistinguishable from a forged token at the endpoint — on
            // purpose — so the only place the difference can be seen is here.
            log.LogWarning(
                "Google sign-in was attempted but Google:ClientId is not set.");
            return null;
        }

        GoogleJsonWebSignature.Payload payload;
        try
        {
            payload = await GoogleJsonWebSignature.ValidateAsync(
                idToken,
                new GoogleJsonWebSignature.ValidationSettings
                {
                    // Without this the check is only "Google signed something",
                    // which every ID token from every app on the device also
                    // satisfies. Pinning the audience is what makes it "signed
                    // for us".
                    Audience = [config.ClientId]
                });
        }
        catch (InvalidJwtException e)
        {
            // The token's own timestamps go in alongside the reason. "Expired"
            // means one of two very different things — a stale cached token, or
            // this server's clock disagreeing with Google's — and the numbers
            // are the only way to tell them apart.
            log.LogWarning(
                "Google rejected an ID token: {Reason} (token iat={Iat} exp={Exp}, server now={Now})",
                e.Message,
                Claim(idToken, "iat"),
                Claim(idToken, "exp"),
                DateTimeOffset.UtcNow.ToUnixTimeSeconds());
            return null;
        }
        catch (Exception e)
        {
            // Validating fetches Google's signing certificates over the
            // network. A server that cannot reach Google is a server outage,
            // not a forged token, and saying so is the difference between
            // ten minutes of debugging and an afternoon of it.
            log.LogError(e, "Could not verify a Google ID token.");
            return null;
        }

        // Google will sign a token for an unverified address on some account
        // types. Taking it would let somebody claim an email they do not own,
        // and the email is what a reader is later found by.
        if (!payload.EmailVerified || string.IsNullOrWhiteSpace(payload.Email))
        {
            log.LogWarning("A Google ID token arrived with an unverified email.");
            return null;
        }

        return new GooglePrincipal(payload.Subject, payload.Email, payload.Name);
    }

    /// <summary>
    /// One numeric claim, read without verifying anything.
    /// </summary>
    /// <remarks>
    /// For log messages only, and only reached once a token has already been
    /// refused. Nothing here decides anything — an unverified claim is a
    /// statement by whoever sent it, and the signature check above is what
    /// makes claims mean something.
    /// </remarks>
    private static string Claim(string jwt, string name)
    {
        var parts = jwt.Split('.');
        if (parts.Length != 3) return "?";

        try
        {
            var padded = parts[1].Replace('-', '+').Replace('_', '/');
            padded = padded.PadRight((padded.Length + 3) / 4 * 4, '=');
            using var document = System.Text.Json.JsonDocument.Parse(
                Convert.FromBase64String(padded));
            return document.RootElement.TryGetProperty(name, out var value)
                ? value.ToString()
                : "absent";
        }
        catch (Exception)
        {
            return "?";
        }
    }
}
