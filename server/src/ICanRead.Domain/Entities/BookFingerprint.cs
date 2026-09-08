namespace ICanRead.Domain.Entities;

/// <summary>
/// A SHA-256 of a PDF file that has been accepted as this book.
/// </summary>
/// <remarks>
/// Many per book on purpose. A reader who adds a different scan or edition on
/// another device should have that file relink to the same plan rather than
/// start the book over, so every file that has ever been accepted keeps its
/// hash here. This is the only thing that makes the PDF-stays-on-the-phone
/// rule survive a new device.
/// </remarks>
public class BookFingerprint : ISyncedEntity
{
    public Guid Id { get; set; }

    public Guid BookId { get; set; }
    public Book? Book { get; set; }

    /// <summary>Lower-case hex SHA-256 of the whole file. Always 64 chars.</summary>
    public required string Sha256 { get; set; }

    /// <summary>
    /// Page count of <em>this</em> file, which may differ from the book's when
    /// the reader links a different edition.
    /// </summary>
    public int PageCount { get; set; }

    public long SizeBytes { get; set; }
    public string? OriginalFileName { get; set; }

    public DateTimeOffset CreatedAt { get; set; }

    /// <inheritdoc />
    public DateTimeOffset ServerUpdatedAt { get; set; }
}
