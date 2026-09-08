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
| Google Sign-In: `POST /api/auth/google`, ID token verified against Google's keys | done |
| Password reset: `POST /api/auth/forgot-password` · `POST /api/auth/reset-password`, code emailed via SendGrid | server done, app screens pending |
| Rate limiting on `/api/auth/*` | done |

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

### Google sign-in

`Google:ClientId` in `appsettings.json` is the **Web** OAuth client ID, and it
is committed on purpose: the same string ships inside the APK, and it names the
Google Cloud project rather than authorising anything. There is no client
secret — this server verifies ID tokens rather than trading authorization
codes. Leave the value empty to turn the feature off; the button disappears
with it.

The Android OAuth client is what lets a device get a token at all, and it never
appears in code — Google matches it by package name and signing certificate.
One has to exist in the same Cloud project for each certificate you build with,
`com.icanread.i_can_read` plus that keystore's SHA-1. A missing or mismatched
one is not an error you can see from here: Google signs the reader in and hands
back a null ID token, which reaches the app as a plain "sign-in failed".

**If every token is rejected as expired, check the clock before the config.**
Google's ID tokens live exactly one hour, so a server whose clock is even
slightly fast refuses tokens that are seconds old. The `GoogleTokenVerifier`
warning prints `iat`, `exp` and the server's `now` for this reason — when `exp`
is `iat + 3600` and `now` is just past it, the machine is wrong, not the token.
Compare `date -u` against a real source and fix the clock.

`Google:ClockToleranceMinutes` exists for that situation and only that one. It
widens the expiry check by that many minutes, which is a real hole while it is
set, so startup refuses a non-zero value outside Development. It is a crutch
for a broken clock, not configuration — delete it once the clock is right.

### Password reset

A reader who forgot their password asks for a code at
`POST /api/auth/forgot-password`, then spends it at
`POST /api/auth/reset-password` along with the new password.

**A six-digit code, not a link.** A link needs somewhere to land, and this app
has no website and no deep-link setup — a code is something the phone can accept
on the screen the reader is already looking at.

Six digits is only a million guesses, so the code is hedged from four
directions: it lives fifteen minutes, only the newest one per account is live,
five wrong tries destroy it, and `/api/auth/*` is rate limited by address. Only
the SHA-256 of the code is stored.

`forgot-password` answers `204` for every address, whether or not it has an
account, and swallows mail failures for the same reason — a `500` on a send
failure would answer "does this address have an account here?" precisely,
because nothing is sent for one that does not. Failures go to the log instead.

Sending needs a SendGrid API key and a verified sender address:

```jsonc
// server/src/ICanRead.Api/appsettings.Development.json
{
  "SendGrid": { "ApiKey": "SG.…", "FromAddress": "no-reply@yourdomain" }
}
```

Leave `ApiKey` empty in Development and the code is written to the console
instead, so a fresh clone can walk the whole flow without an account. Outside
Development, startup fails without it: a server that cannot send mail cannot
reset a password, and a reader who cannot reset a password has lost their
library.

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
