using System.Collections.Concurrent;
using System.Net.Http.Headers;
using System.Net.Http.Json;
using System.Text.RegularExpressions;
using ICanRead.Application.Email;
using ICanRead.Infrastructure.Auth;
using ICanRead.Infrastructure.Persistence;
using Microsoft.AspNetCore.Hosting;
using Microsoft.AspNetCore.Mvc.Testing;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.Hosting;

namespace ICanRead.Tests;

/// <summary>
/// The real API, on a real Postgres, on a database of its own.
/// </summary>
/// <remarks>
/// Deliberately not SQLite or the in-memory provider. The schema leans on
/// things only the real provider does the same way — a partial unique index on
/// GoogleSubject, <c>DateOnly</c> mapping, <c>ExecuteUpdateAsync</c> — and a
/// test that passes against a substitute would not tell us the migration works.
///
/// Requires the local Postgres container, the same one development runs
/// against:
/// <code>
/// docker run -d --name icanread-pg -e POSTGRES_PASSWORD=devpassword \
///   -p 5433:5432 postgres:17
/// </code>
/// </remarks>
public class ApiFactory : WebApplicationFactory<Program>, IAsyncLifetime
{
    private const string ConnectionString =
        "Host=localhost;Port=5433;Database=ICanRead_Test;" +
        "Username=postgres;Password=devpassword";

    /// <summary>Every message the API tried to send, in place of a mail provider.</summary>
    public RecordingEmailSender Mail { get; } = new();

    protected override void ConfigureWebHost(IWebHostBuilder builder)
    {
        builder.UseEnvironment(Environments.Development);

        // Its own key and its own database, so the run does not depend on a
        // gitignored appsettings.Development.json that a fresh clone lacks.
        builder.ConfigureAppConfiguration(config =>
        {
            config.AddInMemoryCollection(new Dictionary<string, string?>
            {
                ["Jwt:SigningKey"] = "test-signing-key-thirty-two-bytes-or-more",
                ["ConnectionStrings:Default"] = ConnectionString,
                // The suite knocks on the auth endpoints far harder than any
                // person would, and all of it from one address. The limit has a
                // test of its own that sets its own ceiling.
                ["RateLimit:AuthPermitLimit"] = "100000"
            });
        });

        builder.ConfigureServices(services =>
        {
            services.RemoveAll<DbContextOptions<AppDbContext>>();
            services.RemoveAll<AppDbContext>();
            services.AddDbContext<AppDbContext>(o => o.UseNpgsql(ConnectionString));

            services.RemoveAll<IGoogleTokenVerifier>();
            services.AddScoped<IGoogleTokenVerifier, StubGoogleTokenVerifier>();

            services.RemoveAll<IEmailSender>();
            services.AddSingleton<IEmailSender>(Mail);
        });
    }

    // Implemented explicitly: xUnit's lifetime methods return `Task`, and the
    // base factory already has a `DisposeAsync` returning `ValueTask`.
    async Task IAsyncLifetime.InitializeAsync()
    {
        using var scope = Services.CreateScope();
        var db = scope.ServiceProvider.GetRequiredService<AppDbContext>();

        // Rebuilt from the migrations, not from EnsureCreated: that way a
        // migration that does not actually apply fails the test run.
        await db.Database.EnsureDeletedAsync();
        await db.Database.MigrateAsync();
    }

    Task IAsyncLifetime.DisposeAsync() => Task.CompletedTask;
}

/// <summary>
/// One factory, and therefore one database, shared by every test class.
/// </summary>
/// <remarks>
/// Without this each class would get its own <see cref="ApiFactory"/> via
/// <c>IClassFixture</c>, and since they all point at <c>ICanRead_Test</c>, one
/// class would drop the database out from under another running in parallel.
/// A collection fixture both shares the setup and stops the classes running at
/// the same time.
/// </remarks>
[CollectionDefinition(Name)]
public class ApiCollection : ICollectionFixture<ApiFactory>
{
    public const string Name = "api";
}

/// <summary>
/// Calling an endpoint as a signed-in reader.
/// </summary>
/// <remarks>
/// <c>HttpClient.DefaultRequestHeaders</c> is not an option: the factory hands
/// every test class a client over one shared server, and several tests act as
/// two readers at once. The token belongs to the request, not to the client.
/// </remarks>
public static class AuthenticatedRequests
{
    public static async Task<HttpResponseMessage> SendAsAsync(
        this HttpClient client,
        HttpMethod method,
        string path,
        string accessToken,
        object? body = null)
    {
        using var request = new HttpRequestMessage(method, path);
        request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", accessToken);

        if (body is not null)
        {
            request.Content = JsonContent.Create(body);
        }

        return await client.SendAsync(request);
    }

    public static Task<HttpResponseMessage> PostAsAsync(
        this HttpClient client, string path, string accessToken, object? body = null) =>
        client.SendAsAsync(HttpMethod.Post, path, accessToken, body);

    public static Task<HttpResponseMessage> GetAsAsync(
        this HttpClient client, string path, string accessToken) =>
        client.SendAsAsync(HttpMethod.Get, path, accessToken);
}

/// <summary>
/// Stands in for Google, so the tests can be about what we do with a verified
/// caller rather than about whether a signature check works.
/// </summary>
/// <remarks>
/// Verifying an RS256 signature against Google's published keys is
/// <c>Google.Apis.Auth</c>'s job and it is tested where it lives. What is ours,
/// and what these tests exercise, is everything after: which account a subject
/// resolves to, and when an email is refused rather than joined up.
///
/// Tokens are <c>google:{subject}:{email}</c>. Anything else fails to verify,
/// which is how the "Google would not vouch for this" path is reached.
/// </remarks>
public class StubGoogleTokenVerifier : IGoogleTokenVerifier
{
    public static string TokenFor(string subject, string email) =>
        $"google:{subject}:{email}";

    public Task<GooglePrincipal?> VerifyAsync(string idToken, CancellationToken ct)
    {
        var parts = idToken.Split(':');
        if (parts is not ["google", var subject, var email])
        {
            return Task.FromResult<GooglePrincipal?>(null);
        }

        return Task.FromResult<GooglePrincipal?>(
            new GooglePrincipal(subject, email, "Reader"));
    }
}

/// <summary>
/// Keeps every message instead of sending it, so a test can read the code a
/// reader would have been emailed.
/// </summary>
/// <remarks>
/// Concurrent because the factory is shared across a collection and the API
/// serves requests on its own threads.
/// </remarks>
public class RecordingEmailSender : IEmailSender
{
    private readonly ConcurrentDictionary<string, EmailMessage> _lastByAddress = new();

    public Task SendAsync(EmailMessage message, CancellationToken ct)
    {
        _lastByAddress[message.ToAddress] = message;
        return Task.CompletedTask;
    }

    public EmailMessage? LastTo(string address) =>
        _lastByAddress.GetValueOrDefault(address.Trim().ToLowerInvariant());

    /// <summary>The six digits out of the last message sent to an address.</summary>
    public string? CodeFor(string address)
    {
        var body = LastTo(address)?.PlainTextBody;
        if (body is null) return null;

        var match = Regex.Match(body, @"\b\d{6}\b");
        return match.Success ? match.Value : null;
    }
}

file static class ServiceCollectionExtensions
{
    public static void RemoveAll<T>(this IServiceCollection services)
    {
        foreach (var descriptor in services.Where(d => d.ServiceType == typeof(T)).ToList())
        {
            services.Remove(descriptor);
        }
    }
}
