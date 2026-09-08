using System.Net;
using System.Net.Http.Json;
using ICanRead.Application.Auth;
using Microsoft.AspNetCore.Hosting;
using Microsoft.Extensions.Configuration;

namespace ICanRead.Tests;

/// <summary>
/// The guessing limit on the auth endpoints.
/// </summary>
/// <remarks>
/// In the collection, so it does not run while another class is rebuilding the
/// database — but on a factory of its own, because the shared one deliberately
/// raises the ceiling out of the way and this is the one test that wants it low.
/// </remarks>
[Collection(ApiCollection.Name)]
public class RateLimitTests
{
    private const int Limit = 3;

    private sealed class ThrottledFactory : ApiFactory
    {
        protected override void ConfigureWebHost(IWebHostBuilder builder)
        {
            base.ConfigureWebHost(builder);
            builder.ConfigureAppConfiguration(config =>
                config.AddInMemoryCollection(new Dictionary<string, string?>
                {
                    ["RateLimit:AuthPermitLimit"] = Limit.ToString()
                }));
        }
    }

    [Fact]
    public async Task Sign_in_attempts_from_one_address_are_capped()
    {
        using var factory = new ThrottledFactory();
        var client = factory.CreateClient();

        var statuses = new List<HttpStatusCode>();
        for (var attempt = 0; attempt < Limit + 2; attempt++)
        {
            var response = await client.PostAsJsonAsync("/api/auth/login",
                new LoginRequest($"nobody-{attempt}@example.com", "not the password"));
            statuses.Add(response.StatusCode);
        }

        // The first few are answered — wrongly, but answered. What follows is
        // refused outright, which is what turns a million guesses from an
        // afternoon's work into something that never finishes.
        Assert.All(statuses.Take(Limit), s => Assert.Equal(HttpStatusCode.Unauthorized, s));
        Assert.All(statuses.Skip(Limit), s => Assert.Equal(HttpStatusCode.TooManyRequests, s));
    }
}
