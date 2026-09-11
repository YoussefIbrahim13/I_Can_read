using ICanRead.Application.Auth;
using ICanRead.Domain.Entities;
using ICanRead.Infrastructure.Persistence;
using Microsoft.AspNetCore.Identity;
using Microsoft.EntityFrameworkCore;

namespace ICanRead.Infrastructure.Auth;

/// <summary>
/// Registration, sign-in, and refresh-token rotation.
/// </summary>
public class AuthService(
    AppDbContext db,
    TokenService tokens,
    AccountCodeService codes,
    IPasswordHasher<User> passwordHasher,
    TimeProvider clock)
{
    public async Task<AuthResult> RegisterAsync(
        RegisterRequest request,
        SessionOrigin origin,
        CancellationToken ct)
    {
        var email = Normalise(request.Email);

        if (await db.Users.AnyAsync(u => u.Email == email, ct))
        {
            return AuthResult.Fail(AuthError.EmailAlreadyRegistered);
        }

        var now = clock.GetUtcNow();
        var user = new User
        {
            Id = Guid.NewGuid(),
            Email = email,
            DisplayName = request.DisplayName,
            CreatedAt = now,
            UpdatedAt = now
        };
        user.PasswordHash = passwordHasher.HashPassword(user, request.Password);

        db.Users.Add(user);
        await db.SaveChangesAsync(ct);

        // Signed in first, and asked to prove the address afterwards. Holding
        // the library hostage until somebody finds an email is how a reader
        // gives up on a reading app; what the unproved address costs them is
        // only the ability to link Google to this account, which is a thing
        // they have not asked for yet.
        await codes.SendVerificationAsync(user, ct);

        return AuthResult.Ok(await IssueAsync(user, origin, ct));
    }

    public async Task<AuthResult> LoginAsync(
        LoginRequest request,
        SessionOrigin origin,
        CancellationToken ct)
    {
        var email = Normalise(request.Email);
        var now = clock.GetUtcNow();
        var user = await db.Users.FirstOrDefaultAsync(u => u.Email == email, ct);

        // Checked before the password, and answered differently from a wrong
        // one. It does tell a caller that this address has an account — but
        // only after ten wrong guesses at it, by which point the address-level
        // rate limit has already been the thing slowing them down. The reason
        // to say it plainly is the reader: told "wrong password" while holding
        // the right one, they go and change a password that was never the
        // problem.
        if (user is not null && user.IsLockedAt(now))
        {
            return AuthResult.Locked(user.LockedUntil!.Value - now);
        }

        // Verified even when there is no such user, against a throwaway hash.
        // Returning early here would make a missing account measurably faster
        // to probe than a wrong password, which is the enumeration the single
        // InvalidCredentials result exists to prevent.
        var storedHash = user?.PasswordHash ?? DummyHash.Value;
        var outcome = passwordHasher.VerifyHashedPassword(
            user ?? DummyHash.User, storedHash, request.Password);

        if (user is null || user.PasswordHash is null || outcome == PasswordVerificationResult.Failed)
        {
            if (user is not null)
            {
                await RecordFailureAsync(user, now, ct);
            }
            return AuthResult.Fail(AuthError.InvalidCredentials);
        }

        if (outcome == PasswordVerificationResult.SuccessRehashNeeded)
        {
            // The hasher's parameters have moved on since this password was
            // set. Upgrading on a successful sign-in is the only moment the
            // plaintext is available to do it.
            user.PasswordHash = passwordHasher.HashPassword(user, request.Password);
            user.UpdatedAt = now;
        }

        // The count is about consecutive failures, so the one success that
        // proves the reader is who they say they are wipes it.
        user.FailedSignInCount = 0;
        user.LockedUntil = null;

        return AuthResult.Ok(await IssueAsync(user, origin, ct));
    }

    /// <summary>
    /// Exchanges a refresh token for a new pair, revoking the one presented.
    /// </summary>
    public async Task<AuthResult> RefreshAsync(
        string refreshToken,
        SessionOrigin origin,
        CancellationToken ct)
    {
        var hash = TokenService.HashRefreshToken(refreshToken);
        var stored = await db.RefreshTokens
            .Include(t => t.User)
            .FirstOrDefaultAsync(t => t.TokenHash == hash, ct);

        var now = clock.GetUtcNow();

        if (stored is null || stored.User is null)
        {
            return AuthResult.Fail(AuthError.InvalidRefreshToken);
        }

        if (!stored.IsActive(now))
        {
            // A token that was *rotated* and has come back means it was
            // captured, or a client retried with one it had already spent.
            // Either way the chain is no longer trustworthy, so every live
            // token for this user goes.
            //
            // `ReplacedByTokenId` is what tells that apart from a token that
            // was revoked on purpose — by signing out, by signing this device
            // out from another one, or by a password change. Those all leave a
            // device holding a dead token that it will present exactly once
            // more, on its next launch, entirely innocently. Treating that as
            // an attack would mean "sign out my old phone" quietly signed out
            // every phone the moment the old one was picked up.
            if (stored.ReplacedByTokenId is not null)
            {
                await RevokeAllAsync(stored.UserId, now, ct);
            }
            return AuthResult.Fail(AuthError.InvalidRefreshToken);
        }

        var issued = await IssueAsync(stored.User, origin, ct, replacing: stored);
        return AuthResult.Ok(issued);
    }

    /// <summary>
    /// Signs in with a Google ID token, creating the account if it is new.
    /// </summary>
    /// <remarks>
    /// <para>
    /// The account is found by Google's <c>sub</c> claim, never by email. The
    /// subject is stable for the life of the account; an email can be changed,
    /// and on Workspace domains it can be reassigned to a different person.
    /// </para>
    /// <para>
    /// When the subject is new but the email already has a password account
    /// here, the two are joined up **only if that account has proved it owns
    /// the address**. The danger otherwise is specific: registration hands out
    /// a session without checking the address, so somebody can register with an
    /// address they do not own, wait for its real owner to arrive through
    /// Google, and — if the two were linked — find themselves holding a
    /// password to that reader's account. A verified address closes exactly
    /// that hole, because the squatter could never have proved it.
    /// </para>
    /// </remarks>
    public async Task<AuthResult> GoogleSignInAsync(
        GooglePrincipal principal,
        SessionOrigin origin,
        CancellationToken ct)
    {
        var email = Normalise(principal.Email);
        var now = clock.GetUtcNow();

        var user = await db.Users
            .FirstOrDefaultAsync(u => u.GoogleSubject == principal.Subject, ct);

        if (user is null)
        {
            var byEmail = await db.Users.FirstOrDefaultAsync(u => u.Email == email, ct);

            if (byEmail is not null)
            {
                // Already a Google account under a *different* subject. Two
                // Google accounts claiming one address is not something to
                // guess at, so neither is taken to be the other.
                if (byEmail.GoogleSubject is not null)
                {
                    return AuthResult.Fail(AuthError.EmailBelongsToPasswordAccount);
                }

                if (!byEmail.IsEmailVerified)
                {
                    return AuthResult.Fail(AuthError.EmailBelongsToPasswordAccount);
                }

                byEmail.GoogleSubject = principal.Subject;
                byEmail.UpdatedAt = now;
                await db.SaveChangesAsync(ct);

                return AuthResult.Ok(await IssueAsync(byEmail, origin, ct));
            }

            user = new User
            {
                Id = Guid.NewGuid(),
                Email = email,
                GoogleSubject = principal.Subject,
                DisplayName = principal.Name,
                // Google has already checked the address it is vouching for,
                // which is the same proof our own code asks for — so an account
                // that arrives this way starts out verified.
                EmailVerifiedAt = now,
                // No PasswordHash. The account can only be entered through
                // Google until the reader sets one.
                CreatedAt = now,
                UpdatedAt = now
            };
            db.Users.Add(user);
            await db.SaveChangesAsync(ct);
        }

        return AuthResult.Ok(await IssueAsync(user, origin, ct));
    }

    /// <summary>Signs one session out. Unknown tokens are not an error.</summary>
    public async Task LogoutAsync(string refreshToken, CancellationToken ct)
    {
        var hash = TokenService.HashRefreshToken(refreshToken);
        var stored = await db.RefreshTokens.FirstOrDefaultAsync(t => t.TokenHash == hash, ct);
        if (stored is null || stored.RevokedAt is not null) return;

        stored.RevokedAt = clock.GetUtcNow();
        await db.SaveChangesAsync(ct);
    }

    /// <summary>
    /// Counts a wrong password, and starts making the account wait once there
    /// have been too many.
    /// </summary>
    /// <remarks>
    /// The wait doubles with each further failure and stops at
    /// <see cref="User.MaxLockout"/>. Doubling is what makes a slow distributed
    /// guess expensive; the ceiling is what stops the account's own holder
    /// being locked out for a day because somebody else was guessing at it.
    /// </remarks>
    private async Task RecordFailureAsync(User user, DateTimeOffset now, CancellationToken ct)
    {
        user.FailedSignInCount++;

        if (user.FailedSignInCount >= User.SignInFailuresBeforeLockout)
        {
            var beyond = user.FailedSignInCount - User.SignInFailuresBeforeLockout;
            var minutes = Math.Min(Math.Pow(2, beyond), User.MaxLockout.TotalMinutes);
            user.LockedUntil = now + TimeSpan.FromMinutes(minutes);
        }

        await db.SaveChangesAsync(ct);
    }

    private async Task<AuthResponse> IssueAsync(
        User user,
        SessionOrigin origin,
        CancellationToken ct,
        RefreshToken? replacing = null)
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
            // On a rotation the session is the same session — it has merely
            // renewed — so it keeps the address and device it was opened from
            // rather than taking on whichever network it refreshed over.
            CreatedFromIp = replacing?.CreatedFromIp ?? origin.IpAddress,
            UserAgent = replacing?.UserAgent ?? origin.UserAgent
        };
        db.RefreshTokens.Add(row);

        if (replacing is not null)
        {
            replacing.RevokedAt = now;
            replacing.ReplacedByTokenId = row.Id;
        }

        await db.SaveChangesAsync(ct);

        return new AuthResponse(
            tokens.CreateAccessToken(user, row.Id),
            refresh,
            tokens.AccessTokenExpiry,
            user.ToResponse());
    }

    private async Task RevokeAllAsync(Guid userId, DateTimeOffset now, CancellationToken ct)
    {
        await db.RefreshTokens
            .Where(t => t.UserId == userId && t.RevokedAt == null)
            .ExecuteUpdateAsync(t => t.SetProperty(x => x.RevokedAt, now), ct);
    }

    /// <summary>Lower-cased and trimmed, matching how the unique index stores it.</summary>
    private static string Normalise(string email) => email.Trim().ToLowerInvariant();
}

/// <summary>
/// A real hash of a fixed password, used to spend the same work verifying a
/// login for an address that has no account.
/// </summary>
file static class DummyHash
{
    public static readonly User User = new() { Email = "" };

    public static readonly string Value =
        new PasswordHasher<User>().HashPassword(User, "not-a-real-password");
}
