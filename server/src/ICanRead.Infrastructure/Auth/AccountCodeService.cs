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
/// The six-digit codes this server emails, and what spending one does.
/// </summary>
/// <remarks>
/// Two flows, one mechanism: "I forgot my password" and "prove this address is
/// yours" differ only in what happens after the digits match. Issuing, hashing,
/// expiring, counting wrong tries and keeping exactly one code live are
/// identical, so they live here once rather than in two services that drift.
/// </remarks>
public class AccountCodeService(
    AppDbContext db,
    IEmailSender email,
    IPasswordHasher<User> passwordHasher,
    TimeProvider clock,
    ILogger<AccountCodeService> logger)
{
    /// <summary>
    /// Emails a password reset code, if the address belongs to an account.
    /// </summary>
    /// <remarks>
    /// Returns the same nothing either way, and never throws for a mail
    /// failure. Both are the same rule: the caller must not be able to tell
    /// whether an address has an account here. A 500 on a send failure would
    /// answer that question precisely, because nothing is sent for an address
    /// that has none.
    /// </remarks>
    public async Task RequestResetAsync(string emailAddress, CancellationToken ct)
    {
        var normalised = Normalise(emailAddress);
        var user = await db.Users.FirstOrDefaultAsync(u => u.Email == normalised, ct);
        if (user is null) return;

        await IssueAndSendAsync(user, AccountCodePurpose.PasswordReset, ct);
    }

    /// <summary>
    /// Sets a new password if the code is the live one for that address.
    /// </summary>
    /// <remarks>
    /// Every session is signed out on success. Someone asking for a reset may
    /// well be asking because somebody else is in their account, and leaving
    /// that intruder's refresh token working would make the reset cosmetic.
    /// </remarks>
    public async Task<CodeOutcome> ResetAsync(
        string emailAddress,
        string code,
        string newPassword,
        CancellationToken ct)
    {
        var normalised = Normalise(emailAddress);
        var user = await db.Users.FirstOrDefaultAsync(u => u.Email == normalised, ct);
        if (user is null) return CodeOutcome.Invalid;

        var outcome = await SpendAsync(user, AccountCodePurpose.PasswordReset, code, ct);
        if (outcome == CodeOutcome.Invalid) return CodeOutcome.Invalid;

        var now = clock.GetUtcNow();
        user.PasswordHash = passwordHasher.HashPassword(user, newPassword);
        user.UpdatedAt = now;

        // A reader who has just proved they can read mail at this address is
        // not someone a lockout should still be holding out. The wrong
        // passwords that caused it were, by definition, not theirs.
        user.FailedSignInCount = 0;
        user.LockedUntil = null;

        await db.RefreshTokens
            .Where(t => t.UserId == user.Id && t.RevokedAt == null)
            .ExecuteUpdateAsync(t => t.SetProperty(x => x.RevokedAt, now), ct);

        await db.SaveChangesAsync(ct);
        return CodeOutcome.Accepted;
    }

    /// <summary>Emails a code proving the address on an account.</summary>
    public Task SendVerificationAsync(User user, CancellationToken ct) =>
        IssueAndSendAsync(user, AccountCodePurpose.EmailVerification, ct);

    /// <summary>Marks the address proved, if the code is the live one.</summary>
    public async Task<CodeOutcome> VerifyEmailAsync(
        User user,
        string code,
        CancellationToken ct)
    {
        // Already proved. Saying so rather than spending a code means a reader
        // who taps the button twice on a slow connection does not see a
        // failure for something that has, in fact, happened.
        if (user.IsEmailVerified) return CodeOutcome.Accepted;

        var outcome = await SpendAsync(user, AccountCodePurpose.EmailVerification, code, ct);
        if (outcome == CodeOutcome.Invalid) return CodeOutcome.Invalid;

        var now = clock.GetUtcNow();
        user.EmailVerifiedAt = now;
        user.UpdatedAt = now;

        await db.SaveChangesAsync(ct);
        return CodeOutcome.Accepted;
    }

    /// <summary>
    /// Issues a code for one purpose and mails it, retiring any earlier one.
    /// </summary>
    /// <remarks>
    /// Only the newest code of a purpose is live. Otherwise asking twice would
    /// leave two valid codes in the world, and every extra request would widen
    /// the window rather than restart it. Codes for the *other* purpose are
    /// left alone: they answer a different question and retiring them would let
    /// one flow silently break the other.
    /// </remarks>
    private async Task IssueAndSendAsync(
        User user,
        AccountCodePurpose purpose,
        CancellationToken ct)
    {
        var now = clock.GetUtcNow();

        await db.AccountCodes
            .Where(c => c.UserId == user.Id
                        && c.Purpose == purpose
                        && c.ConsumedAt == null)
            .ExecuteUpdateAsync(c => c.SetProperty(x => x.ConsumedAt, now), ct);

        var code = CreateCode();
        db.AccountCodes.Add(new AccountCode
        {
            Id = Guid.NewGuid(),
            UserId = user.Id,
            Purpose = purpose,
            CodeHash = HashCode(code),
            CreatedAt = now,
            ExpiresAt = now + AccountCode.Lifetime
        });
        await db.SaveChangesAsync(ct);

        try
        {
            await email.SendAsync(BuildMessage(user.Email, purpose, code), ct);
        }
        catch (Exception error)
        {
            logger.LogError(error, "Could not send a {Purpose} code.", purpose);
        }
    }

    /// <summary>
    /// Checks the digits against the live code, and spends it either way.
    /// </summary>
    /// <remarks>
    /// On a wrong code this saves the attempt count itself, because the caller
    /// returns immediately and that count is the whole defence. On a right one
    /// it only marks the row consumed and leaves the save to the caller, so
    /// that spending the code and acting on it land in one write.
    /// </remarks>
    private async Task<CodeOutcome> SpendAsync(
        User user,
        AccountCodePurpose purpose,
        string code,
        CancellationToken ct)
    {
        var now = clock.GetUtcNow();

        var stored = await db.AccountCodes
            .Where(c => c.UserId == user.Id && c.Purpose == purpose)
            .OrderByDescending(c => c.CreatedAt)
            .FirstOrDefaultAsync(ct);

        if (stored is null || !stored.IsLive(now)) return CodeOutcome.Invalid;

        if (!CryptographicOperations.FixedTimeEquals(
                Encoding.UTF8.GetBytes(stored.CodeHash),
                Encoding.UTF8.GetBytes(HashCode(code))))
        {
            // Counted, and spent once the count runs out: six digits is only a
            // million guesses, and this is what stops a script working through
            // them while the code is still live.
            stored.Attempts++;
            if (stored.Attempts >= AccountCode.MaxAttempts)
            {
                stored.ConsumedAt = now;
            }
            await db.SaveChangesAsync(ct);
            return CodeOutcome.Invalid;
        }

        stored.ConsumedAt = now;
        return CodeOutcome.Accepted;
    }

    private static EmailMessage BuildMessage(
        string address,
        AccountCodePurpose purpose,
        string code)
    {
        var (subject, line) = purpose switch
        {
            AccountCodePurpose.EmailVerification => (
                "Confirm your Yaqra email address",
                "Your confirmation code is"),
            _ => (
                "Your Yaqra password reset code",
                "Your password reset code is")
        };

        var reassurance = purpose == AccountCodePurpose.EmailVerification
            ? "If you did not ask for it, you can ignore this message."
            : "If you did not ask for it, you can ignore this message — your "
              + "password has not changed.";

        var text = $"{line} {code}.\n\nIt expires in 15 minutes. {reassurance}";
        var html =
            $"<p>{line} <strong>{code}</strong>.</p>"
            + $"<p>It expires in 15 minutes. {reassurance}</p>";

        return new EmailMessage(address, subject, text, html);
    }

    /// <summary>Six digits, from the cryptographic generator rather than Random.</summary>
    private static string CreateCode() =>
        RandomNumberGenerator.GetInt32(0, 1_000_000).ToString("D6");

    private static string HashCode(string code) =>
        Convert.ToHexStringLower(SHA256.HashData(Encoding.UTF8.GetBytes(code)));

    private static string Normalise(string email) => email.Trim().ToLowerInvariant();
}
