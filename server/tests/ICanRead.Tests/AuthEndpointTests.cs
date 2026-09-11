using System.Net;
using System.Net.Http.Headers;
using System.Net.Http.Json;
using ICanRead.Application.Auth;

namespace ICanRead.Tests;

[Collection(ApiCollection.Name)]
public class AuthEndpointTests(ApiFactory factory)
{
    private readonly HttpClient _client = factory.CreateClient();

    /// <summary>A fresh address per test, so tests do not collide in the shared database.</summary>
    private static string NewEmail() => $"reader-{Guid.NewGuid():N}@example.com";

    private async Task<AuthResponse> RegisterAsync(string? email = null, string password = "correct horse battery")
    {
        var response = await _client.PostAsJsonAsync("/api/auth/register",
            new RegisterRequest(email ?? NewEmail(), password, "Reader"));

        response.EnsureSuccessStatusCode();
        return (await response.Content.ReadFromJsonAsync<AuthResponse>())!;
    }

    [Fact]
    public async Task Register_returns_a_usable_token_pair()
    {
        var auth = await RegisterAsync();

        Assert.False(string.IsNullOrWhiteSpace(auth.AccessToken));
        Assert.False(string.IsNullOrWhiteSpace(auth.RefreshToken));
        Assert.NotEqual(Guid.Empty, auth.User.Id);
        Assert.True(auth.AccessTokenExpiresAt > DateTimeOffset.UtcNow);
    }

    [Fact]
    public async Task Register_lower_cases_the_email_so_it_cannot_be_taken_twice()
    {
        var email = NewEmail();
        await RegisterAsync(email);

        var again = await _client.PostAsJsonAsync("/api/auth/register",
            new RegisterRequest(email.ToUpperInvariant(), "another password", null));

        Assert.Equal(HttpStatusCode.Conflict, again.StatusCode);
    }

    [Fact]
    public async Task Register_rejects_a_short_password()
    {
        var response = await _client.PostAsJsonAsync("/api/auth/register",
            new RegisterRequest(NewEmail(), "short", null));

        Assert.Equal(HttpStatusCode.BadRequest, response.StatusCode);
    }

    [Fact]
    public async Task Login_succeeds_regardless_of_how_the_email_was_typed()
    {
        var email = NewEmail();
        await RegisterAsync(email);

        var response = await _client.PostAsJsonAsync("/api/auth/login",
            new LoginRequest(email.ToUpperInvariant(), "correct horse battery"));

        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
    }

    [Fact]
    public async Task Login_says_the_same_thing_for_a_wrong_password_and_an_unknown_address()
    {
        var email = NewEmail();
        await RegisterAsync(email);

        var wrongPassword = await _client.PostAsJsonAsync("/api/auth/login",
            new LoginRequest(email, "not the password"));
        var noSuchUser = await _client.PostAsJsonAsync("/api/auth/login",
            new LoginRequest(NewEmail(), "correct horse battery"));

        // Identical, on purpose: telling them apart is how an attacker learns
        // which addresses have accounts.
        Assert.Equal(HttpStatusCode.Unauthorized, wrongPassword.StatusCode);
        Assert.Equal(HttpStatusCode.Unauthorized, noSuchUser.StatusCode);
        Assert.Equal(
            await wrongPassword.Content.ReadAsStringAsync(),
            await noSuchUser.Content.ReadAsStringAsync());
    }

    [Fact]
    public async Task Me_needs_a_token()
    {
        var response = await _client.GetAsync("/api/me");

        Assert.Equal(HttpStatusCode.Unauthorized, response.StatusCode);
    }

    [Fact]
    public async Task Me_returns_the_account_the_token_belongs_to()
    {
        var auth = await RegisterAsync();

        using var request = new HttpRequestMessage(HttpMethod.Get, "/api/me");
        request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", auth.AccessToken);
        var response = await _client.SendAsync(request);

        response.EnsureSuccessStatusCode();
        var me = await response.Content.ReadFromJsonAsync<UserResponse>();
        Assert.Equal(auth.User.Id, me!.Id);
        Assert.Equal(auth.User.Email, me.Email);
    }

    [Fact]
    public async Task Me_rejects_a_token_signed_with_the_wrong_key()
    {
        var auth = await RegisterAsync();
        // Same token, one character of the signature changed.
        var tampered = auth.AccessToken[..^2] + (auth.AccessToken[^2] == 'a' ? 'b' : 'a')
                       + auth.AccessToken[^1];

        using var request = new HttpRequestMessage(HttpMethod.Get, "/api/me");
        request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", tampered);
        var response = await _client.SendAsync(request);

        Assert.Equal(HttpStatusCode.Unauthorized, response.StatusCode);
    }

    [Fact]
    public async Task Refresh_hands_back_a_new_pair_and_spends_the_old_one()
    {
        var auth = await RegisterAsync();

        var response = await _client.PostAsJsonAsync("/api/auth/refresh",
            new RefreshRequest(auth.RefreshToken));
        response.EnsureSuccessStatusCode();
        var refreshed = await response.Content.ReadFromJsonAsync<AuthResponse>();

        Assert.NotEqual(auth.RefreshToken, refreshed!.RefreshToken);
        Assert.Equal(auth.User.Id, refreshed.User.Id);

        // The spent token is gone for good.
        var replay = await _client.PostAsJsonAsync("/api/auth/refresh",
            new RefreshRequest(auth.RefreshToken));
        Assert.Equal(HttpStatusCode.Unauthorized, replay.StatusCode);
    }

    [Fact]
    public async Task Replaying_a_spent_token_kills_the_whole_chain()
    {
        var auth = await RegisterAsync();

        var first = await _client.PostAsJsonAsync("/api/auth/refresh",
            new RefreshRequest(auth.RefreshToken));
        var live = (await first.Content.ReadFromJsonAsync<AuthResponse>())!;

        // The original comes back — it was captured, or a client double-spent.
        await _client.PostAsJsonAsync("/api/auth/refresh", new RefreshRequest(auth.RefreshToken));

        // The chain is no longer trustworthy, so even the token that was still
        // live a moment ago is now refused.
        var afterBreach = await _client.PostAsJsonAsync("/api/auth/refresh",
            new RefreshRequest(live.RefreshToken));
        Assert.Equal(HttpStatusCode.Unauthorized, afterBreach.StatusCode);
    }

    [Fact]
    public async Task Refresh_rejects_a_token_that_was_never_issued()
    {
        var response = await _client.PostAsJsonAsync("/api/auth/refresh",
            new RefreshRequest("VGhpcyB3YXMgbmV2ZXIgaXNzdWVkIGJ5IGFueW9uZQ=="));

        Assert.Equal(HttpStatusCode.Unauthorized, response.StatusCode);
    }

    [Fact]
    public async Task Logout_retires_the_session_but_says_nothing_about_it()
    {
        var auth = await RegisterAsync();

        var loggedOut = await _client.PostAsJsonAsync("/api/auth/logout",
            new RefreshRequest(auth.RefreshToken));
        Assert.Equal(HttpStatusCode.NoContent, loggedOut.StatusCode);

        var afterwards = await _client.PostAsJsonAsync("/api/auth/refresh",
            new RefreshRequest(auth.RefreshToken));
        Assert.Equal(HttpStatusCode.Unauthorized, afterwards.StatusCode);

        // An unknown token gets the same silence, so logout cannot be used to
        // probe which tokens exist.
        var unknown = await _client.PostAsJsonAsync("/api/auth/logout",
            new RefreshRequest("bm90IGEgcmVhbCB0b2tlbiBhdCBhbGwsIGhvbmVzdA=="));
        Assert.Equal(HttpStatusCode.NoContent, unknown.StatusCode);
    }

    // ------------------------------------------------------------------
    // Google
    // ------------------------------------------------------------------

    private Task<HttpResponseMessage> GoogleAsync(string idToken) =>
        _client.PostAsJsonAsync("/api/auth/google", new GoogleTokenRequest(idToken));

    [Fact]
    public async Task Google_creates_an_account_the_first_time_and_reuses_it_after()
    {
        var subject = Guid.NewGuid().ToString();
        var email = NewEmail();
        var token = StubGoogleTokenVerifier.TokenFor(subject, email);

        var first = await GoogleAsync(token);
        first.EnsureSuccessStatusCode();
        var created = (await first.Content.ReadFromJsonAsync<AuthResponse>())!;
        Assert.Equal(email, created.User.Email);

        var second = await GoogleAsync(token);
        second.EnsureSuccessStatusCode();
        var returning = (await second.Content.ReadFromJsonAsync<AuthResponse>())!;

        // The same reader, not a second account with the same address.
        Assert.Equal(created.User.Id, returning.User.Id);
    }

    [Fact]
    public async Task Google_follows_the_subject_when_the_email_changes()
    {
        var subject = Guid.NewGuid().ToString();
        var created = await GoogleAsync(StubGoogleTokenVerifier.TokenFor(subject, NewEmail()));
        var before = (await created.Content.ReadFromJsonAsync<AuthResponse>())!;

        // The reader changed their Google address. It is the same person and
        // must be the same library — which is why the subject is the key and
        // the email never is.
        var after = await GoogleAsync(StubGoogleTokenVerifier.TokenFor(subject, NewEmail()));
        after.EnsureSuccessStatusCode();

        Assert.Equal(
            before.User.Id,
            (await after.Content.ReadFromJsonAsync<AuthResponse>())!.User.Id);
    }

    [Fact]
    public async Task Google_will_not_take_over_an_email_that_has_a_password_account()
    {
        var email = NewEmail();
        await RegisterAsync(email);

        var response = await GoogleAsync(
            StubGoogleTokenVerifier.TokenFor(Guid.NewGuid().ToString(), email));

        // Linking the two would be the usual thing to do, and would be safe if
        // registration verified addresses. It does not — so somebody could
        // register an address they do not own and wait for its owner to arrive
        // through Google, ending up with a password to that reader's account.
        Assert.Equal(HttpStatusCode.Conflict, response.StatusCode);
    }

    [Fact]
    public async Task Google_signing_in_does_not_leave_a_password_that_would_work()
    {
        var email = NewEmail();
        await GoogleAsync(StubGoogleTokenVerifier.TokenFor(Guid.NewGuid().ToString(), email));

        // A Google-only account has no password hash, and the login path must
        // treat that as "no", not as "anything matches". A real-looking guess,
        // not an empty string — an empty one is refused by model validation
        // before it ever reaches the check this test is about.
        var attempt = await _client.PostAsJsonAsync("/api/auth/login",
            new LoginRequest(email, "any password at all"));

        Assert.Equal(HttpStatusCode.Unauthorized, attempt.StatusCode);
    }

    [Fact]
    public async Task A_token_Google_will_not_vouch_for_is_refused()
    {
        var response = await GoogleAsync("not-a-token-google-ever-signed");

        Assert.Equal(HttpStatusCode.Unauthorized, response.StatusCode);
    }

    [Fact]
    public async Task Google_sign_in_returns_a_token_pair_that_actually_works()
    {
        var response = await GoogleAsync(
            StubGoogleTokenVerifier.TokenFor(Guid.NewGuid().ToString(), NewEmail()));
        var auth = (await response.Content.ReadFromJsonAsync<AuthResponse>())!;

        // The point of signing in at all: the sync endpoints accept it.
        var me = new HttpRequestMessage(HttpMethod.Get, "/api/me");
        me.Headers.Authorization = new AuthenticationHeaderValue("Bearer", auth.AccessToken);

        var identified = await _client.SendAsync(me);
        identified.EnsureSuccessStatusCode();
    }
}
