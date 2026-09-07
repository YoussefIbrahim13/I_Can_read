import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'reminder.dart';

/// One reminder's words, already in the reader's language.
///
/// The notification layer never sees `AppLocalizations`: text is resolved by
/// the caller and handed down, so the channel can be swapped for a fake in a
/// test without dragging localization into it.
class ReminderText {
  const ReminderText({required this.title, required this.body});

  final String title;
  final String body;
}

/// Where reminders go. The app owns exactly one.
abstract interface class ReminderChannel {
  /// Asks the reader for permission to post notifications, if the platform
  /// needs asking. Returns false when the reader said no.
  Future<bool> requestPermission();

  /// Makes the scheduled set exactly [reminders], cancelling anything else.
  ///
  /// Replacing rather than diffing: the alternative is tracking what was
  /// scheduled last time across restarts and reinstalls, and getting that
  /// wrong leaves a reminder for a book the reader deleted.
  Future<void> replaceAll(
    List<Reminder> reminders,
    ReminderText Function(Reminder) text,
  );
}

/// The default: schedules nothing.
///
/// Tests and any build without the plugin get this, so nothing has to guard
/// every call site with a null check.
class SilentReminderChannel implements ReminderChannel {
  const SilentReminderChannel();

  @override
  Future<bool> requestPermission() async => false;

  @override
  Future<void> replaceAll(
    List<Reminder> reminders,
    ReminderText Function(Reminder) text,
  ) async {}
}

/// Overridden in `main()` with the real platform channel.
final reminderChannelProvider = Provider<ReminderChannel>(
  (ref) => const SilentReminderChannel(),
);
