# I Can Read — أقدر أقرأ

Structured reading plans for PDF books, modelled on the idea of a ختمة: pick a
goal ("finish in 30 days" or "15 pages a day"), and the app works out the daily
portion, splits it across reading sessions, reminds you at the times you choose,
and tracks how you are doing.

**The PDF never leaves the device.** The account stores book metadata, plans and
progress only. Signing in on a new phone brings everything back except the
files, which you re-select yourself — matched by content hash so they relink to
the right plan.

## Status

Phase 1 (offline-only app) is in progress. No account or server yet.

| Area | State |
|---|---|
| Plan arithmetic (`lib/core/planning/plan_math.dart`) | Done, 46 tests |
| Local database (Drift) | Done, 16 tests |
| PDF import, file store, hashing | Done, 19 unit + 5 device tests |
| Add-book flow, duplicate detection, relink | Done, 12 tests |
| Library shelves | Done |
| Arabic/English UI with RTL | Done, 5 tests |
| Plan wizard (create and edit a goal) | Done, 18 unit + 8 widget tests |
| Reading sessions (splitting the daily portion) | Done, 18 unit + 7 widget tests |
| Reminders (local notifications), incl. tap → book | Done, 20 unit + 9 tests, 9 on-device tests |
| Pausing a plan | Data + arithmetic done, 10 tests; no UI until book detail |
| Today (the day's portion across every book) | Done, 14 unit + 8 widget tests |
| Reader, restricted to the day's portion | Done, 16 unit + 5 on-device tests |
| Book detail, stats | Not started |
| Account + sync (.NET 10 + SQL Server) | Phase 2 |

### Sample books for manual testing

```sh
dart run tool/make_sample_pdf.dart 240 sample-book.pdf
adb push sample-book.pdf /sdcard/Download/
```

## Layout

```
app/                   Flutter application
  lib/core/            planning · db · files · notifications · settings · theme · router
  lib/features/        library · add_book · plan · sessions · today · reader · stats · settings
  lib/l10n/            app_ar.arb · app_en.arb
  test/                unit and widget tests
  integration_test/    tests that need a real device
server/                .NET solution (Phase 2, not created yet)
```

## Running it

```sh
cd app
flutter pub get
flutter test                                   # unit + widget tests
flutter run -d <device>
```

After changing anything under `lib/core/db/`, regenerate the Drift code:

```sh
dart run build_runner build
```

After editing the ARB files:

```sh
flutter gen-l10n
```

### Tests that need a device

`integration_test/` exercises the real PDF engine, which needs platform plugins
the host test VM does not provide. Start an emulator, then:

```sh
flutter test integration_test/pdf_engine_test.dart -d <device>
flutter test integration_test/reminder_channel_test.dart -d <device>
flutter test integration_test/portion_reader_test.dart -d <device>
```

`reminder_channel_test.dart` is the only proof the system scheduler actually
accepts our reminders — everything under `test/reminder_*.dart` proves we asked
for the right things, not that they were taken.

### Checking reminders by hand

Nothing in the test suite proves a notification actually arrives — that needs a
real device. On one:

1. Create a plan and set a session a couple of minutes ahead.
2. Accept the notification prompt shown when you tap **Start the plan**.
3. Background the app and wait. Reminders are scheduled *inexactly*, so it may
   land up to a few minutes late; that is by design.
4. Reboot the phone and confirm the reminder still fires the next day — that is
   what `ScheduledNotificationBootReceiver` in the manifest is for.

## Environment notes

Things that are not obvious and cost time to rediscover:

- **`kotlin.incremental=false`** in `android/gradle.properties`. Kotlin's
  incremental caches fail to close on this machine and break the build outright.
- **Core library desugaring** is enabled in `android/app/build.gradle.kts`
  because `flutter_local_notifications` requires it.
- **`pdfrx` is pinned below 2.5.0**, which needs Flutter ≥ 3.47. This project
  targets 3.44.4.
- **`intl` is pinned to 0.20.2** by `flutter_localizations`.
- **`permission_handler` is deliberately absent.** Version 13 requires Android
  SDK 37; `flutter_local_notifications` requests its own permissions anyway.
- **Windows desktop does not build** — the `flutter_local_notifications` Windows
  plugin needs ATL headers that the installed Visual Studio Build Tools lack.
  Android and iOS are the targets; use an Android device for anything that needs
  a real platform.
- **iOS backup exclusion is written but unverified.** `BookFileStore.open()`
  creates `books/` and asks `ios/Runner/AppDelegate.swift`, over the
  `icanread/book_files` method channel, to set `isExcludedFromBackup` on it —
  the iOS counterpart of `allowBackup="false"`. None of it has ever been
  compiled: this repo is developed on Windows. **Before shipping iOS, on a Mac:**
  1. Confirm the Runner target builds — the channel is registered from
     `didInitializeImplicitFlutterEngine`, and `registrar(forPlugin:)` on the
     implicit engine's registry is the part most likely to need adjusting.
  2. Import a book, then check the flag actually landed. In the simulator:
     `xattr -l ~/Library/Developer/CoreSimulator/Devices/*/data/Containers/Data/Application/*/Documents/books`
     should list `com.apple.metadata:com_apple_backup_excludeItem`.
  3. Confirm a launch that fails to set it does not stop the app — the Dart side
     swallows the error with a `debugPrint` and asserts only in debug.

## Conventions

- Page numbers are **always physical 1-based indices** into the PDF.
  `Book.pageLabelOffset` exists only to display the printed number.
- File paths are stored **relative** to the app documents directory. The iOS
  container path contains a UUID that changes on reinstall, so absolute paths
  rot.
- The UI is bilingual and mirrors. Use `EdgeInsetsDirectional`,
  `AlignmentDirectional` and `*Start`/`*End` — never `left`/`right`.
- Missing a day **extends the finish date**; the daily quota never grows.
- **A reading day starts at 04:00, not midnight.** Someone reading at one in
  the morning is finishing the day they are still awake in.
- **Pausing is not the same as missing days.** Missing days the plan absorbs on
  its own. A pause is deliberate, so its days are subtracted before the app
  judges anyone as behind (`ReadingPlans.pausedDays`).
- **Nothing is backed up.** `android:allowBackup="false"` — auto-backup would
  copy the books to the reader's Google Drive. On iOS the `books/` directory is
  flagged `isExcludedFromBackup` for the same reason (see Environment notes:
  written, not yet verified on a Mac).
- **Today is not driven by the clock.** "This session" is the earliest session
  not yet finished, not the one nearest to now, so a portion missed at
  breakfast is still waiting at midnight.
- **Progress is recorded when the reader says so**, never on scroll position.
  Flipping ahead to check a footnote is not reading.
- **The reader shows the day's portion and nothing else.** Opening on the right
  page of a whole book leaves it an eight-hundred-page object; the point of the
  plan is that today is finishable. `portionLayout` parks the other pages far
  below the document, outside the scroll bounds.
  `pdfrx` must also be given `calculateCurrentPageNumber`: its own answer falls
  back to guessing from scroll percentage across the whole book once a layout
  is not uniform, and reports page 20 of 20 while page 8 is on screen.
- **"Keep reading" opens the rest of the plan for that sitting only.** Reading
  past the portion is allowed and counted — it pulls the finish date closer —
  but the next time the book is opened it is bounded again. The button appears
  only on the last page of the portion, where it answers a question the reader
  is actually asking.
