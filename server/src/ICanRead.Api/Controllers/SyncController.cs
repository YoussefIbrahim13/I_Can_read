using System.Security.Claims;
using ICanRead.Application.Sync;
using ICanRead.Infrastructure.Sync;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;

namespace ICanRead.Api.Controllers;

/// <summary>
/// Base for every endpoint that works on the caller's own data.
/// </summary>
public abstract class UserScopedController : ControllerBase
{
    /// <summary>
    /// The account this request belongs to, from the token and nowhere else.
    /// </summary>
    /// <remarks>
    /// The single rule the whole API rests on: a user id in a request body is
    /// a claim by the caller, and this one is a claim by the server that signed
    /// the token. No endpoint accepts the former.
    /// </remarks>
    protected bool TryGetUserId(out Guid userId) =>
        Guid.TryParse(User.FindFirstValue(ClaimTypes.NameIdentifier), out userId);
}

[ApiController]
[Route("api/sync")]
[Authorize]
public class SyncController(SyncService sync) : UserScopedController
{
    /// <summary>
    /// Everything that changed since <paramref name="since"/>.
    /// </summary>
    /// <param name="since">
    /// The <c>serverTime</c> from the previous pull. Omitted on a new device,
    /// which then gets everything.
    /// </param>
    [HttpGet("pull")]
    public async Task<IActionResult> Pull(
        [FromQuery] DateTimeOffset? since,
        CancellationToken ct)
    {
        if (!TryGetUserId(out var userId)) return Unauthorized();
        return Ok(await sync.PullAsync(userId, since, ct));
    }

    [HttpPost("push")]
    public async Task<IActionResult> Push(SyncPayload payload, CancellationToken ct)
    {
        if (!TryGetUserId(out var userId)) return Unauthorized();
        return Ok(await sync.PushAsync(userId, payload, ct));
    }
}

[ApiController]
[Route("api/books")]
[Authorize]
public class BooksController(SyncService sync) : UserScopedController
{
    /// <summary>
    /// The new-device relink: "I have this file — do I already own the book?"
    /// </summary>
    [HttpPost("lookup-by-hash")]
    public async Task<IActionResult> LookupByHash(
        LookupByHashRequest request,
        CancellationToken ct)
    {
        if (!TryGetUserId(out var userId)) return Unauthorized();

        // Scoped to the caller, so this cannot be used to ask whether anybody
        // at all has a given file.
        var book = await sync.LookupByHashAsync(userId, request.Sha256, ct);
        return Ok(new LookupByHashResponse(book));
    }
}
