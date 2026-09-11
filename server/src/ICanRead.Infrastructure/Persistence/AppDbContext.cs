using ICanRead.Domain.Entities;
using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Storage.ValueConversion;

namespace ICanRead.Infrastructure.Persistence;

public class AppDbContext(DbContextOptions<AppDbContext> options) : DbContext(options)
{
    public DbSet<User> Users => Set<User>();
    public DbSet<RefreshToken> RefreshTokens => Set<RefreshToken>();
    public DbSet<AccountCode> AccountCodes => Set<AccountCode>();
    public DbSet<Book> Books => Set<Book>();
    public DbSet<BookFingerprint> BookFingerprints => Set<BookFingerprint>();
    public DbSet<ReadingPlan> ReadingPlans => Set<ReadingPlan>();
    public DbSet<ReadingSession> ReadingSessions => Set<ReadingSession>();
    public DbSet<ReadingLogEntry> ReadingLog => Set<ReadingLogEntry>();

    /// <summary>
    /// Every instant is normalised to UTC on its way to the database.
    /// </summary>
    /// <remarks>
    /// Npgsql refuses outright to write a <see cref="DateTimeOffset"/> whose
    /// offset is not zero to <c>timestamp with time zone</c> — it throws rather
    /// than converting. Everything this server writes itself already comes from
    /// <c>GetUtcNow</c>, but the timestamps in a sync push come from a phone,
    /// and "the client always sends Z" is a promise made by other code on
    /// another machine. One device shipping a local offset would turn every
    /// push into a 500.
    ///
    /// The conversion is exact — the same instant, expressed against UTC — so
    /// nothing is rounded or reinterpreted, and the store type does not change.
    /// </remarks>
    protected override void ConfigureConventions(ModelConfigurationBuilder builder)
    {
        builder.Properties<DateTimeOffset>()
            .HaveConversion<UtcOffsetConverter>();
    }

    private sealed class UtcOffsetConverter()
        : ValueConverter<DateTimeOffset, DateTimeOffset>(
            written => written.ToUniversalTime(),
            read => read);

    protected override void OnModelCreating(ModelBuilder b)
    {
        b.Entity<User>(e =>
        {
            e.ToTable("users");
            e.HasKey(u => u.Id);
            e.Property(u => u.Email).HasMaxLength(320).IsRequired();
            // Emails are stored lower-cased, so a plain unique index is enough
            // and stays sargable — a case-insensitive collation here would be
            // invisible to anyone reading the queries.
            e.HasIndex(u => u.Email).IsUnique();
            e.Property(u => u.PasswordHash).HasMaxLength(256);
            e.Property(u => u.GoogleSubject).HasMaxLength(128);
            // Partial, because accounts with no Google link are all NULL and
            // there is no reason to index them. Postgres already treats NULLs
            // as distinct in a unique index, so this is about the size of the
            // index rather than about correctness. Quoted because Postgres
            // folds unquoted identifiers to lower case and the column is
            // PascalCase.
            e.HasIndex(u => u.GoogleSubject)
                .IsUnique()
                .HasFilter("\"GoogleSubject\" IS NOT NULL");
            e.Property(u => u.DisplayName).HasMaxLength(200);
            // Computed from EmailVerifiedAt rather than stored alongside it —
            // two columns that can disagree about the same fact is a bug
            // waiting for the one write path that forgets the second.
            e.Ignore(u => u.IsEmailVerified);
        });

        b.Entity<RefreshToken>(e =>
        {
            e.ToTable("refresh_tokens");
            e.HasKey(t => t.Id);
            e.Property(t => t.TokenHash).HasMaxLength(64).IsRequired().IsFixedLength();
            e.HasIndex(t => t.TokenHash).IsUnique();
            // 45 is an IPv4-mapped IPv6 address written out in full, which is
            // the longest thing RemoteIpAddress can produce.
            e.Property(t => t.CreatedFromIp).HasMaxLength(45);
            e.Property(t => t.UserAgent).HasMaxLength(256);
            e.HasOne(t => t.User)
                .WithMany(u => u.RefreshTokens)
                .HasForeignKey(t => t.UserId)
                .OnDelete(DeleteBehavior.Cascade);
            // The sessions list: this account's live tokens, newest first.
            e.HasIndex(t => new { t.UserId, t.CreatedAt });
        });

        b.Entity<AccountCode>(e =>
        {
            e.ToTable("account_codes");
            e.HasKey(c => c.Id);
            e.Property(c => c.CodeHash).HasMaxLength(64).IsRequired().IsFixedLength();
            // As a string, for the same reason Book.Status is: adding a purpose
            // in the middle of the enum must not silently reinterpret the rows
            // already in the table.
            e.Property(c => c.Purpose).HasConversion<string>().HasMaxLength(32);
            e.HasOne(c => c.User)
                .WithMany()
                .HasForeignKey(c => c.UserId)
                .OnDelete(DeleteBehavior.Cascade);
            // The only query there is: the newest code of one purpose for one
            // account.
            e.HasIndex(c => new { c.UserId, c.Purpose, c.CreatedAt });
        });

        b.Entity<Book>(e =>
        {
            e.ToTable("books");
            e.HasKey(x => x.Id);
            e.Property(x => x.Title).HasMaxLength(500).IsRequired();
            e.Property(x => x.Author).HasMaxLength(300);
            // As a string, so the client's enum order and the server's can
            // drift without silently remapping every reader's shelves.
            e.Property(x => x.Status).HasConversion<string>().HasMaxLength(20);
            e.HasOne(x => x.User)
                .WithMany(u => u.Books)
                .HasForeignKey(x => x.UserId)
                .OnDelete(DeleteBehavior.Cascade);
            // Every sync pull is "this user's rows, changed since T".
            e.HasIndex(x => new { x.UserId, x.ServerUpdatedAt });
        });

        b.Entity<BookFingerprint>(e =>
        {
            e.ToTable("book_fingerprints");
            e.HasKey(x => x.Id);
            e.Property(x => x.Sha256).HasMaxLength(64).IsRequired().IsFixedLength();
            e.Property(x => x.OriginalFileName).HasMaxLength(400);
            e.HasOne(x => x.Book)
                .WithMany(x => x.Fingerprints)
                .HasForeignKey(x => x.BookId)
                .OnDelete(DeleteBehavior.Cascade);
            // The new-device lookup: "do I already own the book in this file?"
            e.HasIndex(x => x.Sha256);
            e.HasIndex(x => x.ServerUpdatedAt);
        });

        b.Entity<ReadingPlan>(e =>
        {
            e.ToTable("reading_plans");
            e.HasKey(x => x.Id);
            e.Property(x => x.Mode).HasConversion<string>().HasMaxLength(20);
            e.HasOne(x => x.Book)
                .WithMany(x => x.Plans)
                .HasForeignKey(x => x.BookId)
                .OnDelete(DeleteBehavior.Cascade);
            e.HasIndex(x => x.BookId);
            e.HasIndex(x => x.ServerUpdatedAt);
        });

        b.Entity<ReadingSession>(e =>
        {
            e.ToTable("reading_sessions");
            e.HasKey(x => x.Id);
            e.HasOne(x => x.Plan)
                .WithMany(x => x.Sessions)
                .HasForeignKey(x => x.PlanId)
                .OnDelete(DeleteBehavior.Cascade);
            e.HasIndex(x => x.PlanId);
            e.HasIndex(x => x.ServerUpdatedAt);
        });

        b.Entity<ReadingLogEntry>(e =>
        {
            e.ToTable("reading_log");
            e.HasKey(x => x.Id);
            e.HasOne(x => x.Plan)
                .WithMany(x => x.Log)
                .HasForeignKey(x => x.PlanId)
                // Restrict, not Cascade: the log is append-only and is the
                // record of what the reader actually did. Deleting a plan must
                // be a deliberate decision about the log too, not a silent
                // side effect of tidying up a book.
                .OnDelete(DeleteBehavior.Restrict);
            e.HasIndex(x => new { x.PlanId, x.ReadDate });
            e.HasIndex(x => x.ServerUpdatedAt);
        });
    }
}
