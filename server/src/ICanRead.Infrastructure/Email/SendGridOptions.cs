namespace ICanRead.Infrastructure.Email;

/// <summary>Configuration for the SendGrid mail sender.</summary>
public class SendGridOptions
{
    public const string Section = "SendGrid";

    /// <summary>
    /// The API key. Empty means mail is not configured, which is a legitimate
    /// state in development and a startup failure in production —
    /// see <c>Program.cs</c>.
    /// </summary>
    public string ApiKey { get; set; } = string.Empty;

    /// <summary>
    /// The address the reader sees. Must belong to a domain verified in
    /// SendGrid, or every message is rejected with a 403.
    /// </summary>
    public string FromAddress { get; set; } = string.Empty;

    public string FromName { get; set; } = "Yaqra";
}
