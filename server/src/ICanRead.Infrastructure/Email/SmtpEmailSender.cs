using ICanRead.Application.Email;
using MailKit.Net.Smtp;
using MailKit.Security;
using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Options;
using MimeKit;

namespace ICanRead.Infrastructure.Email;

/// <summary>
/// Sends mail over SMTP with MailKit.
/// </summary>
/// <remarks>
/// <para>
/// MailKit rather than <c>System.Net.Mail.SmtpClient</c>, which Microsoft has
/// marked obsolete for new work, and rather than a provider's own HTTP API —
/// SMTP is the one interface every provider speaks, so moving from Gmail to
/// Mailgun to a company relay is a configuration change and not a rewrite.
/// </para>
/// <para>
/// A fresh connection per message. Reusing one would be faster, but this server
/// sends a handful of messages a day and a pooled connection that has gone
/// stale fails the one send that actually mattered.
/// </para>
/// </remarks>
public class SmtpEmailSender(
    IOptions<EmailOptions> options,
    ILogger<SmtpEmailSender> logger) : IEmailSender
{
    private readonly EmailOptions _options = options.Value;

    public async Task SendAsync(EmailMessage message, CancellationToken ct)
    {
        var mail = new MimeMessage();
        mail.From.Add(new MailboxAddress(_options.SenderName, _options.SenderEmail));
        mail.To.Add(MailboxAddress.Parse(message.ToAddress));
        mail.Subject = message.Subject;
        mail.Body = new BodyBuilder
        {
            // Both parts. A message with only an HTML body is treated as spam by
            // a good number of filters, and a reset code in a spam folder is a
            // reader locked out.
            TextBody = message.PlainTextBody,
            HtmlBody = message.HtmlBody
        }.ToMessageBody();

        using var smtp = new SmtpClient
        {
            // Mail is sent inside a request the reader is waiting on, so a
            // provider having a slow day must not hold that request open.
            Timeout = (int)TimeSpan.FromSeconds(15).TotalMilliseconds
        };

        try
        {
            // StartTls, not Auto: Auto will fall back to an unencrypted session
            // if the server does not advertise TLS, and the password would go
            // out in the clear.
            await smtp.ConnectAsync(
                _options.SmtpServer, _options.Port, SecureSocketOptions.StartTls, ct);
            await smtp.AuthenticateAsync(_options.SenderEmail, _options.Password, ct);
            await smtp.SendAsync(mail, ct);
            await smtp.DisconnectAsync(true, ct);

            logger.LogInformation("Sent {Subject} to {Recipient}.",
                message.Subject, message.ToAddress);
        }
        catch (Exception error)
        {
            // Logged here, where the provider's own reason is still attached,
            // and rethrown: what to do about a failure belongs to the caller,
            // and for a password reset that answer is "say nothing" — see
            // PasswordResetService.
            logger.LogError(error, "Could not send mail to {Recipient}.",
                message.ToAddress);
            throw;
        }
    }
}

/// <summary>
/// Writes the message to the log instead of sending it.
/// </summary>
/// <remarks>
/// Development only. It exists so a fresh clone can walk the whole reset flow —
/// the code is right there in the console — without an SMTP account, and
/// <c>Program.cs</c> refuses to boot with it outside Development.
/// </remarks>
public class LoggingEmailSender(ILogger<LoggingEmailSender> logger) : IEmailSender
{
    public Task SendAsync(EmailMessage message, CancellationToken ct)
    {
        logger.LogWarning(
            "Mail is not configured, so nothing was sent. To {Recipient}, "
            + "subject {Subject}:\n{Body}",
            message.ToAddress, message.Subject, message.PlainTextBody);
        return Task.CompletedTask;
    }
}
