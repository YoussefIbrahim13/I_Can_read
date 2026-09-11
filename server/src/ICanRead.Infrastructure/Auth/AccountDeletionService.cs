using ICanRead.Application.Auth;
using ICanRead.Infrastructure.Persistence;
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
public class AccountDeletionService(AppDbContext db, AccountConfirmation confirmation)
{
    /// <summary>
    /// Deletes the caller's account, once they have proved it is theirs.
    /// </summary>
    /// <remarks>
    /// The proof is not a formality — see <see cref="AccountConfirmation"/> for
    /// why an access token on its own is not enough for the one action in the
    /// app that cannot be undone.
    /// </remarks>
    public async Task<AccountDeletionOutcome> DeleteAsync(
        Guid userId,
        DeleteAccountRequest request,
        CancellationToken ct)
    {
        var user = await db.Users.FirstOrDefaultAsync(u => u.Id == userId, ct);
        if (user is null) return AccountDeletionOutcome.NotFound;

        if (!await confirmation.ConfirmsAsync(user, request.Proof, ct))
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
}
