using ICanRead.Application.Auth;
using ICanRead.Domain.Entities;
using ICanRead.Infrastructure.Persistence;
using Microsoft.AspNetCore.Identity;
using Microsoft.EntityFrameworkCore;

namespace ICanRead.Infrastructure.Auth;

/// <summary>
/// What a signed-in reader can do to their own account.
/// </summary>
/// <remarks>
/// Every method here takes the account id from the caller's token and never
/// from the request body — the one rule that keeps a reader out of somebody
/// else's account. The controller is what enforces it; this type only ever
/// sees an id that has already come from a validated token.
/// </remarks>
public class AccountService(
    AppDbContext db,
    TokenService tokens,
    AccountConfirmation confirmation,
    AccountCodeService codes,
    IPasswordHasher<User> passwordHasher,
    IGoogleTokenVerifier google,
    TimeProvider clock)
{
    public Task<User?> FindAsync(Guid userId, CancellationToken ct) =>
        db.Users.FirstOrDefaultAsync(u => u.Id == userId, ct);

    /// <summary>Changes what the reader is called.</summary>
    public async Task<UserResponse?> UpdateProfileAsync(
        Guid userId,
        UpdateProfileRequest request,
        CancellationToken ct)
    {
        var user = await FindAsync(userId, ct);
        if (user is null) return null;

        var name = request.DisplayName?.Trim();
        // An empty box means "I would rather not be called anything", which is
        // the same state a reader who never filled it in is already allowed to
        // be in. Storing "" instead would make that a different, emptier thing.
        user.DisplayName = string.IsNullOrEmpty(name) ? null : name;
        user.UpdatedAt = clock.GetUtcNow();

        await db.SaveChangesAsync(ct);
        return user.ToResponse();
    }

    /// <summary>
    /// Sets a new password, and hands back a session to keep reading with.
    /// </summary>
    /// <remarks>
    /// Every existing session goes, including the caller's own. A password is
    /// changed either because the reader wants a better one or because they
    /// think somebody else has the old one, and in the second case leaving that
    /// somebody's session alive would make the change cosmetic. Since the
    /// caller's own session is among the casualties, a fresh pair comes back in
    /// the same response — the phone in the reader's hand carries on, and every
    /// other device is signed out.
    /// </remarks>
    public async Task<AccountChangeResult> ChangePasswordAsync(
        Guid userId,
        ChangePasswordRequest request,
        SessionOrigin origin,
        CancellationToken ct)
    {
        var user = await FindAsync(userId, ct);
        if (user is null) return AccountChangeResult.Fail(AccountChangeOutcome.NotFound);

        if (!await confirmation.ConfirmsAsync(user, request.Proof, ct))
        {
            return AccountChangeResult.Fail(AccountChangeOutcome.NotConfirmed);
        }

        var now = clock.GetUtcNow();
        user.PasswordHash = passwordHasher.HashPassword(user, request.NewPassword);
        user.UpdatedAt = now;

        await db.RefreshTokens
            .Where(t => t.UserId == userId && t.RevokedAt == null)
            .ExecuteUpdateAsync(t => t.SetProperty(x => x.RevokedAt, now), ct);

        await db.SaveChangesAsync(ct);

        return AccountChangeResult.Ok(await IssueAsync(user, origin, ct));
    }

    /// <summary>Sends a fresh code to prove the address on the account.</summary>
    public async Task<AccountChangeOutcome> SendEmailCodeAsync(
        Guid userId,
        CancellationToken ct)
    {
        var user = await FindAsync(userId, ct);
        if (user is null) return AccountChangeOutcome.NotFound;

        // Nothing to prove twice. Silently doing nothing beats emailing a code
        // that the verify endpoint would then refuse to need.
        if (user.IsEmailVerified) return AccountChangeOutcome.Done;

        await codes.SendVerificationAsync(user, ct);
        return AccountChangeOutcome.Done;
    }

    /// <summary>Spends a verification code.</summary>
    public async Task<CodeOutcome> VerifyEmailAsync(
        Guid userId,
        string code,
        CancellationToken ct)
    {
        var user = await FindAsync(userId, ct);
        if (user is null) return CodeOutcome.Invalid;

        return await codes.VerifyEmailAsync(user, code, ct);
    }

    /// <summary>
    /// Adds Google as a second way into an account that already exists.
    /// </summary>
    /// <remarks>
    /// Two conditions, and both are about the same danger. The account's own
    /// address must be verified, because otherwise somebody who registered with
    /// an address they do not own could attach the real owner's Google account
    /// to it. And the Google account's address must be the same one, because a
    /// reader linking a *different* Google address would create a second,
    /// invisible key to an account whose stated owner is someone else.
    /// </remarks>
    public async Task<AccountChangeOutcome> LinkGoogleAsync(
        Guid userId,
        string idToken,
        CancellationToken ct)
    {
        var user = await FindAsync(userId, ct);
        if (user is null) return AccountChangeOutcome.NotFound;

        var principal = await google.VerifyAsync(idToken, ct);
        if (principal is null) return AccountChangeOutcome.InvalidGoogleToken;

        if (user.GoogleSubject == principal.Subject) return AccountChangeOutcome.Done;

        if (!user.IsEmailVerified) return AccountChangeOutcome.EmailNotVerified;

        if (!string.Equals(
                Normalise(principal.Email), user.Email, StringComparison.Ordinal))
        {
            return AccountChangeOutcome.GoogleEmailMismatch;
        }

        // Checked rather than left to the unique index: a race here would
        // surface as a 500 on a save, and the reader deserves to be told that
        // the Google account is already spoken for.
        var taken = await db.Users.AnyAsync(
            u => u.GoogleSubject == principal.Subject && u.Id != userId, ct);
        if (taken) return AccountChangeOutcome.GoogleAlreadyInUse;

        user.GoogleSubject = principal.Subject;
        user.UpdatedAt = clock.GetUtcNow();
        await db.SaveChangesAsync(ct);

        return AccountChangeOutcome.Done;
    }

    /// <summary>
    /// Takes Google back off an account, provided it is not the only way in.
    /// </summary>
    public async Task<AccountChangeOutcome> UnlinkGoogleAsync(
        Guid userId,
        AccountProof proof,
        CancellationToken ct)
    {
        var user = await FindAsync(userId, ct);
        if (user is null) return AccountChangeOutcome.NotFound;

        if (user.GoogleSubject is null) return AccountChangeOutcome.Done;

        // The check that matters. An account with no password and no Google
        // link cannot be signed into by anybody, ever — not even by password
        // reset, since the reader would have no session to set one from. The
        // reader is told to set a password first rather than being allowed to
        // shut the last door behind them.
        if (user.PasswordHash is null) return AccountChangeOutcome.WouldLockOut;

        if (!await confirmation.ConfirmsAsync(user, proof, ct))
        {
            return AccountChangeOutcome.NotConfirmed;
        }

        user.GoogleSubject = null;
        user.UpdatedAt = clock.GetUtcNow();
        await db.SaveChangesAsync(ct);

        return AccountChangeOutcome.Done;
    }

    /// <summary>The reader's live sessions, newest first.</summary>
    public async Task<IReadOnlyList<SessionResponse>> ListSessionsAsync(
        Guid userId,
        Guid? currentSessionId,
        CancellationToken ct)
    {
        var now = clock.GetUtcNow();

        return await db.RefreshTokens
            .Where(t => t.UserId == userId && t.RevokedAt == null && t.ExpiresAt > now)
            .OrderByDescending(t => t.CreatedAt)
            .Select(t => new SessionResponse(
                t.Id,
                t.CreatedAt,
                t.ExpiresAt,
                t.CreatedFromIp,
                t.UserAgent,
                t.Id == currentSessionId))
            .ToListAsync(ct);
    }

    /// <summary>
    /// Signs one device out.
    /// </summary>
    /// <remarks>
    /// Scoped to the caller's own account in the same query that finds the row,
    /// so a session id belonging to somebody else is indistinguishable from one
    /// that does not exist.
    /// </remarks>
    public async Task<bool> RevokeSessionAsync(
        Guid userId,
        Guid sessionId,
        CancellationToken ct)
    {
        var revoked = await db.RefreshTokens
            .Where(t => t.Id == sessionId && t.UserId == userId && t.RevokedAt == null)
            .ExecuteUpdateAsync(
                t => t.SetProperty(x => x.RevokedAt, clock.GetUtcNow()), ct);

        return revoked > 0;
    }

    /// <summary>
    /// Signs out everywhere except here.
    /// </summary>
    /// <remarks>
    /// "Except here" needs a session id, and a token minted before that claim
    /// existed has none. Rather than quietly signing the caller out of the
    /// phone they are holding, a null id means nothing is spared — which is
    /// wrong in a way the reader can recover from in one tap, unlike the
    /// alternative of revoking everything *but* misidentifying which one to
    /// keep.
    /// </remarks>
    public async Task<int> RevokeOtherSessionsAsync(
        Guid userId,
        Guid? currentSessionId,
        CancellationToken ct)
    {
        return await db.RefreshTokens
            .Where(t => t.UserId == userId
                        && t.RevokedAt == null
                        && t.Id != currentSessionId)
            .ExecuteUpdateAsync(
                t => t.SetProperty(x => x.RevokedAt, clock.GetUtcNow()), ct);
    }

    /// <summary>
    /// Opens a fresh session. The same shape <c>AuthService</c> issues, because
    /// the client cannot tell — and must not have to tell — where its tokens
    /// came from.
    /// </summary>
    private async Task<AuthResponse> IssueAsync(
        User user,
        SessionOrigin origin,
        CancellationToken ct)
    {
        var now = clock.GetUtcNow();
        var refresh = TokenService.CreateRefreshToken();

        var row = new RefreshToken
        {
            Id = Guid.NewGuid(),
            UserId = user.Id,
            TokenHash = TokenService.HashRefreshToken(refresh),
            CreatedAt = now,
            ExpiresAt = tokens.RefreshTokenExpiry,
            CreatedFromIp = origin.IpAddress,
            UserAgent = origin.UserAgent
        };

        db.RefreshTokens.Add(row);
        await db.SaveChangesAsync(ct);

        return new AuthResponse(
            tokens.CreateAccessToken(user, row.Id),
            refresh,
            tokens.AccessTokenExpiry,
            user.ToResponse());
    }

    private static string Normalise(string email) => email.Trim().ToLowerInvariant();
}
