using System.Text;
using ICanRead.Domain.Entities;
using ICanRead.Infrastructure.Auth;
using ICanRead.Infrastructure.Persistence;
using ICanRead.Infrastructure.Sync;
using Microsoft.AspNetCore.Authentication.JwtBearer;
using Microsoft.AspNetCore.Identity;
using Microsoft.EntityFrameworkCore;
using Microsoft.IdentityModel.Tokens;

var builder = WebApplication.CreateBuilder(args);

// No OpenAPI document. `Microsoft.AspNetCore.OpenApi` pulls in Microsoft.OpenApi
// 2.x, whose whole line currently carries a high-severity advisory
// (GHSA-v5pm-xwqc-g5wc), and 3.x does not compile against the ASP.NET Core 10
// source generator. There is one consumer of this API and it is in this repo,
// so a generated document buys nothing worth a flagged dependency. Re-add it
// when a patched 2.x ships.

builder.Services.AddDbContext<AppDbContext>(options =>
    options.UseSqlServer(builder.Configuration.GetConnectionString("Default")));

builder.Services.AddOptions<JwtOptions>()
    .Bind(builder.Configuration.GetSection(JwtOptions.Section))
    // HS256 needs at least 256 bits of key. Checked on startup so a
    // misconfigured deployment fails at boot rather than at the first sign-in.
    .Validate(o => Encoding.UTF8.GetByteCount(o.SigningKey) >= 32,
        "Jwt:SigningKey must be at least 32 bytes.")
    .ValidateOnStart();

// Not validated on start, unlike the signing key: an install that does not
// offer Google sign-in is a legitimate configuration, and refusing to boot
// over it would make an optional feature mandatory.
builder.Services.AddOptions<GoogleOptions>()
    .Bind(builder.Configuration.GetSection(GoogleOptions.Section));

builder.Services.AddSingleton(TimeProvider.System);
builder.Services.AddSingleton<IPasswordHasher<User>, PasswordHasher<User>>();
builder.Services.AddScoped<TokenService>();
builder.Services.AddScoped<AuthService>();
builder.Services.AddScoped<SyncService>();
builder.Services.AddScoped<IGoogleTokenVerifier, GoogleTokenVerifier>();

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

var app = builder.Build();

app.UseAuthentication();
app.UseAuthorization();

app.MapGet("/health", () => Results.Ok(new { status = "ok" }));
app.MapControllers();

app.Run();

/// <summary>Named so the test project can drive the API with WebApplicationFactory.</summary>
public partial class Program;
