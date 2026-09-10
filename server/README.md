# ICanRead.Api

Phase 2 server: accounts and sync. The PDF never reaches here — only book
metadata, plans and progress.

## What exists

| Area | State |
|---|---|
| Solution, four projects + tests | done |
| Domain entities + EF Core mapping | done |
| `InitialSchema` migration, on PostgreSQL | done |
| Email/password auth: register · login · refresh · logout · `GET /api/me` | done |
| Sync: `GET /api/sync/pull` · `POST /api/sync/push` · `POST /api/books/lookup-by-hash` | done |
| Flutter `SyncEngine` draining `sync_outbox` | done |
| Sign-in / register screens, guest-data adoption | done |
| Google Sign-In: `POST /api/auth/google`, ID token verified against Google's keys | done |
| Password reset: `POST /api/auth/forgot-password` · `POST /api/auth/reset-password`, code emailed over SMTP | done |
| Rate limiting on `/api/auth/*` | done |
| Account deletion: `POST /api/me/delete` | done |

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

Needs a PostgreSQL 17 on `localhost:5433`. In Docker, which is also what the
tests expect:

```bash
docker run -d --name icanread-pg -e POSTGRES_PASSWORD=devpassword \
  -p 5433:5432 postgres:17
```

Port 5433 rather than 5432, so it cannot collide with a Postgres already
installed on the machine.

Then supply a signing key. `appsettings.Development.json` is gitignored, so a
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
dotnet run --project src/ICanRead.Api
```

Migrations are applied on startup, so there is no `dotnet ef database update`
step. `GET /health` answers `{"status":"ok"}` once it is up.

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

Sending goes over **SMTP via MailKit**, not a provider's own HTTP API: SMTP is
the one interface every provider speaks, so moving from Gmail to a company relay
is a configuration change rather than a rewrite.

```jsonc
// server/src/ICanRead.Api/appsettings.Development.json
{
  "EmailSettings": {
    "SmtpServer": "smtp.gmail.com",
    "Port": 587,
    "SenderEmail": "you@gmail.com",
    "Password": "the sixteen-character app password"
  }
}
```

On Gmail that password must be an **app password** from an account with 2FA on;
the account's own password does not authenticate against SMTP at all. The
connection is forced to STARTTLS rather than negotiated — `Auto` falls back to
an unencrypted session when a server does not advertise TLS, and the password
would go out in the clear.

Leave the section empty in Development and the code is written to the console
instead, so a fresh clone can walk the whole flow without a mail account.
Outside Development, startup fails without it: a server that cannot send mail
cannot reset a password, and a reader who cannot reset a password has lost their
library.

### Deleting an account

`POST /api/me/delete` closes the account and removes everything it holds. A real
delete, not a flag: Google Play requires an in-app way to delete an account, and
a row merely marked as gone is not a deletion.

**A valid access token is not proof enough.** It lasts half an hour, so a phone
left unlocked on a table is a valid access token, and this is the one call that
cannot be undone. The caller re-proves the account is theirs the same way they
got in: the password if the account has one, and a fresh Google ID token —
matched on the subject, never the email — if Google is the only way in.

The reading log is deleted explicitly, before the account. Its foreign key is
`Restrict` on purpose, so it is the one table a cascade would leave behind, and
leaving it would keep a deleted reader's history.

The PDFs are not part of this, because they were never here. The app leaves the
books on the phone alone too, and returns that library to being a guest library
— the files are the reader's own, and wiping a device is not what "delete my
account" asked for.

## Tests

```bash
dotnet test
```

They drive the real API over HTTP against a **real Postgres** — the container
above — in a database called `ICanRead_Test` that is dropped and rebuilt from
the migrations on every run. Deliberately not SQLite or the in-memory provider:
the schema depends on things only the real provider does the same way — a
partial unique index, the `DateOnly` mapping, `ExecuteUpdateAsync` — and a test
passing against a substitute would not tell us the migration works.

## Deploying to Render

`render.yaml` at the repository root describes the whole thing: one Docker web
service and one managed Postgres. Point Render at the repo as a Blueprint and it
reads that file — there is nothing to configure in the dashboard except the
three secrets it will ask for.

```
New → Blueprint → pick this repository
```

Render then prompts for the values marked `sync: false`, which are the SMTP
account:

| Variable | Value |
|---|---|
| `EmailSettings__SmtpServer` | `smtp.gmail.com` |
| `EmailSettings__SenderEmail` | the address codes are sent from |
| `EmailSettings__Password` | that account's app password |

Double underscore, not colon: it is how the configuration system spells a
nested key in an environment variable. **All three are required** — outside
Development the server refuses to start without mail, because an account that
cannot be recovered is a library lost. `Jwt__SigningKey` is generated by Render
and `ConnectionStrings__Default` comes from the database, so neither needs
touching.

Once it is up, `https://<service>.onrender.com/health` answers
`{"status":"ok"}`, and the app is built against it:

```bash
flutter build apk --dart-define=API_BASE_URL=https://<service>.onrender.com
```

### What the free plan costs

**The service sleeps after 15 minutes of no traffic**, and the next request
waits out a cold start — with a migration check on top of it. Sync is a
background drain that retries, so a reader sees nothing; a sign-in on a sleeping
service is the case that feels broken.

**Free Postgres is deleted after 30 days.** Render does not extend it and the
date is fixed from creation. Nothing in the app depends on the server — every
library is on its own phone — so what is lost is sync and every account, not
anybody's books. Moving to a paid plan before that date is the only thing that
keeps them.

### Migrations run at startup

The container applies pending migrations before it serves anything. A managed
host gives no shell to run `dotnet ef database update` from, and the
alternative — a new deploy answering requests against last week's schema — is
worse than what this costs. What it costs is that two instances starting at once
would migrate at once; this runs as one, and scaling out is where that stops
being true.

### Rate limiting behind a proxy

`/api/auth/*` is capped per address, and behind Render every request arrives
from Render's own address. `UseForwardedHeaders` is what recovers the caller's:
without it every reader would share a single bucket of ten requests a minute,
and the first person to mistype a password would lock out the rest.

**That address is only as honest as the caller.** Render appends to
`X-Forwarded-For` rather than replacing it, so anyone can put whatever they like
at the front of the list and get a fresh bucket per request. The limit is a
speed bump in front of a script working through six digits, not a defence
against someone who knows to rotate a header — the code's own hedges (fifteen
minutes, newest-only, five wrong tries) are what actually bound that attack. If
a trustworthy client-IP header is ever confirmed for this host, the fix is the
`ForwardedHeadersOptions` block in `Program.cs` and nothing else.

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
- **PostgreSQL, not SQL Server.** The schema was SQL Server first and the choice
  was made by the host: Render offers no managed SQL Server, and the ways round
  that are a second provider to pay for and administer, or a container needing
  2 GB of memory with no managed backups. Nothing here wanted anything SQL
  Server does and Postgres does not — one filtered index changed its quoting,
  and Postgres treats NULLs as distinct in a unique index anyway.
- **The connection string is accepted in either form.** Managed hosts publish
  `postgresql://user:pass@host/db` and Npgsql cannot parse it, so
  `PostgresConnectionString` translates it and passes a keyword string through
  untouched. Whoever deploys pastes what the dashboard gave them.
