using System.Globalization;
using System.Security.Claims;
using ICanRead.Application.Auth;
using ICanRead.Infrastructure.Auth;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.RateLimiting;

namespace ICanRead.Api.Controllers;

[ApiController]
[Route("api/auth")]
// Every way into an account, under one limit: sign-in, registration, the reset
// code, and the token exchange. Guessing is the thing being slowed down, and it
// does not matter which of these doors it knocks on.
[EnableRateLimiting(AuthRateLimit.Policy)]
public class AuthController(
    AuthService auth,
    AccountCodeService codes,
    IGoogleTokenVerifier google) : ControllerBase
{
    [HttpPost("google")]
    public async Task<IActionResult> Google(GoogleTokenRequest request, CancellationToken ct)
    {
        var principal = await google.VerifyAsync(request.IdToken, ct);
        if (principal is null)
        {
            return this.Respond(AuthResult.Fail(AuthError.InvalidGoogleToken));
        }

        return this.Respond(await auth.GoogleSignInAsync(principal, HttpContext.Origin(), ct));
    }

    [HttpPost("register")]
    public async Task<IActionResult> Register(RegisterRequest request, CancellationToken ct) =>
        this.Respond(await auth.RegisterAsync(request, HttpContext.Origin(), ct));

    [HttpPost("login")]
    public async Task<IActionResult> Login(LoginRequest request, CancellationToken ct) =>
        this.Respond(await auth.LoginAsync(request, HttpContext.Origin(), ct));

    [HttpPost("refresh")]
    public async Task<IActionResult> Refresh(RefreshRequest request, CancellationToken ct) =>
        this.Respond(await auth.RefreshAsync(request.RefreshToken, HttpContext.Origin(), ct));

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
        await codes.RequestResetAsync(request.Email, ct);
        // Always the same answer. Whether that address has an account here is
        // not something an unauthenticated caller gets to find out.
        return NoContent();
    }

    [HttpPost("reset-password")]
    public async Task<IActionResult> ResetPassword(
        ResetPasswordRequest request,
        CancellationToken ct)
    {
        var outcome = await codes.ResetAsync(
            request.Email, request.Code, request.NewPassword, ct);

        return outcome == CodeOutcome.Accepted
            ? NoContent()
            // Deliberately not signed in on the way out: the reader has a
            // password now and the ordinary sign-in path can use it, and this
            // way a reset never hands out a session as a side effect.
            : BadRequest(new ProblemDetails
            {
                Title = "That code is not valid. Ask for a new one."
            });
    }
}

[ApiController]
[Route("api/me")]
[Authorize]
public class MeController(
    AccountService account,
    AccountDeletionService deletion) : ControllerBase
{
    [HttpGet]
    public async Task<IActionResult> Get(CancellationToken ct)
    {
        if (!TryGetUserId(out var userId)) return Unauthorized();

        var user = await account.FindAsync(userId, ct);
        return user is null ? Unauthorized() : Ok(user.ToResponse());
    }

    [HttpPatch]
    public async Task<IActionResult> Update(
        UpdateProfileRequest request,
        CancellationToken ct)
    {
        if (!TryGetUserId(out var userId)) return Unauthorized();

        var user = await account.UpdateProfileAsync(userId, request, ct);
        return user is null ? Unauthorized() : Ok(user);
    }

    /// <summary>
    /// Sets a new password and returns a session to carry on with.
    /// </summary>
    /// <remarks>
    /// The response is a full <see cref="AuthResponse"/> rather than a 204,
    /// because the change signs out every session including this one. See
    /// <c>AccountService.ChangePasswordAsync</c>.
    /// </remarks>
    [HttpPost("password")]
    // Takes a password to prove the account is the caller's, so it is a place
    // guessing could pay.
    [EnableRateLimiting(AuthRateLimit.Policy)]
    public async Task<IActionResult> ChangePassword(
        ChangePasswordRequest request,
        CancellationToken ct)
    {
        if (!TryGetUserId(out var userId)) return Unauthorized();

        var result = await account.ChangePasswordAsync(
            userId, request, HttpContext.Origin(), ct);

        return result.Succeeded ? Ok(result.Session) : Problem(result.Outcome);
    }

    [HttpPost("email/send-code")]
    [EnableRateLimiting(AuthRateLimit.Policy)]
    public async Task<IActionResult> SendEmailCode(CancellationToken ct)
    {
        if (!TryGetUserId(out var userId)) return Unauthorized();

        var outcome = await account.SendEmailCodeAsync(userId, ct);
        return outcome == AccountChangeOutcome.Done ? NoContent() : Problem(outcome);
    }

    [HttpPost("email/verify")]
    // Six digits is a million guesses, and the code's own attempt counter only
    // protects the code that was issued — not a script asking for a new one
    // after every fifth try.
    [EnableRateLimiting(AuthRateLimit.Policy)]
    public async Task<IActionResult> VerifyEmail(
        VerifyEmailRequest request,
        CancellationToken ct)
    {
        if (!TryGetUserId(out var userId)) return Unauthorized();

        var outcome = await account.VerifyEmailAsync(userId, request.Code, ct);

        return outcome == CodeOutcome.Accepted
            ? NoContent()
            : BadRequest(new ProblemDetails
            {
                Title = "That code is not valid. Ask for a new one."
            });
    }

    [HttpPost("google/link")]
    [EnableRateLimiting(AuthRateLimit.Policy)]
    public async Task<IActionResult> LinkGoogle(
        GoogleTokenRequest request,
        CancellationToken ct)
    {
        if (!TryGetUserId(out var userId)) return Unauthorized();

        var outcome = await account.LinkGoogleAsync(userId, request.IdToken, ct);
        return outcome == AccountChangeOutcome.Done ? NoContent() : Problem(outcome);
    }

    [HttpPost("google/unlink")]
    [EnableRateLimiting(AuthRateLimit.Policy)]
    public async Task<IActionResult> UnlinkGoogle(
        DeleteAccountRequest request,
        CancellationToken ct)
    {
        if (!TryGetUserId(out var userId)) return Unauthorized();

        var outcome = await account.UnlinkGoogleAsync(userId, request.Proof, ct);
        return outcome == AccountChangeOutcome.Done ? NoContent() : Problem(outcome);
    }

    [HttpGet("sessions")]
    public async Task<IActionResult> Sessions(CancellationToken ct)
    {
        if (!TryGetUserId(out var userId)) return Unauthorized();

        return Ok(await account.ListSessionsAsync(userId, CurrentSessionId, ct));
    }

    [HttpDelete("sessions/{id:guid}")]
    public async Task<IActionResult> RevokeSession(Guid id, CancellationToken ct)
    {
        if (!TryGetUserId(out var userId)) return Unauthorized();

        // A 404 covers both "no such session" and "not yours". Which of the two
        // it was is not something a caller gets to learn by asking.
        return await account.RevokeSessionAsync(userId, id, ct)
            ? NoContent()
            : NotFound();
    }

    [HttpPost("sessions/revoke-others")]
    public async Task<IActionResult> RevokeOtherSessions(CancellationToken ct)
    {
        if (!TryGetUserId(out var userId)) return Unauthorized();

        await account.RevokeOtherSessionsAsync(userId, CurrentSessionId, ct);
        return NoContent();
    }

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

    /// <summary>
    /// The account id, taken from the token and never from the request — the
    /// one rule that keeps a caller out of somebody else's account.
    /// </summary>
    private bool TryGetUserId(out Guid userId) =>
        Guid.TryParse(User.FindFirstValue(ClaimTypes.NameIdentifier), out userId);

    /// <summary>The session this request arrived on, when its token names one.</summary>
    private Guid? CurrentSessionId => TokenService.SessionIdFrom(User);

    /// <summary>
    /// Turns a refusal into a response the client can act on.
    /// </summary>
    /// <remarks>
    /// Four of these are 409s, and a client cannot tell four apart by status
    /// alone — "confirm your address first" and "that Google account belongs to
    /// somebody else" ask the reader to do completely different things. So each
    /// carries a <c>code</c> alongside the title. The title is English and is
    /// for a developer reading a log; the code is what the app switches on to
    /// say the right thing in the reader's own language.
    /// </remarks>
    private IActionResult Problem(AccountChangeOutcome outcome)
    {
        var (status, code, title) = outcome switch
        {
            AccountChangeOutcome.NotFound => (
                StatusCodes.Status401Unauthorized,
                "notFound",
                "That account no longer exists."),
            AccountChangeOutcome.NotConfirmed => (
                StatusCodes.Status401Unauthorized,
                "notConfirmed",
                "That did not confirm the account is yours."),
            AccountChangeOutcome.InvalidGoogleToken => (
                StatusCodes.Status401Unauthorized,
                "invalidGoogleToken",
                "Google would not confirm that sign-in. Try again."),
            AccountChangeOutcome.EmailNotVerified => (
                StatusCodes.Status409Conflict,
                "emailNotVerified",
                "Confirm your email address first."),
            AccountChangeOutcome.GoogleEmailMismatch => (
                StatusCodes.Status409Conflict,
                "googleEmailMismatch",
                "That Google account uses a different email address."),
            AccountChangeOutcome.GoogleAlreadyInUse => (
                StatusCodes.Status409Conflict,
                "googleAlreadyInUse",
                "That Google account is already linked to another account."),
            AccountChangeOutcome.WouldLockOut => (
                StatusCodes.Status409Conflict,
                "wouldLockOut",
                "Set a password first, or you would have no way back in."),
            _ => (
                StatusCodes.Status500InternalServerError,
                "unknown",
                "Something went wrong.")
        };

        var problem = new ProblemDetails { Status = status, Title = title };
        problem.Extensions["code"] = code;

        return StatusCode(status, problem);
    }
}

/// <summary>
/// The two things every auth endpoint does with the request itself.
/// </summary>
/// <remarks>
/// Extensions rather than a shared base controller: <c>AuthController</c> and
/// <c>MeController</c> have nothing else in common — one is anonymous and one
/// requires a token — and a base class would imply they do.
/// </remarks>
internal static class AuthControllerExtensions
{
    /// <summary>
    /// Where this request came from, for the sessions list.
    /// </summary>
    /// <remarks>
    /// The address has already been resolved through the forwarded-headers
    /// middleware, so behind a proxy this is the caller's rather than the
    /// proxy's. Both values are shown back to the reader and neither is ever
    /// acted on — see <c>RefreshToken.UserAgent</c>.
    /// </remarks>
    public static SessionOrigin Origin(this HttpContext context)
    {
        var agent = context.Request.Headers.UserAgent.ToString();

        return new SessionOrigin(
            context.Connection.RemoteIpAddress?.ToString(),
            // Truncated to what the column holds. A header long enough to
            // overflow it is either a curiosity or an attempt, and neither is
            // worth failing a sign-in over.
            string.IsNullOrWhiteSpace(agent)
                ? null
                : agent[..Math.Min(agent.Length, 256)]);
    }

    public static IActionResult Respond(this ControllerBase controller, AuthResult result)
    {
        if (result is { Succeeded: true })
        {
            return controller.Ok(result.Response);
        }

        switch (result.Error)
        {
            case AuthError.EmailAlreadyRegistered:
                return controller.Conflict(new ProblemDetails
                {
                    Title = "That email is already registered."
                });

            // Also a 409, and deliberately the same status as the above: from
            // the client's point of view both mean "this address is spoken for,
            // use the way in that already exists".
            case AuthError.EmailBelongsToPasswordAccount:
                return controller.Conflict(new ProblemDetails
                {
                    Title = "That email already has an account. "
                            + "Sign in with your password instead."
                });

            case AuthError.AccountLocked:
                // The same 429 the address-level rate limiter returns, which is
                // what keeps this from being a clean "yes, that account exists"
                // — a caller cannot tell which of the two limits it hit.
                var seconds = Math.Max(
                    1, (int)Math.Ceiling(result.RetryAfter?.TotalSeconds ?? 60));

                controller.Response.Headers.RetryAfter =
                    seconds.ToString(CultureInfo.InvariantCulture);

                return controller.StatusCode(
                    StatusCodes.Status429TooManyRequests,
                    new ProblemDetails
                    {
                        Title = "Too many sign-in attempts. Try again shortly."
                    });

            default:
                return controller.Unauthorized(new ProblemDetails
                {
                    Title = "Those details did not match."
                });
        }
    }
}
