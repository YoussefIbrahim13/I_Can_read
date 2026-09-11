using System.Net;
using System.Net.Http.Json;
using ICanRead.Application.Auth;
using ICanRead.Domain.Entities;
using ICanRead.Infrastructure.Persistence;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.DependencyInjection;

namespace ICanRead.Tests;

/// <summary>
/// Making one account wait after too many wrong passwords.
/// </summary>
/// <remarks>
/// The rate limiter in front of these endpoints counts requests per address,
/// which is the defence against one machine guessing quickly. This is the
/// defence against many machines guessing at one account slowly — something the
/// address-level limit cannot see at all.
/// </remarks>
[Collection(ApiCollection.Name)]
public class LockoutTests(ApiFactory factory)
{
    private const string Password = "correct horse battery";

    private readonly HttpClient _client = factory.CreateClient();

    private static string NewEmail() => $"reader-{Guid.NewGuid():N}@example.com";

    private async Task<string> RegisteredEmailAsync()
    {
        var email = NewEmail();
        (await _client.PostAsJsonAsync("/api/auth/register",
            new RegisterRequest(email, Password, "Reader"))).EnsureSuccessStatusCode();

        return email;
    }

    private Task<HttpResponseMessage> LoginAsync(string email, string password) =>
        _client.PostAsJsonAsync("/api/auth/login", new LoginRequest(email, password));

    private async Task GuessWrongAsync(string email, int times)
    {
        for (var attempt = 0; attempt < times; attempt++)
        {
            var response = await LoginAsync(email, $"wrong {attempt}");
            Assert.Equal(HttpStatusCode.Unauthorized, response.StatusCode);
        }
    }

    /// <summary>Moves an account's lockout into the past, so the wait is over.</summary>
    private async Task ExpireTheLockAsync(string email)
    {
        using var scope = factory.Services.CreateScope();
        var db = scope.ServiceProvider.GetRequiredService<AppDbContext>();

        await db.Users
            .Where(u => u.Email == email)
            .ExecuteUpdateAsync(u => u.SetProperty(
                x => x.LockedUntil, DateTimeOffset.UtcNow.AddMinutes(-1)));
    }

    [Fact]
    public async Task Too_many_wrong_passwords_make_the_account_wait()
    {
        var email = await RegisteredEmailAsync();

        await GuessWrongAsync(email, User.SignInFailuresBeforeLockout);

        // Even with the right password. That is the whole point: the account is
        // not answering sign-in questions for a while.
        var response = await LoginAsync(email, Password);

        Assert.Equal(HttpStatusCode.TooManyRequests, response.StatusCode);
        Assert.NotNull(response.Headers.RetryAfter);
    }

    [Fact]
    public async Task The_wait_ends()
    {
        var email = await RegisteredEmailAsync();
        await GuessWrongAsync(email, User.SignInFailuresBeforeLockout);
        await ExpireTheLockAsync(email);

        Assert.Equal(HttpStatusCode.OK, (await LoginAsync(email, Password)).StatusCode);
    }

    [Fact]
    public async Task A_successful_sign_in_forgets_the_failures_before_it()
    {
        var email = await RegisteredEmailAsync();

        await GuessWrongAsync(email, User.SignInFailuresBeforeLockout - 1);
        Assert.Equal(HttpStatusCode.OK, (await LoginAsync(email, Password)).StatusCode);

        // The count is about *consecutive* failures. If it had survived the
        // success, this second run would have tipped the account over.
        await GuessWrongAsync(email, User.SignInFailuresBeforeLockout - 1);
        Assert.Equal(HttpStatusCode.OK, (await LoginAsync(email, Password)).StatusCode);
    }

    [Fact]
    public async Task Resetting_the_password_lifts_the_lock()
    {
        var email = await RegisteredEmailAsync();
        await GuessWrongAsync(email, User.SignInFailuresBeforeLockout);

        (await _client.PostAsJsonAsync("/api/auth/forgot-password",
            new ForgotPasswordRequest(email))).EnsureSuccessStatusCode();

        (await _client.PostAsJsonAsync("/api/auth/reset-password",
            new ResetPasswordRequest(email, factory.Mail.CodeFor(email)!, "a brand new password")))
            .EnsureSuccessStatusCode();

        // A reader who has just proved they can read mail at this address is
        // not somebody the lockout should still be holding out — the wrong
        // passwords that caused it were, by definition, not theirs.
        Assert.Equal(HttpStatusCode.OK,
            (await LoginAsync(email, "a brand new password")).StatusCode);
    }

    [Fact]
    public async Task An_address_with_no_account_is_never_reported_as_locked()
    {
        var email = NewEmail();

        await GuessWrongAsync(email, User.SignInFailuresBeforeLockout + 2);

        // A 429 here would answer "does this address have an account?" for
        // free. There is no row to count against, so there is nothing to say.
        Assert.Equal(HttpStatusCode.Unauthorized,
            (await LoginAsync(email, Password)).StatusCode);
    }
}
