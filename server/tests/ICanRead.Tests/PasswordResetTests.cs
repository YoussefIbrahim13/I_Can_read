using System.Net;
using System.Net.Http.Json;
using ICanRead.Application.Auth;
using ICanRead.Domain.Entities;

namespace ICanRead.Tests;

[Collection(ApiCollection.Name)]
public class PasswordResetTests(ApiFactory factory)
{
    private readonly HttpClient _client = factory.CreateClient();

    private const string OriginalPassword = "correct horse battery";
    private const string NewPassword = "a whole new passphrase";

    private static string NewEmail() => $"reader-{Guid.NewGuid():N}@example.com";

    private async Task<string> RegisteredEmailAsync()
    {
        var email = NewEmail();
        var response = await _client.PostAsJsonAsync("/api/auth/register",
            new RegisterRequest(email, OriginalPassword, "Reader"));
        response.EnsureSuccessStatusCode();
        return email;
    }

    private Task<HttpResponseMessage> ForgotAsync(string email) =>
        _client.PostAsJsonAsync("/api/auth/forgot-password", new ForgotPasswordRequest(email));

    private Task<HttpResponseMessage> ResetAsync(string email, string code, string password = NewPassword) =>
        _client.PostAsJsonAsync("/api/auth/reset-password",
            new ResetPasswordRequest(email, code, password));

    private Task<HttpResponseMessage> LoginAsync(string email, string password) =>
        _client.PostAsJsonAsync("/api/auth/login", new LoginRequest(email, password));

    [Fact]
    public async Task A_reader_who_forgot_their_password_can_set_a_new_one()
    {
        var email = await RegisteredEmailAsync();

        await ForgotAsync(email);
        var code = factory.Mail.CodeFor(email);
        Assert.NotNull(code);

        var reset = await ResetAsync(email, code);
        Assert.Equal(HttpStatusCode.NoContent, reset.StatusCode);

        Assert.Equal(HttpStatusCode.OK, (await LoginAsync(email, NewPassword)).StatusCode);
        // And the password they could not remember is genuinely gone.
        Assert.Equal(
            HttpStatusCode.Unauthorized,
            (await LoginAsync(email, OriginalPassword)).StatusCode);
    }

    [Fact]
    public async Task An_unknown_address_is_answered_exactly_like_a_known_one()
    {
        var known = await RegisteredEmailAsync();
        var unknown = NewEmail();

        var forKnown = await ForgotAsync(known);
        var forUnknown = await ForgotAsync(unknown);

        Assert.Equal(HttpStatusCode.NoContent, forKnown.StatusCode);
        Assert.Equal(HttpStatusCode.NoContent, forUnknown.StatusCode);
        // Nothing was sent to the address with no account — the silence is the
        // whole point, and it is why the endpoint answers the same either way.
        Assert.Null(factory.Mail.LastTo(unknown));
    }

    [Fact]
    public async Task The_code_only_works_once()
    {
        var email = await RegisteredEmailAsync();
        await ForgotAsync(email);
        var code = factory.Mail.CodeFor(email)!;

        await ResetAsync(email, code);
        var replay = await ResetAsync(email, code, "yet another passphrase");

        Assert.Equal(HttpStatusCode.BadRequest, replay.StatusCode);
        Assert.Equal(
            HttpStatusCode.Unauthorized,
            (await LoginAsync(email, "yet another passphrase")).StatusCode);
    }

    [Fact]
    public async Task Asking_again_retires_the_code_that_was_already_sent()
    {
        var email = await RegisteredEmailAsync();

        await ForgotAsync(email);
        var first = factory.Mail.CodeFor(email)!;

        await ForgotAsync(email);
        var second = factory.Mail.CodeFor(email)!;
        Assert.NotEqual(first, second);

        // Only the newest is live: two valid codes at once would widen the
        // window every time a reader tapped the button again.
        Assert.Equal(HttpStatusCode.BadRequest, (await ResetAsync(email, first)).StatusCode);
        Assert.Equal(HttpStatusCode.NoContent, (await ResetAsync(email, second)).StatusCode);
    }

    [Fact]
    public async Task Guessing_burns_the_code_after_a_handful_of_tries()
    {
        var email = await RegisteredEmailAsync();
        await ForgotAsync(email);
        var code = factory.Mail.CodeFor(email)!;

        for (var attempt = 0; attempt < AccountCode.MaxAttempts; attempt++)
        {
            var wrong = (int.Parse(code) + attempt + 1) % 1_000_000;
            var guess = await ResetAsync(email, wrong.ToString("D6"));
            Assert.Equal(HttpStatusCode.BadRequest, guess.StatusCode);
        }

        // Spent. The real code is no longer worth anything either, which is
        // what stops a script working through a million of them.
        Assert.Equal(HttpStatusCode.BadRequest, (await ResetAsync(email, code)).StatusCode);
    }

    [Fact]
    public async Task A_reset_signs_every_other_session_out()
    {
        var email = await RegisteredEmailAsync();
        var signedIn = await (await LoginAsync(email, OriginalPassword))
            .Content.ReadFromJsonAsync<AuthResponse>();

        await ForgotAsync(email);
        await ResetAsync(email, factory.Mail.CodeFor(email)!);

        // Somebody asking for a reset may be asking because another person is
        // in their account; leaving that session alive would make the reset
        // cosmetic.
        var stillValid = await _client.PostAsJsonAsync("/api/auth/refresh",
            new RefreshRequest(signedIn!.RefreshToken));
        Assert.Equal(HttpStatusCode.Unauthorized, stillValid.StatusCode);
    }

    [Fact]
    public async Task A_code_belonging_to_one_reader_does_not_open_another_account()
    {
        var mine = await RegisteredEmailAsync();
        var theirs = await RegisteredEmailAsync();

        await ForgotAsync(mine);
        var myCode = factory.Mail.CodeFor(mine)!;

        var crossUse = await ResetAsync(theirs, myCode);

        Assert.Equal(HttpStatusCode.BadRequest, crossUse.StatusCode);
        Assert.Equal(
            HttpStatusCode.OK,
            (await LoginAsync(theirs, OriginalPassword)).StatusCode);
    }

    [Fact]
    public async Task A_short_new_password_is_refused_before_the_code_is_spent()
    {
        var email = await RegisteredEmailAsync();
        await ForgotAsync(email);
        var code = factory.Mail.CodeFor(email)!;

        var tooShort = await ResetAsync(email, code, "short");
        Assert.Equal(HttpStatusCode.BadRequest, tooShort.StatusCode);

        // Model validation rejected it, so the code the reader is holding is
        // still good — being told the password is too short must not also cost
        // them the code.
        Assert.Equal(HttpStatusCode.NoContent, (await ResetAsync(email, code)).StatusCode);
    }
}
