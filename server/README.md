# ICanRead.Api

Phase 2 server: accounts and sync. The PDF never reaches here — only book
metadata, plans and progress.

## What exists

| Area | State |
|---|---|
| Solution, four projects + tests | done |
| Domain entities + EF Core mapping | done |
| `InitialSchema` migration, applied to `.\SQLEXPRESS01` | done |
| Email/password auth: register · login · refresh · logout · `GET /api/me` | done |
| Sync: `GET /api/sync/pull` · `POST /api/sync/push` · `POST /api/books/lookup-by-hash` | done |
| Flutter `SyncEngine` draining `sync_outbox` | done |
| Sign-in / register screens, guest-data adoption | done |
| Google Sign-In | not started — needs a `serverClientId` from Google Cloud |

## How sync works

`pull?since=<serverTime>` returns everything of yours that changed since that
cursor; `push` sends a payload of the same shape back. A new device omits
`since` and gets everything.

**The cursor is this server's clock, not the device's.** Every synced row
carries a `ServerUpdatedAt` that only this server writes. The client's own
`UpdatedAt` still decides conflicts — it says when the reader made a change,
which is the right question for last-write-wins — but it is the wrong thing to
filter a pull on: two phones whose clocks disagree by a few minutes is
ordinary, and rows from the slow one would be skipped forever.

Pull uses `>=` rather than `>`, so the boundary row is delivered twice. That is
deliberate and cheap: every merge is idempotent, and `>` would drop a row
written in the same tick as the cursor.

Three merge rules, because the three kinds of row mean different things:

| Rows | Rule |
|---|---|
| books, plans, sessions | last write wins on the client's `UpdatedAt` |
| `LastPageRead` | **maximum**, never the latest — reading only moves forward, and it is merged even when the rest of the row loses |
| `reading_log` | **append-only**, merged by id; an id already present is left exactly as it is |

Removals are tombstones, never real deletes — books and sessions both carry a
`DeletedAt`. Sessions need one because the client rebuilds the whole reminder
list whenever a time is edited: a row that simply vanished from a device cannot
be described in a push, so the copy here would survive and be handed back as a
duplicate reminder.

Timestamps arrive as UTC with an explicit `Z`, and the two calendar-day fields
(`StartDate`, `ReadDate`) as a bare `YYYY-MM-DD`. The client is careful never to
route a *date* through UTC: local midnight is the previous day anywhere east of
Greenwich, and a day is the unit this whole app counts in.

Ownership is taken from the token on every endpoint. A push naming a book or
plan the caller does not own is reported in `rejected` rather than dropped
silently, so a client bug cannot look like a working sync.

## Running it

Needs the local `.\SQLEXPRESS01` instance (SQL Server 2019+) reachable with
Windows auth. Nothing else.

First, supply a signing key. `appsettings.Development.json` is gitignored, so a
fresh clone has none and the app refuses to start until it does — deliberately,
rather than falling back to a default key that would end up in production:

```jsonc
// server/src/ICanRead.Api/appsettings.Development.json
{
  "Jwt": { "SigningKey": "any-local-string-of-at-least-32-bytes-long" }
}
```

Then:

```bash
cd server
dotnet ef database update --project src/ICanRead.Infrastructure --startup-project src/ICanRead.Api
dotnet run --project src/ICanRead.Api
```

`GET /health` answers `{"status":"ok"}` once it is up.

## Tests

```bash
dotnet test
```

They drive the real API over HTTP against a **real SQL Server**, in a database
called `ICanRead_Test` that is dropped and rebuilt from the migrations on every
run. Deliberately not SQLite or the in-memory provider: the schema depends on
things only the real provider does the same way — a filtered unique index, the
`DateOnly` mapping, `ExecuteUpdateAsync` — and a test passing against a
substitute would not tell us the migration works.

## Decisions worth knowing

- **No `BookStatus.Archived`.** The client dropped it in favour of pausing the
  plan. Adding it back here would let a device sync a status the app cannot
  draw.
- **No OpenAPI document.** `Microsoft.AspNetCore.OpenApi` pulls in
  Microsoft.OpenApi 2.x, whose whole line currently carries a high-severity
  advisory (GHSA-v5pm-xwqc-g5wc); 3.x does not compile against the ASP.NET Core
  10 source generator. There is one consumer of this API and it lives in this
  repo. Re-add when a patched 2.x ships.
- **Refresh tokens are opaque random bytes, stored hashed**, and rotate on every
  use. Presenting a spent token revokes every live token for that account, on
  the assumption that a replayed token means a captured one.
- **`reading_log` deletes are `Restrict`, not `Cascade`.** The log is
  append-only and is the record of what the reader actually did; losing it must
  never be a side effect of tidying up a book.
- **The signing key is validated on startup**, so a misconfigured deployment
  fails at boot instead of at the first sign-in. The key in
  `appsettings.Development.json` is for local development only.
