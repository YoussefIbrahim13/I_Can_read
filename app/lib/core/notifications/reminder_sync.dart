import 'dart:async';
import 'dart:ui';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/app_localizations.dart';
import '../db/app_database.dart';
import '../settings/app_settings.dart';
import 'reminder.dart';
import 'reminder_channel.dart';

/// The sessions that deserve a reminder right now, straight from the database.
final dueRemindersProvider = StreamProvider<List<ReminderRequest>>((ref) {
  return ref
      .watch(appDatabaseProvider)
      .watchDueReminders()
      .map(
        (rows) => [
          for (final row in rows)
            ReminderRequest(
              planId: row.plan.id,
              bookId: row.book.id,
              bookTitle: row.book.title,
              ordinal: row.session.ordinal,
              minutes: row.session.timeOfDayMinutes,
              pages: row.session.pagesShare,
              daysOfWeek: row.session.daysOfWeek,
              isEnabled: row.session.isEnabled,
            ),
        ],
      );
});

/// Keeps the operating system's idea of the reader's reminders in step with
/// the database.
///
/// There is no incremental path: every change rewrites the whole set. Reminders
/// are few — a handful of books at a handful of times — and a full rewrite is
/// the only version of this that cannot drift out of step after a crash, a
/// reinstall, or a plan edited on another device.
class ReminderSync {
  ReminderSync({required this.channel, required this.locale});

  final ReminderChannel channel;
  final Locale locale;

  Future<void> apply(List<ReminderRequest> requests) async {
    final reminders = buildReminders(requests);
    // Loaded directly from the delegate rather than through a `BuildContext`:
    // rescheduling is not a widget and must work while nothing is on screen.
    final l10n = await AppLocalizations.delegate.load(locale);
    await channel.replaceAll(
      reminders,
      (reminder) => ReminderText(
        title: l10n.notificationTitle,
        body: l10n.notificationBody(reminder.pages, reminder.bookTitle),
      ),
    );
  }
}

/// The locale reminders are written in.
///
/// Notifications are composed long before they are read, so they follow the
/// app's own language setting; when that is "follow the system" the platform
/// locale decides, falling back to the first supported language.
Locale reminderLocale(Locale? setting, Locale platform) {
  if (setting != null) return setting;
  final match = supportedLocales.where(
    (locale) => locale.languageCode == platform.languageCode,
  );
  return match.isEmpty ? supportedLocales.first : match.first;
}

/// Watch this once, high in the tree, and reminders stay current for the life
/// of the app.
final reminderSyncProvider = Provider<ReminderSync>((ref) {
  final settings = ref.watch(appSettingsProvider);
  final sync = ReminderSync(
    channel: ref.watch(reminderChannelProvider),
    locale: reminderLocale(settings.locale, PlatformDispatcher.instance.locale),
  );

  // `fireImmediately` covers app start; the listener covers every later edit —
  // a new plan, a moved session, a finished book.
  ref.listen(dueRemindersProvider, (previous, next) {
    final requests = next.value;
    if (requests != null) unawaited(sync.apply(requests));
  }, fireImmediately: true);

  return sync;
});
