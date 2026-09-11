using System.Net;
using System.Net.Http.Json;
using System.Text.Json;
using ICanRead.Application.Auth;

namespace ICanRead.Tests;

/// <summary>
/// What a signed-in reader can do to their own account: their name, their
/// password, and whether Google is one of the ways in.
/// </summary>
[Collection(ApiCollection.Name)]
public class AccountManagementTests(ApiFactory factory)
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

    /// <summary>A reader who has registered and proved their address.</summary>
    private async Task<(AuthResponse Auth, string Email)> ConfirmedAsync()
    {
        var (auth, email) = await RegisterAsync();

        (await _client.PostAsAsync("/api/me/email/verify", auth.AccessToken,
            new VerifyEmailRequest(factory.Mail.CodeFor(email)!))).EnsureSuccessStatusCode();

        return (auth, email);
    }

    private async Task<AuthResponse> GoogleReaderAsync(string subject, string email)
    {
        var response = await _client.PostAsJsonAsync("/api/auth/google",
            new GoogleTokenRequest(StubGoogleTokenVerifier.TokenFor(subject, email)));

        response.EnsureSuccessStatusCode();
        return (await response.Content.ReadFromJsonAsync<AuthResponse>())!;
    }

    private Task<HttpResponseMessage> LoginAsync(string email, string password) =>
        _client.PostAsJsonAsync("/api/auth/login", new LoginRequest(email, password));

    private Task<HttpResponseMessage> RefreshAsync(string refreshToken) =>
        _client.PostAsJsonAsync("/api/auth/refresh", new RefreshRequest(refreshToken));

    // ---- the reader's name ------------------------------------------------

    [Fact]
    public async Task The_reader_can_change_what_they_are_called()
    {
        var (auth, _) = await RegisterAsync();

        var response = await _client.SendAsAsync(HttpMethod.Patch, "/api/me",
            auth.AccessToken, new UpdateProfileRequest("  Yusuf  "));

        var user = await response.Content.ReadFromJsonAsync<UserResponse>();
        Assert.Equal("Yusuf", user!.DisplayName);
    }

    [Fact]
    public async Task Clearing_the_name_leaves_no_name_rather_than_an_empty_one()
    {
        var (auth, _) = await RegisterAsync();

        var response = await _client.SendAsAsync(HttpMethod.Patch, "/api/me",
            auth.AccessToken, new UpdateProfileRequest("   "));

        var user = await response.Content.ReadFromJsonAsync<UserResponse>();
        Assert.Null(user!.DisplayName);
    }

    // ---- the password -----------------------------------------------------

    [Fact]
    public async Task A_wrong_current_password_changes_nothing()
    {
        var (auth, email) = await RegisterAsync();

        var response = await _client.PostAsAsync("/api/me/password", auth.AccessToken,
            new ChangePasswordRequest("not the password", null, "a brand new password"));

        Assert.Equal(HttpStatusCode.Unauthorized, response.StatusCode);
        // The old one still works, which is the part that matters.
        Assert.Equal(HttpStatusCode.OK, (await LoginAsync(email, Password)).StatusCode);
    }

    [Fact]
    public async Task Changing_the_password_keeps_this_device_and_drops_the_others()
    {
        var (here, email) = await RegisterAsync();

        var elsewhere = await (await LoginAsync(email, Password))
            .Content.ReadFromJsonAsync<AuthResponse>();

        var response = await _client.PostAsAsync("/api/me/password", here.AccessToken,
            new ChangePasswordRequest(Password, null, "a brand new password"));

        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        var renewed = await response.Content.ReadFromJsonAsync<AuthResponse>();

        // The phone in the reader's hand carries on...
        Assert.Equal(HttpStatusCode.OK,
            (await RefreshAsync(renewed!.RefreshToken)).StatusCode);

        // ...and the session that may well be the reason for the change does not.
        Assert.Equal(HttpStatusCode.Unauthorized,
            (await RefreshAsync(elsewhere!.RefreshToken)).StatusCode);

        Assert.Equal(HttpStatusCode.Unauthorized, (await LoginAsync(email, Password)).StatusCode);
        Assert.Equal(HttpStatusCode.OK,
            (await LoginAsync(email, "a brand new password")).StatusCode);
    }

    [Fact]
    public async Task A_google_account_sets_its_first_password_with_a_google_token()
    {
        var email = NewEmail();
        var token = StubGoogleTokenVerifier.TokenFor("g-first-password", email);
        var auth = await GoogleReaderAsync("g-first-password", email);

        Assert.False(auth.User.HasPassword);

        // No old password to give, so the proof is the way they got in.
        var response = await _client.PostAsAsync("/api/me/password", auth.AccessToken,
            new ChangePasswordRequest(null, token, "a brand new password"));

        Assert.Equal(HttpStatusCode.OK, response.StatusCode);

        var renewed = await response.Content.ReadFromJsonAsync<AuthResponse>();
        Assert.True(renewed!.User.HasPassword);

        Assert.Equal(HttpStatusCode.OK,
            (await LoginAsync(email, "a brand new password")).StatusCode);
    }

    [Fact]
    public async Task A_google_account_cannot_have_its_password_set_without_google()
    {
        var email = NewEmail();
        var auth = await GoogleReaderAsync("g-no-proof", email);

        var response = await _client.PostAsAsync("/api/me/password", auth.AccessToken,
            new ChangePasswordRequest(null, null, "a brand new password"));

        Assert.Equal(HttpStatusCode.Unauthorized, response.StatusCode);
        Assert.Equal(HttpStatusCode.Unauthorized,
            (await LoginAsync(email, "a brand new password")).StatusCode);
    }

    // ---- linking google ---------------------------------------------------

    /// <summary>
    /// Four of the refusals below are 409s, and the app has to say something
    /// different for each. The status cannot carry that, so the code does — and
    /// if these strings drift, every one of those messages becomes "something
    /// went wrong" without anything failing to compile.
    /// </summary>
    private static async Task<string?> CodeOf(HttpResponseMessage response)
    {
        var problem = await response.Content.ReadFromJsonAsync<JsonElement>();
        return problem.TryGetProperty("code", out var code) ? code.GetString() : null;
    }

    [Fact]
    public async Task Each_refusal_names_itself_so_the_app_can_say_which_it_was()
    {
        var (unconfirmed, unconfirmedEmail) = await RegisterAsync();
        var (confirmed, _) = await ConfirmedAsync();
        var googleOnlyEmail = NewEmail();
        var googleOnly = await GoogleReaderAsync("g-codes", googleOnlyEmail);

        Assert.Equal("emailNotVerified", await CodeOf(
            await _client.PostAsAsync("/api/me/google/link", unconfirmed.AccessToken,
                new GoogleTokenRequest(
                    StubGoogleTokenVerifier.TokenFor("g-code-a", unconfirmedEmail)))));

        Assert.Equal("googleEmailMismatch", await CodeOf(
            await _client.PostAsAsync("/api/me/google/link", confirmed.AccessToken,
                new GoogleTokenRequest(
                    StubGoogleTokenVerifier.TokenFor("g-code-b", NewEmail())))));

        Assert.Equal("wouldLockOut", await CodeOf(
            await _client.PostAsAsync("/api/me/google/unlink", googleOnly.AccessToken,
                new DeleteAccountRequest(
                    null, StubGoogleTokenVerifier.TokenFor("g-codes", googleOnlyEmail)))));

        Assert.Equal("notConfirmed", await CodeOf(
            await _client.PostAsAsync("/api/me/password", confirmed.AccessToken,
                new ChangePasswordRequest("wrong", null, "a brand new password"))));
    }

    [Fact]
    public async Task Linking_google_needs_a_confirmed_address()
    {
        var (auth, email) = await RegisterAsync();

        var response = await _client.PostAsAsync("/api/me/google/link", auth.AccessToken,
            new GoogleTokenRequest(StubGoogleTokenVerifier.TokenFor("g-unconfirmed", email)));

        Assert.Equal(HttpStatusCode.Conflict, response.StatusCode);
    }

    [Fact]
    public async Task Linking_google_needs_the_same_address()
    {
        var (auth, _) = await ConfirmedAsync();

        // A different Google address would be a second, invisible key to an
        // account whose stated owner is somebody else.
        var response = await _client.PostAsAsync("/api/me/google/link", auth.AccessToken,
            new GoogleTokenRequest(
                StubGoogleTokenVerifier.TokenFor("g-elsewhere", NewEmail())));

        Assert.Equal(HttpStatusCode.Conflict, response.StatusCode);
    }

    [Fact]
    public async Task A_confirmed_account_can_link_google_and_then_sign_in_with_it()
    {
        var (auth, email) = await ConfirmedAsync();
        var token = StubGoogleTokenVerifier.TokenFor("g-linked", email);

        Assert.Equal(HttpStatusCode.NoContent,
            (await _client.PostAsAsync("/api/me/google/link", auth.AccessToken,
                new GoogleTokenRequest(token))).StatusCode);

        var signedIn = await (await _client.PostAsJsonAsync("/api/auth/google",
            new GoogleTokenRequest(token))).Content.ReadFromJsonAsync<AuthResponse>();

        Assert.Equal(auth.User.Id, signedIn!.User.Id);
        Assert.True(signedIn.User.GoogleLinked);
    }

    [Fact]
    public async Task One_google_account_cannot_be_the_key_to_two_accounts()
    {
        var (first, firstEmail) = await ConfirmedAsync();
        (await _client.PostAsAsync("/api/me/google/link", first.AccessToken,
            new GoogleTokenRequest(StubGoogleTokenVerifier.TokenFor("g-shared", firstEmail))))
            .EnsureSuccessStatusCode();

        var (second, secondEmail) = await ConfirmedAsync();

        // Same Google subject, wearing the second reader's address.
        var response = await _client.PostAsAsync("/api/me/google/link", second.AccessToken,
            new GoogleTokenRequest(
                StubGoogleTokenVerifier.TokenFor("g-shared", secondEmail)));

        Assert.Equal(HttpStatusCode.Conflict, response.StatusCode);
    }

    [Fact]
    public async Task Unlinking_google_is_refused_while_it_is_the_only_way_in()
    {
        var email = NewEmail();
        var token = StubGoogleTokenVerifier.TokenFor("g-only-door", email);
        var auth = await GoogleReaderAsync("g-only-door", email);

        var response = await _client.PostAsAsync("/api/me/google/unlink", auth.AccessToken,
            new DeleteAccountRequest(null, token));

        // An account with neither a password nor a Google link cannot be signed
        // into by anybody, ever — not even by reset, since there would be no
        // session to set a password from.
        Assert.Equal(HttpStatusCode.Conflict, response.StatusCode);
    }

    [Fact]
    public async Task Unlinking_google_works_once_there_is_a_password_to_fall_back_on()
    {
        var email = NewEmail();
        var token = StubGoogleTokenVerifier.TokenFor("g-second-door", email);
        var auth = await GoogleReaderAsync("g-second-door", email);

        var withPassword = await (await _client.PostAsAsync("/api/me/password",
            auth.AccessToken, new ChangePasswordRequest(null, token, "a brand new password")))
            .Content.ReadFromJsonAsync<AuthResponse>();

        var response = await _client.PostAsAsync("/api/me/google/unlink",
            withPassword!.AccessToken,
            new DeleteAccountRequest("a brand new password", null));

        Assert.Equal(HttpStatusCode.NoContent, response.StatusCode);

        var me = await (await _client.GetAsAsync("/api/me", withPassword.AccessToken))
            .Content.ReadFromJsonAsync<UserResponse>();

        Assert.False(me!.GoogleLinked);
        Assert.True(me.HasPassword);
    }
}
