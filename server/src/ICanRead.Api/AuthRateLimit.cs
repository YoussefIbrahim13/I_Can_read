namespace ICanRead.Api;

/// <summary>
/// Names the rate-limiting policy so the controller and <c>Program.cs</c> agree
/// on it without a loose string in two places.
/// </summary>
public static class AuthRateLimit
{
    public const string Policy = "auth";

    /// <summary>Configuration section holding the window size.</summary>
    public const string Section = "RateLimit";
}

/// <summary>How hard the auth endpoints may be hammered from one address.</summary>
/// <remarks>
/// Configurable because the right number depends on the deployment — a server
/// behind a NAT that many readers share needs a higher ceiling than one facing
/// the open internet — and because the test suite drives these endpoints far
/// harder than any person would.
/// </remarks>
public class RateLimitOptions
{
    /// <summary>
    /// Requests allowed per window. Ten is far more than a person signing in and
    /// far less than a script working through six digits.
    /// </summary>
    public int AuthPermitLimit { get; set; } = 10;

    public int AuthWindowSeconds { get; set; } = 60;
}
