using System.Net;
using System.Net.Http.Json;
using ICanRead.Application.Auth;

namespace ICanRead.Tests;

/// <summary>
/// The reader's own list of devices, and throwing one out of it.
/// </summary>
[Collection(ApiCollection.Name)]
public class SessionTests(ApiFactory factory)
{
    private const string Password = "correct horse battery";

    private readonly HttpClient _client = factory.CreateClient();

    private static string NewEmail() => $"reader-{Guid.NewGuid():N}@example.com";

    private async Task<(AuthResponse Auth, string Email)> RegisterAsync()
    {
        var email = NewEmail();
        var response = await _client.PostAsJsonAsync("/api/auth/register",
            new RegisterRequest(email, Password, "Reader"));

        response.EnsureSuccessStatusCode();
        return ((await response.Content.ReadFromJsonAsync<AuthResponse>())!, email);
    }

    private async Task<AuthResponse> LoginAsync(string email)
    {
        var response = await _client.PostAsJsonAsync("/api/auth/login",
            new LoginRequest(email, Password));

        response.EnsureSuccessStatusCode();
        return (await response.Content.ReadFromJsonAsync<AuthResponse>())!;
    }

    private async Task<IReadOnlyList<SessionResponse>> SessionsAsync(AuthResponse auth)
    {
        var response = await _client.GetAsAsync("/api/me/sessions", auth.AccessToken);
        response.EnsureSuccessStatusCode();

        return (await response.Content.ReadFromJsonAsync<List<SessionResponse>>())!;
    }

    private Task<HttpResponseMessage> RefreshAsync(string refreshToken) =>
        _client.PostAsJsonAsync("/api/auth/refresh", new RefreshRequest(refreshToken));

    [Fact]
    public async Task The_list_marks_the_device_it_was_asked_from()
    {
        var (auth, _) = await RegisterAsync();

        var sessions = await SessionsAsync(auth);

        var session = Assert.Single(sessions);
        Assert.True(session.IsCurrent);
    }

    [Fact]
    public async Task A_second_sign_in_is_a_second_session()
    {
        var (here, email) = await RegisterAsync();
        var elsewhere = await LoginAsync(email);

        var fromHere = await SessionsAsync(here);
        var fromElsewhere = await SessionsAsync(elsewhere);

        Assert.Equal(2, fromHere.Count);
        // Same two rows, and each device recognises itself rather than the other.
        Assert.Single(fromHere, s => s.IsCurrent);
        Assert.Single(fromElsewhere, s => s.IsCurrent);
        Assert.NotEqual(
            fromHere.Single(s => s.IsCurrent).Id,
            fromElsewhere.Single(s => s.IsCurrent).Id);
    }

    [Fact]
    public async Task Revoking_a_session_stops_the_device_it_belongs_to()
    {
        var (here, email) = await RegisterAsync();
        var elsewhere = await LoginAsync(email);

        var other = (await SessionsAsync(here)).Single(s => !s.IsCurrent);

        var response = await _client.SendAsAsync(
            HttpMethod.Delete, $"/api/me/sessions/{other.Id}", here.AccessToken);

        Assert.Equal(HttpStatusCode.NoContent, response.StatusCode);
        Assert.Equal(HttpStatusCode.Unauthorized,
            (await RefreshAsync(elsewhere.RefreshToken)).StatusCode);

        var left = Assert.Single(await SessionsAsync(here));
        Assert.True(left.IsCurrent);
    }

    [Fact]
    public async Task A_session_belonging_to_somebody_else_is_simply_not_found()
    {
        var (mine, _) = await RegisterAsync();
        var (theirs, _) = await RegisterAsync();

        var target = (await SessionsAsync(theirs)).Single();

        var response = await _client.SendAsAsync(
            HttpMethod.Delete, $"/api/me/sessions/{target.Id}", mine.AccessToken);

        // A 404 rather than a 403: which of "no such session" and "not yours"
        // it was is not something a caller gets to learn by asking.
        Assert.Equal(HttpStatusCode.NotFound, response.StatusCode);
        Assert.Equal(HttpStatusCode.OK,
            (await RefreshAsync(theirs.RefreshToken)).StatusCode);
    }

    [Fact]
    public async Task Signing_out_everywhere_else_leaves_this_device_alone()
    {
        var (here, email) = await RegisterAsync();
        var second = await LoginAsync(email);
        var third = await LoginAsync(email);

        var response = await _client.PostAsAsync(
            "/api/me/sessions/revoke-others", here.AccessToken);

        Assert.Equal(HttpStatusCode.NoContent, response.StatusCode);

        Assert.Equal(HttpStatusCode.Unauthorized,
            (await RefreshAsync(second.RefreshToken)).StatusCode);
        Assert.Equal(HttpStatusCode.Unauthorized,
            (await RefreshAsync(third.RefreshToken)).StatusCode);

        var left = Assert.Single(await SessionsAsync(here));
        Assert.True(left.IsCurrent);
    }

    [Fact]
    public async Task A_signed_out_device_coming_back_does_not_take_the_others_with_it()
    {
        var (here, email) = await RegisterAsync();
        var elsewhere = await LoginAsync(email);

        var other = (await SessionsAsync(here)).Single(s => !s.IsCurrent);
        (await _client.SendAsAsync(
            HttpMethod.Delete, $"/api/me/sessions/{other.Id}", here.AccessToken))
            .EnsureSuccessStatusCode();

        // The signed-out phone does not know yet. On its next launch it will
        // present the dead token exactly once, entirely innocently — and the
        // reuse detection must not read that as a stolen token and sign every
        // other device out in response.
        Assert.Equal(HttpStatusCode.Unauthorized,
            (await RefreshAsync(elsewhere.RefreshToken)).StatusCode);

        Assert.Equal(HttpStatusCode.OK, (await RefreshAsync(here.RefreshToken)).StatusCode);
    }

    [Fact]
    public async Task A_rotated_token_coming_back_does_take_the_others_with_it()
    {
        var (here, email) = await RegisterAsync();
        await LoginAsync(email);

        // Spent, not revoked: this one really has been exchanged, so seeing it
        // again means two parties are holding it.
        (await RefreshAsync(here.RefreshToken)).EnsureSuccessStatusCode();

        Assert.Equal(HttpStatusCode.Unauthorized,
            (await RefreshAsync(here.RefreshToken)).StatusCode);

        var response = await _client.GetAsAsync("/api/me/sessions", here.AccessToken);
        var left = await response.Content.ReadFromJsonAsync<List<SessionResponse>>();
        Assert.Empty(left!);
    }

    [Fact]
    public async Task Refreshing_renews_a_session_rather_than_opening_another()
    {
        var (auth, _) = await RegisterAsync();
        var before = (await SessionsAsync(auth)).Single();

        var renewed = await (await RefreshAsync(auth.RefreshToken))
            .Content.ReadFromJsonAsync<AuthResponse>();

        var after = Assert.Single(await SessionsAsync(renewed!));

        // A new row, because the token rotated — but one session, not two, and
        // it still carries where it was opened from rather than where it
        // happened to refresh.
        Assert.NotEqual(before.Id, after.Id);
        Assert.True(after.IsCurrent);
        Assert.Equal(before.IpAddress, after.IpAddress);
        Assert.Equal(before.Device, after.Device);
    }
}
