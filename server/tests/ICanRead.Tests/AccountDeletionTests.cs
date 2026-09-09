using System.Net;
using System.Net.Http.Headers;
using System.Net.Http.Json;
using ICanRead.Application.Auth;
using ICanRead.Application.Sync;
using ICanRead.Infrastructure.Persistence;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.DependencyInjection;

namespace ICanRead.Tests;

[Collection(ApiCollection.Name)]
public class AccountDeletionTests(ApiFactory factory)
{
    private readonly HttpClient _client = factory.CreateClient();

    private const string Password = "correct horse battery";

    private static string NewEmail() => $"reader-{Guid.NewGuid():N}@example.com";

    private async Task<AuthResponse> RegisterAsync(string? email = null)
    {
        var response = await _client.PostAsJsonAsync("/api/auth/register",
            new RegisterRequest(email ?? NewEmail(), Password, "Reader"));
        response.EnsureSuccessStatusCode();
        return (await response.Content.ReadFromJsonAsync<AuthResponse>())!;
    }

    private async Task<HttpResponseMessage> DeleteAsync(
        AuthResponse auth,
        string? password = Password,
        string? googleIdToken = null)
    {
        // Awaited inside the `using`, not returned from it: disposing the
        // request while the send is still in flight tears its own body out from
        // under it.
        using var request = new HttpRequestMessage(HttpMethod.Post, "/api/me/delete")
        {
            Content = JsonContent.Create(
                new DeleteAccountRequest(password, googleIdToken))
        };
        request.Headers.Authorization =
            new AuthenticationHeaderValue("Bearer", auth.AccessToken);
        return await _client.SendAsync(request);
    }

    /// <summary>
    /// A book, a plan and a day's reading, so there is something to lose.
    /// Returns the id of the log entry, which is the row a cascade would miss.
    /// </summary>
    private async Task<Guid> PushALibraryAsync(AuthResponse auth)
    {
        var bookId = Guid.NewGuid();
        var planId = Guid.NewGuid();
        var logId = Guid.NewGuid();
        var now = DateTimeOffset.UtcNow;

        var payload = new SyncPayload
        {
            Books =
            [
                new BookDto(bookId, "The Muqaddimah", "Ibn Khaldun", 300, 0,
                    "reading", now, now, null)
            ],
            Fingerprints =
            [
                new FingerprintDto(Guid.NewGuid(), bookId, new string('a', 64),
                    300, 1024, "book.pdf", now)
            ],
            Plans =
            [
                new PlanDto(planId, bookId, "byPagesPerDay", 1, 300,
                    DateOnly.FromDateTime(DateTime.UtcNow),
                    DateOnly.FromDateTime(DateTime.UtcNow.AddDays(30)),
                    10, 20, true, null, 0, now, now)
            ],
            Sessions =
            [
                new SessionDto(Guid.NewGuid(), planId, 0, 1200, 10, 127, true,
                    now, null)
            ],
            LogEntries =
            [
                new LogEntryDto(logId, planId, null,
                    DateOnly.FromDateTime(DateTime.UtcNow), 1, 20, 20, 600, now)
            ]
        };

        using var request = new HttpRequestMessage(HttpMethod.Post, "/api/sync/push")
        {
            Content = JsonContent.Create(payload)
        };
        request.Headers.Authorization =
            new AuthenticationHeaderValue("Bearer", auth.AccessToken);

        (await _client.SendAsync(request)).EnsureSuccessStatusCode();
        return logId;
    }

    private AppDbContext Db(IServiceScope scope) =>
        scope.ServiceProvider.GetRequiredService<AppDbContext>();

    [Fact]
    public async Task Deleting_takes_the_whole_library_with_it()
    {
        var auth = await RegisterAsync();
        var logId = await PushALibraryAsync(auth);

        var response = await DeleteAsync(auth);
        Assert.Equal(HttpStatusCode.NoContent, response.StatusCode);

        using var scope = factory.Services.CreateScope();
        var db = Db(scope);

        Assert.False(await db.Users.AnyAsync(u => u.Id == auth.User.Id));
        Assert.False(await db.Books.AnyAsync(b => b.UserId == auth.User.Id));
        // The reading log's foreign key is Restrict, so it is the one table a
        // cascade would have left behind — and the one that would have kept a
        // deleted reader's history. Checked by id rather than by emptying the
        // table: other tests in this collection have libraries of their own.
        Assert.False(await db.ReadingLog.AnyAsync(entry => entry.Id == logId));
    }

    [Fact]
    public async Task A_wrong_password_does_not_delete_anything()
    {
        var auth = await RegisterAsync();

        var response = await DeleteAsync(auth, password: "not the password");

        Assert.Equal(HttpStatusCode.Unauthorized, response.StatusCode);
        using var scope = factory.Services.CreateScope();
        Assert.True(await Db(scope).Users.AnyAsync(u => u.Id == auth.User.Id));
    }

    [Fact]
    public async Task A_valid_token_alone_is_not_enough()
    {
        var auth = await RegisterAsync();

        var response = await DeleteAsync(auth, password: null);

        // An access token lasts half an hour, so a phone left on a table is a
        // valid access token — and this is the one call that cannot be undone.
        Assert.Equal(HttpStatusCode.Unauthorized, response.StatusCode);
        using var scope = factory.Services.CreateScope();
        Assert.True(await Db(scope).Users.AnyAsync(u => u.Id == auth.User.Id));
    }

    [Fact]
    public async Task Signing_in_again_afterwards_finds_nothing()
    {
        var email = NewEmail();
        var auth = await RegisterAsync(email);
        await DeleteAsync(auth);

        var signIn = await _client.PostAsJsonAsync("/api/auth/login",
            new LoginRequest(email, Password));
        Assert.Equal(HttpStatusCode.Unauthorized, signIn.StatusCode);

        // Every session went with the account, so the refresh token the deleted
        // device is still holding buys nothing.
        var refresh = await _client.PostAsJsonAsync("/api/auth/refresh",
            new RefreshRequest(auth.RefreshToken));
        Assert.Equal(HttpStatusCode.Unauthorized, refresh.StatusCode);
    }

    [Fact]
    public async Task The_address_is_free_to_register_again()
    {
        var email = NewEmail();
        await DeleteAsync(await RegisterAsync(email));

        // Nothing is kept, so nothing stands in the way of coming back — with
        // an empty library, which is what deletion meant.
        var again = await _client.PostAsJsonAsync("/api/auth/register",
            new RegisterRequest(email, Password, "Reader"));
        Assert.Equal(HttpStatusCode.OK, again.StatusCode);
    }

    [Fact]
    public async Task A_google_account_confirms_with_google_rather_than_a_password()
    {
        var subject = Guid.NewGuid().ToString();
        var token = StubGoogleTokenVerifier.TokenFor(subject, NewEmail());
        var googleAuth = (await (await _client.PostAsJsonAsync("/api/auth/google",
                new GoogleSignInRequest(token)))
            .Content.ReadFromJsonAsync<AuthResponse>())!;

        // It has no password, so a password cannot be what confirms it.
        var withoutToken = await DeleteAsync(googleAuth, password: "anything");
        Assert.Equal(HttpStatusCode.Unauthorized, withoutToken.StatusCode);

        // Nor does somebody else's Google account.
        var wrongSubject = await DeleteAsync(googleAuth, password: null,
            googleIdToken: StubGoogleTokenVerifier.TokenFor(
                Guid.NewGuid().ToString(), NewEmail()));
        Assert.Equal(HttpStatusCode.Unauthorized, wrongSubject.StatusCode);

        var confirmed = await DeleteAsync(googleAuth, password: null,
            googleIdToken: token);
        Assert.Equal(HttpStatusCode.NoContent, confirmed.StatusCode);

        using var scope = factory.Services.CreateScope();
        Assert.False(await Db(scope).Users.AnyAsync(u => u.Id == googleAuth.User.Id));
    }

    [Fact]
    public async Task Deleting_leaves_other_readers_alone()
    {
        var mine = await RegisterAsync();
        var theirs = await RegisterAsync();
        await PushALibraryAsync(theirs);

        await DeleteAsync(mine);

        using var scope = factory.Services.CreateScope();
        var db = Db(scope);
        Assert.True(await db.Users.AnyAsync(u => u.Id == theirs.User.Id));
        Assert.True(await db.Books.AnyAsync(b => b.UserId == theirs.User.Id));
        Assert.True(await db.ReadingLog.AnyAsync());
    }
}
