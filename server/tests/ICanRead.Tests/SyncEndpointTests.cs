using System.Net;
using System.Net.Http.Headers;
using System.Net.Http.Json;
using ICanRead.Application.Auth;
using ICanRead.Application.Sync;

namespace ICanRead.Tests;

[Collection(ApiCollection.Name)]
public class SyncEndpointTests(ApiFactory factory)
{
    private readonly ApiFactory _factory = factory;

    private static readonly DateTimeOffset Jan1 = new(2026, 1, 1, 0, 0, 0, TimeSpan.Zero);
    private static readonly DateOnly Jan1Date = new(2026, 1, 1);

    /// <summary>A signed-in client, on a brand new account.</summary>
    private async Task<HttpClient> NewReaderAsync()
    {
        var client = _factory.CreateClient();
        var response = await client.PostAsJsonAsync("/api/auth/register",
            new RegisterRequest($"reader-{Guid.NewGuid():N}@example.com", "correct horse battery", null));

        response.EnsureSuccessStatusCode();
        var auth = (await response.Content.ReadFromJsonAsync<AuthResponse>())!;
        client.DefaultRequestHeaders.Authorization =
            new AuthenticationHeaderValue("Bearer", auth.AccessToken);
        return client;
    }

    private static BookDto NewBook(Guid id, string title = "The Muqaddimah", DateTimeOffset? updatedAt = null) =>
        new(id, title, "Ibn Khaldun", 240, 0, "Reading", Jan1, updatedAt ?? Jan1, null);

    private static PlanDto NewPlan(
        Guid id, Guid bookId, int lastPageRead = 0, DateTimeOffset? updatedAt = null, int pagesPerDay = 15) =>
        new(id, bookId, "ByPagesPerDay", 1, 240, Jan1Date, new DateOnly(2026, 1, 16),
            pagesPerDay, lastPageRead, true, null, 0, Jan1, updatedAt ?? Jan1);

    private static async Task<SyncPushResponse> PushAsync(HttpClient client, SyncPayload payload)
    {
        var response = await client.PostAsJsonAsync("/api/sync/push", payload);
        response.EnsureSuccessStatusCode();
        return (await response.Content.ReadFromJsonAsync<SyncPushResponse>())!;
    }

    private static async Task<SyncPullResponse> PullAsync(HttpClient client, DateTimeOffset? since = null)
    {
        var url = since is null
            ? "/api/sync/pull"
            : $"/api/sync/pull?since={Uri.EscapeDataString(since.Value.ToString("O"))}";
        var response = await client.GetAsync(url);
        response.EnsureSuccessStatusCode();
        return (await response.Content.ReadFromJsonAsync<SyncPullResponse>())!;
    }

    [Fact]
    public async Task Sync_needs_a_token()
    {
        var anonymous = _factory.CreateClient();

        Assert.Equal(HttpStatusCode.Unauthorized, (await anonymous.GetAsync("/api/sync/pull")).StatusCode);
        Assert.Equal(HttpStatusCode.Unauthorized,
            (await anonymous.PostAsJsonAsync("/api/sync/push", new SyncPayload())).StatusCode);
    }

    [Fact]
    public async Task A_push_comes_back_on_the_next_pull()
    {
        var client = await NewReaderAsync();
        var bookId = Guid.NewGuid();
        var planId = Guid.NewGuid();
        var logId = Guid.NewGuid();

        var push = await PushAsync(client, new SyncPayload
        {
            Books = [NewBook(bookId)],
            Plans = [NewPlan(planId, bookId)],
            Sessions = [new SessionDto(Guid.NewGuid(), planId, 0, 20 * 60, 15, 127, true, Jan1, null)],
            LogEntries = [new LogEntryDto(logId, planId, null, Jan1Date, 1, 15, 15, 600, Jan1)]
        });

        Assert.Empty(push.Rejected);
        Assert.Equal(4, push.Applied);

        var pull = await PullAsync(client);
        Assert.Equal(bookId, Assert.Single(pull.Changes.Books).Id);
        Assert.Equal(planId, Assert.Single(pull.Changes.Plans).Id);
        Assert.Single(pull.Changes.Sessions);
        Assert.Equal(logId, Assert.Single(pull.Changes.LogEntries).Id);
    }

    [Fact]
    public async Task One_reader_never_sees_another_readers_books()
    {
        var alice = await NewReaderAsync();
        var bob = await NewReaderAsync();
        var bookId = Guid.NewGuid();

        await PushAsync(alice, new SyncPayload { Books = [NewBook(bookId, "Alice's book")] });

        var bobsPull = await PullAsync(bob);
        Assert.Empty(bobsPull.Changes.Books);
    }

    [Fact]
    public async Task A_push_cannot_overwrite_a_book_belonging_to_someone_else()
    {
        var alice = await NewReaderAsync();
        var bob = await NewReaderAsync();
        var bookId = Guid.NewGuid();

        await PushAsync(alice, new SyncPayload { Books = [NewBook(bookId, "Alice's book")] });

        // Bob knows the id and pushes over it.
        var push = await PushAsync(bob, new SyncPayload
        {
            Books = [NewBook(bookId, "Bob's book", updatedAt: Jan1.AddYears(1))]
        });

        Assert.Equal(bookId, Assert.Single(push.Rejected));
        Assert.Equal(0, push.Applied);

        var alicesPull = await PullAsync(alice);
        Assert.Equal("Alice's book", Assert.Single(alicesPull.Changes.Books).Title);
    }

    [Fact]
    public async Task A_plan_for_a_book_the_caller_does_not_own_is_rejected()
    {
        var alice = await NewReaderAsync();
        var bob = await NewReaderAsync();
        var bookId = Guid.NewGuid();
        var planId = Guid.NewGuid();

        await PushAsync(alice, new SyncPayload { Books = [NewBook(bookId)] });

        var push = await PushAsync(bob, new SyncPayload { Plans = [NewPlan(planId, bookId)] });

        Assert.Equal(planId, Assert.Single(push.Rejected));
        Assert.Empty((await PullAsync(bob)).Changes.Plans);
    }

    [Fact]
    public async Task The_newer_edit_of_a_book_wins()
    {
        var client = await NewReaderAsync();
        var bookId = Guid.NewGuid();

        await PushAsync(client, new SyncPayload
        {
            Books = [NewBook(bookId, "First title", updatedAt: Jan1.AddDays(5))]
        });

        // An older edit arrives late, from a device that was offline.
        var stale = await PushAsync(client, new SyncPayload
        {
            Books = [NewBook(bookId, "Stale title", updatedAt: Jan1.AddDays(1))]
        });
        Assert.Equal(1, stale.Ignored);
        Assert.Equal("First title", Assert.Single((await PullAsync(client)).Changes.Books).Title);

        // A newer one takes.
        await PushAsync(client, new SyncPayload
        {
            Books = [NewBook(bookId, "Newest title", updatedAt: Jan1.AddDays(9))]
        });
        Assert.Equal("Newest title", Assert.Single((await PullAsync(client)).Changes.Books).Title);
    }

    [Fact]
    public async Task Progress_takes_the_furthest_page_not_the_latest_write()
    {
        var client = await NewReaderAsync();
        var bookId = Guid.NewGuid();
        var planId = Guid.NewGuid();

        await PushAsync(client, new SyncPayload
        {
            Books = [NewBook(bookId)],
            Plans = [NewPlan(planId, bookId, lastPageRead: 120, updatedAt: Jan1.AddDays(5))]
        });

        // A phone that was offline pushes a stale row — older, and behind on
        // progress. It must not drag the reader back to page 40.
        await PushAsync(client, new SyncPayload
        {
            Plans = [NewPlan(planId, bookId, lastPageRead: 40, updatedAt: Jan1.AddDays(1))]
        });
        Assert.Equal(120, Assert.Single((await PullAsync(client)).Changes.Plans).LastPageRead);

        // Even a *newer* write cannot move progress backwards.
        await PushAsync(client, new SyncPayload
        {
            Plans = [NewPlan(planId, bookId, lastPageRead: 60, updatedAt: Jan1.AddDays(9))]
        });
        Assert.Equal(120, Assert.Single((await PullAsync(client)).Changes.Plans).LastPageRead);
    }

    [Fact]
    public async Task A_stale_row_still_contributes_its_progress()
    {
        var client = await NewReaderAsync();
        var bookId = Guid.NewGuid();
        var planId = Guid.NewGuid();

        await PushAsync(client, new SyncPayload
        {
            Books = [NewBook(bookId)],
            Plans = [NewPlan(planId, bookId, lastPageRead: 30, pagesPerDay: 15, updatedAt: Jan1.AddDays(5))]
        });

        // Older settings, but this device read further. The settings lose and
        // the progress still counts — a phone can be behind on the plan and
        // ahead in the book at the same time.
        await PushAsync(client, new SyncPayload
        {
            Plans = [NewPlan(planId, bookId, lastPageRead: 90, pagesPerDay: 5, updatedAt: Jan1.AddDays(1))]
        });

        var plan = Assert.Single((await PullAsync(client)).Changes.Plans);
        Assert.Equal(90, plan.LastPageRead);
        Assert.Equal(15, plan.PagesPerDay);
    }

    [Fact]
    public async Task The_log_is_append_only_and_a_repeat_push_changes_nothing()
    {
        var client = await NewReaderAsync();
        var bookId = Guid.NewGuid();
        var planId = Guid.NewGuid();
        var logId = Guid.NewGuid();

        await PushAsync(client, new SyncPayload
        {
            Books = [NewBook(bookId)],
            Plans = [NewPlan(planId, bookId)]
        });

        var entry = new LogEntryDto(logId, planId, null, Jan1Date, 1, 15, 15, 600, Jan1);
        await PushAsync(client, new SyncPayload { LogEntries = [entry] });

        // The same id again, with different numbers — a retry, or a device
        // that never saw the acknowledgement.
        var repeat = await PushAsync(client, new SyncPayload
        {
            LogEntries = [entry with { PagesRead = 999, ToPage = 999 }]
        });

        Assert.Equal(1, repeat.Ignored);
        var stored = Assert.Single((await PullAsync(client)).Changes.LogEntries);
        Assert.Equal(15, stored.PagesRead);
    }

    [Fact]
    public async Task Two_devices_reading_the_same_day_both_keep_their_entries()
    {
        var client = await NewReaderAsync();
        var bookId = Guid.NewGuid();
        var planId = Guid.NewGuid();

        await PushAsync(client, new SyncPayload
        {
            Books = [NewBook(bookId)],
            Plans = [NewPlan(planId, bookId)]
        });

        // The phone and the tablet each logged a stretch while offline.
        await PushAsync(client, new SyncPayload
        {
            LogEntries = [new LogEntryDto(Guid.NewGuid(), planId, null, Jan1Date, 1, 15, 15, 600, Jan1)]
        });
        await PushAsync(client, new SyncPayload
        {
            LogEntries = [new LogEntryDto(Guid.NewGuid(), planId, null, Jan1Date, 16, 30, 15, 700, Jan1)]
        });

        // Both survive. Last-write-wins here would have thrown one away.
        Assert.Equal(2, (await PullAsync(client)).Changes.LogEntries.Count);
    }

    [Fact]
    public async Task Pull_since_a_cursor_returns_only_what_changed_after_it()
    {
        var client = await NewReaderAsync();
        var first = Guid.NewGuid();

        await PushAsync(client, new SyncPayload { Books = [NewBook(first, "First")] });
        var cursor = (await PullAsync(client)).ServerTime;

        var second = Guid.NewGuid();
        await PushAsync(client, new SyncPayload { Books = [NewBook(second, "Second")] });

        var delta = await PullAsync(client, cursor);
        Assert.Equal("Second", Assert.Single(delta.Changes.Books).Title);
    }

    [Fact]
    public async Task The_cursor_is_the_servers_clock_not_the_devices()
    {
        var client = await NewReaderAsync();

        // A device whose clock is a year slow. Its rows carry last year's
        // UpdatedAt, but they were written to the server now — so a pull from
        // a moment ago must still deliver them.
        var before = (await PullAsync(client)).ServerTime;
        await PushAsync(client, new SyncPayload
        {
            Books = [NewBook(Guid.NewGuid(), "Slow clock", updatedAt: Jan1.AddYears(-1))]
        });

        var delta = await PullAsync(client, before);
        Assert.Equal("Slow clock", Assert.Single(delta.Changes.Books).Title);
    }

    [Fact]
    public async Task A_new_device_with_no_cursor_gets_everything()
    {
        var client = await NewReaderAsync();
        var bookId = Guid.NewGuid();

        await PushAsync(client, new SyncPayload
        {
            Books = [NewBook(bookId)],
            Plans = [NewPlan(Guid.NewGuid(), bookId)]
        });

        var fresh = await PullAsync(client);
        Assert.Single(fresh.Changes.Books);
        Assert.Single(fresh.Changes.Plans);
    }

    [Fact]
    public async Task A_deleted_book_travels_as_a_tombstone_rather_than_vanishing()
    {
        var client = await NewReaderAsync();
        var bookId = Guid.NewGuid();

        await PushAsync(client, new SyncPayload { Books = [NewBook(bookId)] });
        await PushAsync(client, new SyncPayload
        {
            Books = [NewBook(bookId) with { UpdatedAt = Jan1.AddDays(2), DeletedAt = Jan1.AddDays(2) }]
        });

        // Still delivered, with its DeletedAt set — otherwise the other device
        // would never learn the book was removed.
        var book = Assert.Single((await PullAsync(client)).Changes.Books);
        Assert.NotNull(book.DeletedAt);
    }

    [Fact]
    public async Task A_replaced_session_comes_back_as_a_tombstone_not_a_second_reminder()
    {
        var client = await NewReaderAsync();
        var bookId = Guid.NewGuid();
        var planId = Guid.NewGuid();
        var oldSession = Guid.NewGuid();
        var newSession = Guid.NewGuid();

        await PushAsync(client, new SyncPayload
        {
            Books = [NewBook(bookId)],
            Plans = [NewPlan(planId, bookId)],
            Sessions = [new SessionDto(oldSession, planId, 0, 20 * 60, 15, 127, true, Jan1, null)]
        });

        // What the device sends when the reader moves the reminder to 21:00:
        // the whole list is rebuilt, so the old row is retired and a new one
        // takes its place.
        await PushAsync(client, new SyncPayload
        {
            Sessions =
            [
                new SessionDto(oldSession, planId, 0, 20 * 60, 15, 127, true,
                    Jan1.AddDays(1), Jan1.AddDays(1)),
                new SessionDto(newSession, planId, 0, 21 * 60, 15, 127, true,
                    Jan1.AddDays(1), null)
            ]
        });

        var sessions = (await PullAsync(client)).Changes.Sessions;

        // Both rows come down. The retired one carries its DeletedAt, which is
        // the only thing that stops the other phone scheduling two reminders.
        Assert.Equal(2, sessions.Count);
        Assert.NotNull(sessions.Single(s => s.Id == oldSession).DeletedAt);
        Assert.Null(sessions.Single(s => s.Id == newSession).DeletedAt);
    }

    [Fact]
    public async Task Lookup_by_hash_finds_the_readers_own_book()
    {
        var client = await NewReaderAsync();
        var bookId = Guid.NewGuid();
        var hash = new string('a', 64);

        await PushAsync(client, new SyncPayload
        {
            Books = [NewBook(bookId)],
            Fingerprints = [new FingerprintDto(Guid.NewGuid(), bookId, hash, 240, 1024, "book.pdf", Jan1)]
        });

        var response = await client.PostAsJsonAsync("/api/books/lookup-by-hash",
            new LookupByHashRequest(hash.ToUpperInvariant()));
        response.EnsureSuccessStatusCode();
        var found = await response.Content.ReadFromJsonAsync<LookupByHashResponse>();

        // Case-insensitive: the client may send the hash either way.
        Assert.Equal(bookId, found!.Book!.Id);
    }

    [Fact]
    public async Task Lookup_by_hash_will_not_reveal_another_readers_book()
    {
        var alice = await NewReaderAsync();
        var bob = await NewReaderAsync();
        var hash = new string('b', 64);
        var bookId = Guid.NewGuid();

        await PushAsync(alice, new SyncPayload
        {
            Books = [NewBook(bookId)],
            Fingerprints = [new FingerprintDto(Guid.NewGuid(), bookId, hash, 240, 1024, null, Jan1)]
        });

        // Bob has the very same PDF. That is not a reason to tell him Alice
        // has it, so the answer is simply "no book of yours".
        var response = await bob.PostAsJsonAsync("/api/books/lookup-by-hash",
            new LookupByHashRequest(hash));
        var found = await response.Content.ReadFromJsonAsync<LookupByHashResponse>();

        Assert.Null(found!.Book);
    }
}
