using ICanRead.Infrastructure.Persistence;
using Npgsql;

namespace ICanRead.Tests;

/// <summary>
/// Translating the connection string a managed host publishes.
/// </summary>
/// <remarks>
/// Not in the API collection, and touching no database: this is the one piece
/// of deployment configuration that can be got wrong silently, because the
/// symptom is a deploy that boots and then fails on its first query. Cheap to
/// pin down here instead.
/// </remarks>
public class PostgresConnectionStringTests
{
    private static NpgsqlConnectionStringBuilder Parse(string value) =>
        new(PostgresConnectionString.FromUrlOrKeywords(value));

    [Fact]
    public void A_postgres_url_becomes_the_keyword_form_Npgsql_reads()
    {
        var result = Parse(
            "postgresql://icanread_user:s3cret@dpg-abc123-a.frankfurt-postgres.render.com:5432/icanread");

        Assert.Equal("dpg-abc123-a.frankfurt-postgres.render.com", result.Host);
        Assert.Equal(5432, result.Port);
        Assert.Equal("icanread", result.Database);
        Assert.Equal("icanread_user", result.Username);
        Assert.Equal("s3cret", result.Password);
    }

    [Fact]
    public void The_connection_is_encrypted()
    {
        var result = Parse("postgres://user:pw@db.example.com:5432/icanread");

        // Require, not VerifyFull: encrypted without pinning a certificate
        // chain the host reissues on its own schedule. Not Prefer, which would
        // fall back to plaintext without saying so.
        Assert.Equal(SslMode.Require, result.SslMode);
    }

    [Fact]
    public void A_url_without_a_port_gets_the_default_one()
    {
        // Render's internal URL leaves the port off. Uri would otherwise report
        // -1 here and Npgsql would refuse it.
        Assert.Equal(5432, Parse("postgres://user:pw@icanread-db/icanread").Port);
    }

    [Fact]
    public void A_percent_encoded_password_is_decoded()
    {
        // Generated passwords contain characters that have to be escaped to
        // survive a URL. Handed to Npgsql still escaped, they simply fail to
        // authenticate — with an error that says nothing about why.
        var result = Parse("postgres://user:p%40ss%2Fword@db.example.com:5432/icanread");

        Assert.Equal("p@ss/word", result.Password);
    }

    [Fact]
    public void A_keyword_string_is_left_alone()
    {
        // Local development and the test host both configure this form, so the
        // translation has to be a no-op for them rather than something they
        // need to know about.
        const string keywords =
            "Host=localhost;Port=5433;Database=ICanRead;Username=postgres;Password=devpassword";

        Assert.Equal(keywords, PostgresConnectionString.FromUrlOrKeywords(keywords));
    }
}
