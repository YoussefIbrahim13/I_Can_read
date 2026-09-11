using ICanRead.Application.Auth;
using ICanRead.Domain.Entities;
using Microsoft.AspNetCore.Identity;

namespace ICanRead.Infrastructure.Auth;

/// <summary>
/// Re-proving that an account belongs to the caller holding its access token.
/// </summary>
/// <remarks>
/// A valid access token is not proof enough for everything. It lasts half an
/// hour, so a phone left unlocked on a table is a valid access token — and the
/// three things that use this are the three that a stranger with that phone
/// could otherwise do for good: delete the account, take its password, or take
/// away the Google sign-in that is its only way in.
///
/// So the reader re-proves it the same way they got in: the password if they
/// have one, and a fresh Google token if Google is their only way in. Which one
/// applies is decided from the stored account, never from what the caller chose
/// to send — otherwise an account with a password could be confirmed by
/// whichever of the two was easier to obtain.
/// </remarks>
public class AccountConfirmation(
    IPasswordHasher<User> passwordHasher,
    IGoogleTokenVerifier google)
{
    public async Task<bool> ConfirmsAsync(
        User user,
        AccountProof proof,
        CancellationToken ct)
    {
        if (user.PasswordHash is not null)
        {
            if (string.IsNullOrEmpty(proof.Password)) return false;

            return passwordHasher.VerifyHashedPassword(
                user, user.PasswordHash, proof.Password)
                != PasswordVerificationResult.Failed;
        }

        // Google-only account. The token is verified against Google and then
        // matched on the subject, never on the email: an email can be changed
        // or reassigned, and matching on it would let one Workspace user
        // confirm another's account by inheriting their address.
        if (string.IsNullOrEmpty(proof.GoogleIdToken)) return false;

        var principal = await google.VerifyAsync(proof.GoogleIdToken, ct);
        return principal is not null && principal.Subject == user.GoogleSubject;
    }
}
