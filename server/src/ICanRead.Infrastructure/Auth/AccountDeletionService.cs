using ICanRead.Application.Auth;
using ICanRead.Domain.Entities;
using ICanRead.Infrastructure.Persistence;
using Microsoft.AspNetCore.Identity;
using Microsoft.EntityFrameworkCore;

namespace ICanRead.Infrastructure.Auth;

/// <summary>
/// Closing an account for good.
/// </summary>
/// <remarks>
/// <para>
/// A real delete, not a flag. Google Play requires an in-app way to delete an
/// account, and a row that is merely marked as gone is not a deletion —
/// everything the reader asked us to forget would still be sitting there.
/// </para>
/// <para>
/// The books' PDFs are not part of this, because they were never here. What
/// goes is the account and everything the account carried: the library rows,
/// the plans, the reminders, the reading log, and every session token.
/// </para>
/// </remarks>
public class AccountDeletionService(
    AppDbContext db,
    IPasswordHasher<User> passwordHasher,
    IGoogleTokenVerifier google)
{
    /// <summary>
    /// Deletes the caller's account, once they have proved it is theirs.
    /// </summary>
    /// <remarks>
    /// A valid access token is not proof enough on its own. It lasts half an
    /// hour, so a phone left unlocked on a table is a valid access token, and
    /// this is the one action in the app that cannot be undone. So the reader
    /// re-proves it the same way they got in: the password if they have one,
    /// and a fresh Google token if Google is their only way in.
    /// </remarks>
    public async Task<AccountDeletionOutcome> DeleteAsync(
        Guid userId,
        DeleteAccountRequest request,
        CancellationToken ct)
    {
        var user = await db.Users.FirstOrDefaultAsync(u => u.Id == userId, ct);
        if (user is null) return AccountDeletionOutcome.NotFound;

        if (!await ConfirmedAsync(user, request, ct))
        {
            return AccountDeletionOutcome.NotConfirmed;
        }

        await using var transaction = await db.Database.BeginTransactionAsync(ct);

        // The log first, and by hand. Its foreign key is `Restrict` on purpose —
        // losing the record of what somebody actually read must never be a side
        // effect of tidying up a book — so deleting the account is the one place
        // that has to say, in as many words, that it means the log too.
        await db.ReadingLog
            .Where(entry => entry.Plan!.Book!.UserId == userId)
            .ExecuteDeleteAsync(ct);

        // Everything else follows the account down: books, fingerprints, plans,
        // sessions, refresh tokens and any live reset code are all `Cascade`.
        await db.Users.Where(u => u.Id == userId).ExecuteDeleteAsync(ct);

        await transaction.CommitAsync(ct);
        return AccountDeletionOutcome.Deleted;
    }

    private async Task<bool> ConfirmedAsync(
        User user,
        DeleteAccountRequest request,
        CancellationToken ct)
    {
        if (user.PasswordHash is not null)
        {
            if (string.IsNullOrEmpty(request.Password)) return false;

            return passwordHasher.VerifyHashedPassword(
                user, user.PasswordHash, request.Password)
                != PasswordVerificationResult.Failed;
        }

        // Google-only account. The token is verified against Google and then
        // matched on the subject, never on the email: an email can be changed
        // or reassigned, and matching on it would let one Workspace user delete
        // another's account by inheriting their address.
        if (string.IsNullOrEmpty(request.GoogleIdToken)) return false;

        var principal = await google.VerifyAsync(request.GoogleIdToken, ct);
        return principal is not null && principal.Subject == user.GoogleSubject;
    }
}
