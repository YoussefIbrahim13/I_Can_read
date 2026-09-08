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
    IPasswordHasher<User> passwordHasher,
    TimeProvider clock)
{
    public async Task<AuthResult> RegisterAsync(RegisterRequest request, CancellationToken ct)
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

        return AuthResult.Ok(await IssueAsync(user, ct));
    }

    public async Task<AuthResult> LoginAsync(LoginRequest request, CancellationToken ct)
    {
        var email = Normalise(request.Email);
        var user = await db.Users.FirstOrDefaultAsync(u => u.Email == email, ct);

        // Verified even when there is no such user, against a throwaway hash.
        // Returning early here would make a missing account measurably faster
        // to probe than a wrong password, which is the enumeration the single
        // InvalidCredentials result exists to prevent.
        var storedHash = user?.PasswordHash ?? DummyHash.Value;
        var outcome = passwordHasher.VerifyHashedPassword(
            user ?? DummyHash.User, storedHash, request.Password);

        if (user is null || user.PasswordHash is null || outcome == PasswordVerificationResult.Failed)
        {
            return AuthResult.Fail(AuthError.InvalidCredentials);
        }

        if (outcome == PasswordVerificationResult.SuccessRehashNeeded)
        {
            // The hasher's parameters have moved on since this password was
            // set. Upgrading on a successful sign-in is the only moment the
            // plaintext is available to do it.
            user.PasswordHash = passwordHasher.HashPassword(user, request.Password);
            user.UpdatedAt = clock.GetUtcNow();
        }

        return AuthResult.Ok(await IssueAsync(user, ct));
    }

    /// <summary>
    /// Exchanges a refresh token for a new pair, revoking the one presented.
    /// </summary>
    public async Task<AuthResult> RefreshAsync(string refreshToken, CancellationToken ct)
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
            // A revoked token coming back means it was captured, or a client
            // retried with a token it had already spent. Either way the chain
            // is no longer trustworthy, so every live token for this user goes.
            if (stored.RevokedAt is not null)
            {
                await RevokeAllAsync(stored.UserId, now, ct);
            }
            return AuthResult.Fail(AuthError.InvalidRefreshToken);
        }

        var issued = await IssueAsync(stored.User, ct, replacing: stored);
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
    /// A Google email that already belongs to a **password** account is
    /// refused rather than joined to it. Linking on a verified email is the
    /// usual thing to do, and it would be safe here except for one gap: this
    /// server does not verify email addresses at registration. So somebody can
    /// register with an address they do not own, wait for its real owner to
    /// arrive through Google, and — if the two were linked — find themselves
    /// holding a password to that reader's account. Refusing costs a reader
    /// with both an inconvenient message; linking costs the wrong reader their
    /// library. This becomes safe to relax the day registration verifies an
    /// address, and not before.
    /// </para>
    /// </remarks>
    public async Task<AuthResult> GoogleSignInAsync(
        GooglePrincipal principal,
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
                // Already a Google account under a *different* subject, or a
                // password account. Either way it is not this caller's.
                return AuthResult.Fail(AuthError.EmailBelongsToPasswordAccount);
            }

            user = new User
            {
                Id = Guid.NewGuid(),
                Email = email,
                GoogleSubject = principal.Subject,
                DisplayName = principal.Name,
                // No PasswordHash. The account can only be entered through
                // Google until the reader sets one.
                CreatedAt = now,
                UpdatedAt = now
            };
            db.Users.Add(user);
            await db.SaveChangesAsync(ct);
        }

        return AuthResult.Ok(await IssueAsync(user, ct));
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

    private async Task<AuthResponse> IssueAsync(
        User user,
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
            ExpiresAt = tokens.RefreshTokenExpiry
        };
        db.RefreshTokens.Add(row);

        if (replacing is not null)
        {
            replacing.RevokedAt = now;
            replacing.ReplacedByTokenId = row.Id;
        }

        await db.SaveChangesAsync(ct);

        return new AuthResponse(
            tokens.CreateAccessToken(user),
            refresh,
            tokens.AccessTokenExpiry,
            new UserResponse(user.Id, user.Email, user.DisplayName));
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
