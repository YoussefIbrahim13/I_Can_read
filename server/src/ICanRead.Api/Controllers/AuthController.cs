using System.Security.Claims;
using ICanRead.Application.Auth;
using ICanRead.Infrastructure.Auth;
using ICanRead.Infrastructure.Persistence;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;

namespace ICanRead.Api.Controllers;

[ApiController]
[Route("api/auth")]
public class AuthController(AuthService auth, IGoogleTokenVerifier google) : ControllerBase
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
public class MeController(AppDbContext db) : ControllerBase
{
    [HttpGet]
    public async Task<IActionResult> Get(CancellationToken ct)
    {
        // From the token, never from the request body — the one rule that keeps
        // a caller from reading somebody else's account.
        var id = User.FindFirstValue(ClaimTypes.NameIdentifier);
        if (!Guid.TryParse(id, out var userId)) return Unauthorized();

        var user = await db.Users
            .Where(u => u.Id == userId)
            .Select(u => new UserResponse(u.Id, u.Email, u.DisplayName))
            .FirstOrDefaultAsync(ct);

        return user is null ? Unauthorized() : Ok(user);
    }
}
