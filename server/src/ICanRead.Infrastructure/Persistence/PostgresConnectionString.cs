using Npgsql;

namespace ICanRead.Infrastructure.Persistence;

/// <summary>
/// Turns the URL-shaped connection string a managed host publishes into the
/// keyword form Npgsql parses.
/// </summary>
/// <remarks>
/// Render, like most managed Postgres providers, hands out
/// <c>postgresql://user:password@host:port/database</c>. Npgsql does not accept
/// that shape at all — it wants <c>Host=…;Username=…</c> — so without this the
/// value straight out of the dashboard fails at the first connection. Anyone
/// deploying could translate it by hand, and would get it wrong once.
/// </remarks>
public static class PostgresConnectionString
{
    /// <summary>
    /// Normalises <paramref name="value"/> to an Npgsql keyword string.
    /// A keyword string is returned unchanged, so the caller does not have to
    /// know which of the two forms its configuration happens to hold.
    /// </summary>
    public static string FromUrlOrKeywords(string value)
    {
        var trimmed = value.Trim();

        if (!trimmed.StartsWith("postgres://", StringComparison.OrdinalIgnoreCase)
            && !trimmed.StartsWith("postgresql://", StringComparison.OrdinalIgnoreCase))
        {
            return trimmed;
        }

        var url = new Uri(trimmed);
        var credentials = url.UserInfo.Split(':', 2);

        var builder = new NpgsqlConnectionStringBuilder
        {
            Host = url.Host,
            Port = url.IsDefaultPort ? 5432 : url.Port,
            Database = Uri.UnescapeDataString(url.AbsolutePath.TrimStart('/')),
            Username = Uri.UnescapeDataString(credentials[0]),
            Password = credentials.Length > 1
                ? Uri.UnescapeDataString(credentials[1])
                : null,
            // Encrypted, but without checking the certificate chain. Require is
            // as far as we can go without pinning a CA we do not control: the
            // host reissues these certificates on its own schedule, and
            // VerifyFull would turn one of those reissues into an outage.
            // Deliberately not Prefer — Prefer falls back to plaintext when the
            // server declines TLS, silently, and this database holds password
            // hashes.
            SslMode = SslMode.Require
        };

        return builder.ConnectionString;
    }
}
