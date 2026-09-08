namespace ICanRead.Application.Email;

/// <summary>One message, in both the forms a mail client may render.</summary>
/// <remarks>
/// Plain text is not optional. A message with only an HTML part is treated as
/// spam by a good number of filters, and a password reset that lands in a spam
/// folder is a reader locked out.
/// </remarks>
public record EmailMessage(
    string ToAddress,
    string Subject,
    string PlainTextBody,
    string HtmlBody);

/// <summary>
/// Whatever actually puts mail on the wire.
/// </summary>
/// <remarks>
/// An interface rather than a direct call to the provider so the tests can
/// assert on what would have been sent, and so swapping providers is one class
/// rather than a change to the reset logic.
/// </remarks>
public interface IEmailSender
{
    Task SendAsync(EmailMessage message, CancellationToken ct);
}
