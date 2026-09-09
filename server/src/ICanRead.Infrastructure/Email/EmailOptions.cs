namespace ICanRead.Infrastructure.Email;

/// <summary>The SMTP account the server sends from.</summary>
public class EmailOptions
{
    public const string Section = "EmailSettings";

    /// <summary>e.g. <c>smtp.gmail.com</c>.</summary>
    public string SmtpServer { get; set; } = string.Empty;

    /// <summary>587 for STARTTLS, which is what nearly every provider wants.</summary>
    public int Port { get; set; } = 587;

    /// <summary>The address messages come from, and the SMTP username.</summary>
    public string SenderEmail { get; set; } = string.Empty;

    public string SenderName { get; set; } = "Yaqra";

    /// <summary>
    /// The SMTP password. On Gmail this is an app password, not the account's
    /// own — the account password will not authenticate here at all.
    /// </summary>
    public string Password { get; set; } = string.Empty;

    /// <summary>
    /// Whether mail is configured at all. An unconfigured server is allowed in
    /// development and refused at startup anywhere else.
    /// </summary>
    public bool IsConfigured =>
        !string.IsNullOrWhiteSpace(SmtpServer) &&
        !string.IsNullOrWhiteSpace(SenderEmail) &&
        !string.IsNullOrWhiteSpace(Password);
}
