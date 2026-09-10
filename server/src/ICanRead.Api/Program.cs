using System.Text;
using System.Threading.RateLimiting;
using ICanRead.Api;
using ICanRead.Application.Email;
using ICanRead.Domain.Entities;
using ICanRead.Infrastructure.Auth;
using ICanRead.Infrastructure.Email;
using ICanRead.Infrastructure.Persistence;
using ICanRead.Infrastructure.Sync;
using Microsoft.AspNetCore.HttpOverrides;
using Microsoft.AspNetCore.RateLimiting;
using Microsoft.Extensions.Options;
using Microsoft.AspNetCore.Authentication.JwtBearer;
using Microsoft.AspNetCore.Identity;
using Microsoft.EntityFrameworkCore;
using Microsoft.IdentityModel.Tokens;

var builder = WebApplication.CreateBuilder(args);

// The host assigns the port and expects the service to answer on exactly it —
// Render's default is 10000, but it is the variable that decides, not the
// number. Binding 0.0.0.0 rather than localhost is what makes the container
// reachable from outside itself. Absent locally, where launchSettings decides.
if (Environment.GetEnvironmentVariable("PORT") is { Length: > 0 } port)
{
    builder.WebHost.UseUrls($"http://0.0.0.0:{port}");
}

// No OpenAPI document. `Microsoft.AspNetCore.OpenApi` pulls in Microsoft.OpenApi
// 2.x, whose whole line currently carries a high-severity advisory
// (GHSA-v5pm-xwqc-g5wc), and 3.x does not compile against the ASP.NET Core 10
// source generator. There is one consumer of this API and it is in this repo,
// so a generated document buys nothing worth a flagged dependency. Re-add it
// when a patched 2.x ships.

// A managed host publishes its database as a URL, which Npgsql cannot parse;
// `PostgresConnectionString` translates that and passes a keyword string
// through untouched. DATABASE_URL is the name Render and most of its
// neighbours use, and is read as a fallback so the image runs on a host that
// sets only that.
var database = builder.Configuration.GetConnectionString("Default")
               ?? builder.Configuration["DATABASE_URL"];

if (string.IsNullOrWhiteSpace(database))
{
    throw new InvalidOperationException(
        "No database configured. Set ConnectionStrings__Default or DATABASE_URL.");
}

builder.Services.AddDbContext<AppDbContext>(options =>
    options.UseNpgsql(PostgresConnectionString.FromUrlOrKeywords(database)));

builder.Services.AddOptions<JwtOptions>()
    .Bind(builder.Configuration.GetSection(JwtOptions.Section))
    // HS256 needs at least 256 bits of key. Checked on startup so a
    // misconfigured deployment fails at boot rather than at the first sign-in.
    .Validate(o => Encoding.UTF8.GetByteCount(o.SigningKey) >= 32,
        "Jwt:SigningKey must be at least 32 bytes.")
    .ValidateOnStart();

// The client ID is not validated on start, unlike the signing key: an install
// that does not offer Google sign-in is a legitimate configuration, and
// refusing to boot over it would make an optional feature mandatory.
//
// The clock tolerance is the opposite case. It is a development-only crutch
// that widens the window an ID token stays usable in, and the way a setting
// like that reaches production is by sitting in a config file nobody re-read.
// Boot fails instead — the same rule the signing key follows.
var isDevelopment = builder.Environment.IsDevelopment();
builder.Services.AddOptions<GoogleOptions>()
    .Bind(builder.Configuration.GetSection(GoogleOptions.Section))
    .Validate(o => o.ClockToleranceMinutes >= 0,
        "Google:ClockToleranceMinutes cannot be negative.")
    .Validate(o => o.ClockToleranceMinutes == 0 || isDevelopment,
        "Google:ClockToleranceMinutes may only be set in Development. "
        + "It exists to work around a wrong clock on a developer's machine "
        + "and must never be set on a deployed server.")
    .ValidateOnStart();

builder.Services.AddOptions<EmailOptions>()
    .Bind(builder.Configuration.GetSection(EmailOptions.Section))
    // A deployed server that cannot send mail cannot reset a password, and a
    // reader who cannot reset a password has lost their library. Missing
    // configuration fails at boot rather than at the moment somebody needs it.
    .Validate(o => isDevelopment || o.IsConfigured,
        "EmailSettings needs SmtpServer, SenderEmail and Password outside "
        + "Development.")
    .ValidateOnStart();

builder.Services.AddSingleton(TimeProvider.System);
builder.Services.AddSingleton<IPasswordHasher<User>, PasswordHasher<User>>();
builder.Services.AddScoped<TokenService>();
builder.Services.AddScoped<AuthService>();
builder.Services.AddScoped<PasswordResetService>();
builder.Services.AddScoped<AccountDeletionService>();
builder.Services.AddScoped<SyncService>();
builder.Services.AddScoped<IGoogleTokenVerifier, GoogleTokenVerifier>();

// Development without an SMTP account still gets a working reset flow — the
// code goes to the console. Outside Development the validation above has
// already refused to boot, so the fallback cannot be reached there.
//
// Chosen per request rather than once at startup, so configuration a host
// layers on afterwards — which is what the test host does — still decides.
builder.Services.AddScoped<IEmailSender>(services =>
{
    var email = services.GetRequiredService<IOptions<EmailOptions>>();
    return email.Value.IsConfigured
        ? new SmtpEmailSender(email, services.GetRequiredService<ILogger<SmtpEmailSender>>())
        : new LoggingEmailSender(services.GetRequiredService<ILogger<LoggingEmailSender>>());
});

// Rate limiting, on the endpoints where guessing pays: sign-in, and the reset
// code. Keyed by remote address rather than by account — the account is exactly
// what an attacker is enumerating, so keying on it would let them spread the
// work across addresses and never hit a limit.
builder.Services.Configure<RateLimitOptions>(
    builder.Configuration.GetSection(AuthRateLimit.Section));

builder.Services.AddRateLimiter(options =>
{
    options.RejectionStatusCode = StatusCodes.Status429TooManyRequests;

    options.AddPolicy(AuthRateLimit.Policy, context =>
    {
        // Resolved per request rather than captured here. Configuration a host
        // layers on after this line — which is exactly what the test host does
        // — would otherwise be read too early to have any effect.
        var limits = context.RequestServices
            .GetRequiredService<IOptions<RateLimitOptions>>().Value;

        return RateLimitPartition.GetFixedWindowLimiter(
            context.Connection.RemoteIpAddress?.ToString() ?? "unknown",
            _ => new FixedWindowRateLimiterOptions
            {
                PermitLimit = limits.AuthPermitLimit,
                Window = TimeSpan.FromSeconds(limits.AuthWindowSeconds)
            });
    });
});

builder.Services.AddAuthentication(JwtBearerDefaults.AuthenticationScheme)
    .AddJwtBearer(options =>
    {
        var jwt = builder.Configuration.GetSection(JwtOptions.Section).Get<JwtOptions>()
                  ?? new JwtOptions();

        options.TokenValidationParameters = new TokenValidationParameters
        {
            ValidateIssuer = true,
            ValidIssuer = jwt.Issuer,
            ValidateAudience = true,
            ValidAudience = jwt.Audience,
            ValidateIssuerSigningKey = true,
            IssuerSigningKey = new SymmetricSecurityKey(
                Encoding.UTF8.GetBytes(jwt.SigningKey)),
            ValidateLifetime = true,
            // Default is five minutes of slack, which quietly extends every
            // access token past the expiry the client was told about.
            ClockSkew = TimeSpan.Zero
        };
    });

builder.Services.AddAuthorization();
builder.Services.AddControllers();

// Behind a platform proxy every request arrives from the proxy's own address,
// and the rate limiter above keys on the caller's. Without this, one bucket of
// ten requests a minute would be shared by every reader on the deployment, and
// the first person to mistype a password would lock out the rest.
builder.Services.Configure<ForwardedHeadersOptions>(options =>
{
    options.ForwardedHeaders =
        ForwardedHeaders.XForwardedFor | ForwardedHeaders.XForwardedProto;

    // The proxies sit on addresses we are not told in advance, so there is no
    // list to check them against. Emptying both collections is what turns that
    // check off — left at their defaults, which trust loopback only, the
    // middleware would ignore the header entirely and we would be back to
    // every reader sharing one bucket.
    options.KnownIPNetworks.Clear();
    options.KnownProxies.Clear();

    // Walk the chain to the front, which is the address the caller claims.
    // Render appends to X-Forwarded-For rather than replacing it, so that
    // address is only as honest as the caller: the limit is a speed bump in
    // front of a script working through six digits, not a defence against
    // someone who knows to rotate the header. See the README.
    options.ForwardLimit = null;
});

var app = builder.Build();

// Bring the schema up to date before serving anything. A managed host gives no
// shell to run `dotnet ef database update` from, and the alternative — a new
// deploy answering requests against last week's schema — is worse than what
// this costs. What it costs is that two instances starting at once would
// migrate at once; this service runs as one.
using (var scope = app.Services.CreateScope())
{
    await scope.ServiceProvider.GetRequiredService<AppDbContext>()
        .Database.MigrateAsync();
}

// Ahead of the rate limiter, which needs the forwarded address rather than the
// proxy's to have been resolved by the time it picks a bucket.
app.UseForwardedHeaders();

app.UseRateLimiter();
app.UseAuthentication();
app.UseAuthorization();

app.MapGet("/health", () => Results.Ok(new { status = "ok" }));
app.MapControllers();

app.Run();

/// <summary>Named so the test project can drive the API with WebApplicationFactory.</summary>
public partial class Program;
