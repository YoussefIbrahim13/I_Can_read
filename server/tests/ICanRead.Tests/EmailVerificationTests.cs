using System.Net;
using System.Net.Http.Json;
using ICanRead.Application.Auth;

namespace ICanRead.Tests;

/// <summary>
/// Proving that the address on an account is one the reader can read mail at.
/// </summary>
/// <remarks>
/// The point of the whole flow is the last two tests here: a confirmed address
/// is what makes it safe to hand a Google sign-in the account that already
/// exists under the same email, and an unconfirmed one is what makes it unsafe.
/// </remarks>
[Collection(ApiCollection.Name)]
public class EmailVerificationTests(ApiFactory factory)
{
    private readonly HttpClient _client = factory.CreateClient();

    private static string NewEmail() => $"reader-{Guid.NewGuid():N}@example.com";

    private async Task<(AuthResponse Auth, string Email)> RegisterAsync()
    {
        var email = NewEmail();
        var response = await _client.PostAsJsonAsync("/api/auth/register",
            new RegisterRequest(email, "correct horse battery", "Reader"));

        response.EnsureSuccessStatusCode();
        return ((await response.Content.ReadFromJsonAsync<AuthResponse>())!, email);
    }

    private Task<HttpResponseMessage> VerifyAsync(AuthResponse auth, string code) =>
        _client.PostAsAsync("/api/me/email/verify", auth.AccessToken,
            new VerifyEmailRequest(code));

    private async Task<(AuthResponse Auth, string Email)> ConfirmedReaderAsync()
    {
        var (auth, email) = await RegisterAsync();
        var code = factory.Mail.CodeFor(email)!;

        (await VerifyAsync(auth, code)).EnsureSuccessStatusCode();
        return (auth, email);
    }

    [Fact]
    public async Task Registering_sends_a_code_but_does_not_wait_for_it()
    {
        var (auth, email) = await RegisterAsync();

        // Signed in already. Holding the library until somebody goes and finds
        // an email is how a reader gives up on a reading app.
        Assert.False(string.IsNullOrWhiteSpace(auth.AccessToken));
        Assert.False(auth.User.EmailVerified);
        Assert.NotNull(factory.Mail.CodeFor(email));
    }

    [Fact]
    public async Task The_code_confirms_the_address()
    {
        var (auth, email) = await RegisterAsync();

        var response = await VerifyAsync(auth, factory.Mail.CodeFor(email)!);
        Assert.Equal(HttpStatusCode.NoContent, response.StatusCode);

        var me = await (await _client.GetAsAsync("/api/me", auth.AccessToken))
            .Content.ReadFromJsonAsync<UserResponse>();

        Assert.True(me!.EmailVerified);
    }

    [Fact]
    public async Task A_wrong_code_confirms_nothing()
    {
        var (auth, _) = await RegisterAsync();

        Assert.Equal(HttpStatusCode.BadRequest,
            (await VerifyAsync(auth, "000000")).StatusCode);

        var me = await (await _client.GetAsAsync("/api/me", auth.AccessToken))
            .Content.ReadFromJsonAsync<UserResponse>();

        Assert.False(me!.EmailVerified);
    }

    [Fact]
    public async Task Asking_again_retires_the_previous_code()
    {
        var (auth, email) = await RegisterAsync();
        var first = factory.Mail.CodeFor(email)!;

        (await _client.PostAsAsync("/api/me/email/send-code", auth.AccessToken))
            .EnsureSuccessStatusCode();
        var second = factory.Mail.CodeFor(email)!;

        Assert.NotEqual(first, second);
        Assert.Equal(HttpStatusCode.BadRequest, (await VerifyAsync(auth, first)).StatusCode);
        Assert.Equal(HttpStatusCode.NoContent, (await VerifyAsync(auth, second)).StatusCode);
    }

    [Fact]
    public async Task A_confirmation_code_is_not_a_password_reset_code()
    {
        var (_, email) = await RegisterAsync();
        var confirmation = factory.Mail.CodeFor(email)!;

        // The two codes look identical — six digits, same table, same lifetime.
        // What keeps "can receive mail here" from becoming "can take this
        // account over" is that a code is only valid for what it was issued for.
        var response = await _client.PostAsJsonAsync("/api/auth/reset-password",
            new ResetPasswordRequest(email, confirmation, "a brand new password"));

        Assert.Equal(HttpStatusCode.BadRequest, response.StatusCode);
    }

    [Fact]
    public async Task A_password_reset_code_does_not_confirm_an_address()
    {
        var (auth, email) = await RegisterAsync();

        (await _client.PostAsJsonAsync("/api/auth/forgot-password",
            new ForgotPasswordRequest(email))).EnsureSuccessStatusCode();

        var reset = factory.Mail.CodeFor(email)!;

        Assert.Equal(HttpStatusCode.BadRequest, (await VerifyAsync(auth, reset)).StatusCode);
    }

    [Fact]
    public async Task Google_joins_an_account_that_has_proved_its_address()
    {
        var (auth, email) = await ConfirmedReaderAsync();

        var response = await _client.PostAsJsonAsync("/api/auth/google",
            new GoogleTokenRequest(StubGoogleTokenVerifier.TokenFor("g-join", email)));

        Assert.Equal(HttpStatusCode.OK, response.StatusCode);

        var signedIn = await response.Content.ReadFromJsonAsync<AuthResponse>();
        // The same account, not a second one beside it.
        Assert.Equal(auth.User.Id, signedIn!.User.Id);
        Assert.True(signedIn.User.GoogleLinked);
        Assert.True(signedIn.User.HasPassword);
    }

    [Fact]
    public async Task Google_refuses_an_account_that_has_not()
    {
        var (_, email) = await RegisterAsync();

        // The attack this closes: register with an address you do not own, wait
        // for its real owner to arrive through Google, and inherit their
        // account. A squatter can never have confirmed the address.
        var response = await _client.PostAsJsonAsync("/api/auth/google",
            new GoogleTokenRequest(StubGoogleTokenVerifier.TokenFor("g-squat", email)));

        Assert.Equal(HttpStatusCode.Conflict, response.StatusCode);
    }

    [Fact]
    public async Task An_account_that_arrives_through_google_starts_out_confirmed()
    {
        var email = NewEmail();

        var response = await _client.PostAsJsonAsync("/api/auth/google",
            new GoogleTokenRequest(StubGoogleTokenVerifier.TokenFor("g-fresh", email)));

        var auth = await response.Content.ReadFromJsonAsync<AuthResponse>();

        // Google has already checked the address it is vouching for, which is
        // the same proof our own six digits ask for.
        Assert.True(auth!.User.EmailVerified);
        Assert.False(auth.User.HasPassword);
    }
}
