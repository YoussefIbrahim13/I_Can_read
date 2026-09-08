using System.Net.Http.Headers;
using System.Net.Http.Json;
using ICanRead.Application.Email;
using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Options;

namespace ICanRead.Infrastructure.Email;

/// <summary>
/// Sends mail through SendGrid's v3 API.
/// </summary>
/// <remarks>
/// Straight HTTP against the documented endpoint rather than the official SDK.
/// The SDK's whole surface here would be one POST of a JSON body, and this way
/// the deployment carries no extra dependency to keep patched.
/// </remarks>
public class SendGridEmailSender(
    HttpClient http,
    IOptions<SendGridOptions> options,
    ILogger<SendGridEmailSender> logger) : IEmailSender
{
    private readonly SendGridOptions _options = options.Value;

    public async Task SendAsync(EmailMessage message, CancellationToken ct)
    {
        var payload = new
        {
            personalizations = new[]
            {
                new { to = new[] { new { email = message.ToAddress } } }
            },
            from = new { email = _options.FromAddress, name = _options.FromName },
            subject = message.Subject,
            content = new[]
            {
                // Order matters to the spec: text/plain must come first, and
                // clients show the last part they understand.
                new { type = "text/plain", value = message.PlainTextBody },
                new { type = "text/html", value = message.HtmlBody }
            }
        };

        using var request = new HttpRequestMessage(HttpMethod.Post, "v3/mail/send")
        {
            Content = JsonContent.Create(payload)
        };
        request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", _options.ApiKey);

        using var response = await http.SendAsync(request, ct);

        if (!response.IsSuccessStatusCode)
        {
            // The body carries SendGrid's reason — an unverified sender, a
            // suppressed address — and without it the log says only "it did not
            // work", which is the one thing already obvious.
            var body = await response.Content.ReadAsStringAsync(ct);
            logger.LogError(
                "SendGrid refused a message to {Recipient}: {Status} {Body}",
                message.ToAddress, (int)response.StatusCode, body);

            throw new HttpRequestException(
                $"SendGrid returned {(int)response.StatusCode}.");
        }
    }
}

/// <summary>
/// Writes the message to the log instead of sending it.
/// </summary>
/// <remarks>
/// Development only. It exists so a fresh clone can walk the whole reset flow —
/// the code is right there in the console — without a SendGrid account, and
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
