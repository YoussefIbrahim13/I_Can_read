using System.Security.Claims;
using ICanRead.Application.Auth;
using ICanRead.Infrastructure.Auth;
using ICanRead.Infrastructure.Persistence;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.RateLimiting;
using Microsoft.EntityFrameworkCore;

namespace ICanRead.Api.Controllers;

[ApiController]
[Route("api/auth")]
// Every way into an account, under one limit: sign-in, registration, the reset
// code, and the token exchange. Guessing is the thing being slowed down, and it
// does not matter which of these doors it knocks on.
[EnableRateLimiting(AuthRateLimit.Policy)]
public class AuthController(
    AuthService auth,
    PasswordResetService passwordReset,
    IGoogleTokenVerifier google) : ControllerBase
{
    [HttpPost("google")]
    public async Task<IActionResult> Google(GoogleSignInRequest request, CancellationToken ct)
    {
        var principal = await google.VerifyAsync(request.IdToken, ct);
        if (principal is null)
        {
            return Respond(AuthResult.Fail(AuthError.InvalidGoogleToken));
        }

        return Respond(await auth.GoogleSignInAsync(principal, ct));
    }

    [HttpPost("register")]
    public async Task<IActionResult> Register(RegisterRequest request, CancellationToken ct) =>
        Respond(await auth.RegisterAsync(request, ct));

    [HttpPost("login")]
    public async Task<IActionResult> Login(LoginRequest request, CancellationToken ct) =>
        Respond(await auth.LoginAsync(request, ct));

    [HttpPost("refresh")]
    public async Task<IActionResult> Refresh(RefreshRequest request, CancellationToken ct) =>
        Respond(await auth.RefreshAsync(request.RefreshToken, ct));

    [HttpPost("logout")]
    public async Task<IActionResult> Logout(RefreshRequest request, CancellationToken ct)
    {
        await auth.LogoutAsync(request.RefreshToken, ct);
        // No content either way. Whether that token existed is not something an
        // unauthenticated caller gets to find out.
        return NoContent();
    }

    [HttpPost("forgot-password")]
    public async Task<IActionResult> ForgotPassword(
        ForgotPasswordRequest request,
        CancellationToken ct)
    {
        await passwordReset.RequestAsync(request.Email, ct);
        // Always the same answer. Whether that address has an account here is
        // not something an unauthenticated caller gets to find out.
        return NoContent();
    }

    [HttpPost("reset-password")]
    public async Task<IActionResult> ResetPassword(
        ResetPasswordRequest request,
        CancellationToken ct)
    {
        var outcome = await passwordReset.ResetAsync(
            request.Email, request.Code, request.NewPassword, ct);

        return outcome == PasswordResetOutcome.Reset
            ? NoContent()
            // Deliberately not signed in on the way out: the reader has a
            // password now and the ordinary sign-in path can use it, and this
            // way a reset never hands out a session as a side effect.
            : BadRequest(new ProblemDetails
            {
                Title = "That code is not valid. Ask for a new one."
            });
    }

    private IActionResult Respond(AuthResult result) => result switch
    {
        { Succeeded: true } => Ok(result.Response),
        { Error: AuthError.EmailAlreadyRegistered } =>
            Conflict(new ProblemDetails { Title = "That email is already registered." }),
        // Also a 409, and deliberately the same status as the above: from the
        // client's point of view both mean "this address is spoken for, use the
        // way in that already exists".
        { Error: AuthError.EmailBelongsToPasswordAccount } =>
            Conflict(new ProblemDetails
            {
                Title = "That email already has an account. Sign in with your password."
            }),
        _ => Unauthorized(new ProblemDetails { Title = "Those details did not match." })
    };
}

[ApiController]
[Route("api/me")]
[Authorize]
public class MeController(AppDbContext db, AccountDeletionService deletion)
    : ControllerBase
{
    /// <summary>
    /// Closes the caller's account and deletes everything it holds.
    /// </summary>
    /// <remarks>
    /// A POST rather than <c>DELETE /api/me</c>: the confirmation travels in the
    /// body, and a request body on DELETE is something proxies and HTTP clients
    /// are entitled to drop.
    /// </remarks>
    [HttpPost("delete")]
    // Under the auth limit too. It takes a password, so it is a place guessing
    // could pay, and it is the one call in the app that cannot be undone.
    [EnableRateLimiting(AuthRateLimit.Policy)]
    public async Task<IActionResult> Delete(
        DeleteAccountRequest request,
        CancellationToken ct)
    {
        if (!TryGetUserId(out var userId)) return Unauthorized();

        var outcome = await deletion.DeleteAsync(userId, request, ct);

        return outcome switch
        {
            AccountDeletionOutcome.Deleted => NoContent(),
            // Already gone, which is the state the caller was asking for. The
            // token outliving the account is not the reader's problem.
            AccountDeletionOutcome.NotFound => NoContent(),
            _ => Unauthorized(new ProblemDetails
            {
                Title = "That did not confirm the account is yours."
            })
        };
    }

    [HttpGet]
    public async Task<IActionResult> Get(CancellationToken ct)
    {
        if (!TryGetUserId(out var userId)) return Unauthorized();

        var user = await db.Users
            .Where(u => u.Id == userId)
            .Select(u => new UserResponse(u.Id, u.Email, u.DisplayName))
            .FirstOrDefaultAsync(ct);

        return user is null ? Unauthorized() : Ok(user);
    }

    /// <summary>
    /// The account id, taken from the token and never from the request — the
    /// one rule that keeps a caller out of somebody else's account.
    /// </summary>
    private bool TryGetUserId(out Guid userId) =>
        Guid.TryParse(User.FindFirstValue(ClaimTypes.NameIdentifier), out userId);
}
