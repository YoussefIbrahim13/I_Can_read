using System.Security.Cryptography;
using System.Text;
using ICanRead.Application.Auth;
using ICanRead.Application.Email;
using ICanRead.Domain.Entities;
using ICanRead.Infrastructure.Persistence;
using Microsoft.AspNetCore.Identity;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Logging;

namespace ICanRead.Infrastructure.Auth;

/// <summary>
/// "I forgot my password": issues a one-time code and spends it.
/// </summary>
public class PasswordResetService(
    AppDbContext db,
    IEmailSender email,
    IPasswordHasher<User> passwordHasher,
    TimeProvider clock,
    ILogger<PasswordResetService> logger)
{
    private static readonly TimeSpan Lifetime = TimeSpan.FromMinutes(15);

    /// <summary>
    /// Emails a code, if the address belongs to an account.
    /// </summary>
    /// <remarks>
    /// Returns the same nothing either way, and never throws for a mail
    /// failure. Both are the same rule: the caller must not be able to tell
    /// whether an address has an account here. A 500 on a send failure would
    /// answer that question precisely, because nothing is sent for an address
    /// that has none.
    /// </remarks>
    public async Task RequestAsync(string emailAddress, CancellationToken ct)
    {
        var normalised = Normalise(emailAddress);
        var user = await db.Users.FirstOrDefaultAsync(u => u.Email == normalised, ct);
        if (user is null) return;

        var now = clock.GetUtcNow();

        // Only the newest code is live. Otherwise asking twice would leave two
        // valid codes in the world, and every extra request would widen the
        // window rather than restart it.
        await db.PasswordResetCodes
            .Where(c => c.UserId == user.Id && c.ConsumedAt == null)
            .ExecuteUpdateAsync(c => c.SetProperty(x => x.ConsumedAt, now), ct);

        var code = CreateCode();
        db.PasswordResetCodes.Add(new PasswordResetCode
        {
            Id = Guid.NewGuid(),
            UserId = user.Id,
            CodeHash = HashCode(code),
            CreatedAt = now,
            ExpiresAt = now + Lifetime
        });
        await db.SaveChangesAsync(ct);

        try
        {
            await email.SendAsync(BuildMessage(user.Email, code), ct);
        }
        catch (Exception error)
        {
            logger.LogError(error, "Could not send a password reset code.");
        }
    }

    /// <summary>
    /// Sets a new password if the code is the live one for that address.
    /// </summary>
    /// <remarks>
    /// Every session is signed out on success. Someone asking for a reset may
    /// well be asking because somebody else is in their account, and leaving
    /// that intruder's refresh token working would make the reset cosmetic.
    /// </remarks>
    public async Task<PasswordResetOutcome> ResetAsync(
        string emailAddress,
        string code,
        string newPassword,
        CancellationToken ct)
    {
        var normalised = Normalise(emailAddress);
        var now = clock.GetUtcNow();

        var user = await db.Users.FirstOrDefaultAsync(u => u.Email == normalised, ct);
        if (user is null) return PasswordResetOutcome.Invalid;

        var stored = await db.PasswordResetCodes
            .Where(c => c.UserId == user.Id)
            .OrderByDescending(c => c.CreatedAt)
            .FirstOrDefaultAsync(ct);

        if (stored is null || !stored.IsLive(now)) return PasswordResetOutcome.Invalid;

        if (!CryptographicOperations.FixedTimeEquals(
                Encoding.UTF8.GetBytes(stored.CodeHash),
                Encoding.UTF8.GetBytes(HashCode(code))))
        {
            // Counted, and spent once the count runs out: six digits is only a
            // million guesses, and this is what stops a script working through
            // them while the code is still live.
            stored.Attempts++;
            if (stored.Attempts >= PasswordResetCode.MaxAttempts)
            {
                stored.ConsumedAt = now;
            }
            await db.SaveChangesAsync(ct);
            return PasswordResetOutcome.Invalid;
        }

        stored.ConsumedAt = now;
        user.PasswordHash = passwordHasher.HashPassword(user, newPassword);
        user.UpdatedAt = now;

        await db.RefreshTokens
            .Where(t => t.UserId == user.Id && t.RevokedAt == null)
            .ExecuteUpdateAsync(t => t.SetProperty(x => x.RevokedAt, now), ct);

        await db.SaveChangesAsync(ct);
        return PasswordResetOutcome.Reset;
    }

    private static EmailMessage BuildMessage(string address, string code)
    {
        const string subject = "Your Yaqra password reset code";
        var text =
            $"Your password reset code is {code}.\n\n"
            + "It expires in 15 minutes. If you did not ask for it, you can "
            + "ignore this message — your password has not changed.";
        var html =
            $"<p>Your password reset code is <strong>{code}</strong>.</p>"
            + "<p>It expires in 15 minutes. If you did not ask for it, you can "
            + "ignore this message — your password has not changed.</p>";

        return new EmailMessage(address, subject, text, html);
    }

    /// <summary>Six digits, from the cryptographic generator rather than Random.</summary>
    private static string CreateCode() =>
        RandomNumberGenerator.GetInt32(0, 1_000_000).ToString("D6");

    private static string HashCode(string code) =>
        Convert.ToHexStringLower(SHA256.HashData(Encoding.UTF8.GetBytes(code)));

    private static string Normalise(string email) => email.Trim().ToLowerInvariant();
}
