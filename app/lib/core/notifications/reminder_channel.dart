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

/// Where reminders go, and where taps come back from. The app owns exactly one.
abstract interface class ReminderChannel {
  /// Book ids from reminders the reader tapped while the app was running.
  ///
  /// A reminder that only raises a banner is an interruption. Tapping one has
  /// to land on the page the reminder is about, which is why the book id is
  /// carried as the notification's payload.
  Stream<String> get taps;

  /// The reminder that launched the app, if a reminder launched it.
  ///
  /// Separate from [taps] because a tap on a terminated app is not delivered
  /// as an event — the system starts the process and hands the payload over
  /// once, on request. Answers null every time after the first.
  Future<String?> takeLaunchPayload();

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
  Stream<String> get taps => const Stream.empty();

  @override
  Future<String?> takeLaunchPayload() async => null;

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
