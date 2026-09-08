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
/// The real API, on a real SQL Server, on a database of its own.
/// </summary>
/// <remarks>
/// Deliberately not SQLite or the in-memory provider. The schema leans on
/// things only the real provider does the same way — a filtered unique index on
/// GoogleSubject, <c>DateOnly</c> mapping, <c>ExecuteUpdateAsync</c> — and a
/// test that passes against a substitute would not tell us the migration works.
///
/// Requires the local <c>.\SQLEXPRESS01</c> instance, the same one development
/// runs against.
/// </remarks>
public class ApiFactory : WebApplicationFactory<Program>, IAsyncLifetime
{
    private const string ConnectionString =
        "Server=.\\SQLEXPRESS01;Database=ICanRead_Test;Integrated Security=true;" +
        "TrustServerCertificate=true;MultipleActiveResultSets=true";

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
                ["ConnectionStrings:Default"] = ConnectionString
            });
        });

        builder.ConfigureServices(services =>
        {
            services.RemoveAll<DbContextOptions<AppDbContext>>();
            services.RemoveAll<AppDbContext>();
            services.AddDbContext<AppDbContext>(o => o.UseSqlServer(ConnectionString));

            services.RemoveAll<IGoogleTokenVerifier>();
            services.AddScoped<IGoogleTokenVerifier, StubGoogleTokenVerifier>();
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
