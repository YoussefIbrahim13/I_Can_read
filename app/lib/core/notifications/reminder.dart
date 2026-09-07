/// What the app asks the operating system to deliver, as pure data.
///
/// Nothing here touches a plugin, a clock or a database, so the rules that
/// decide *which* reminders exist can be stated in tests on any machine —
/// which matters, because notifications themselves cannot be exercised on a
/// desktop build.
library;

import 'dart:convert';

import 'package:crypto/crypto.dart';

/// Every weekday selected — the bitmask a session starts with.
const everyDay = 127;

/// A ceiling on how many reminders are handed to the system at once.
///
/// iOS silently drops pending notifications past 64, so the app stays a little
/// under it and keeps the room to spare for anything scheduled outside a plan.
const maxScheduledReminders = 56;

/// A session as the notification layer sees it: which book, when, how much.
class ReminderRequest {
  const ReminderRequest({
    required this.planId,
    required this.bookId,
    required this.bookTitle,
    required this.ordinal,
    required this.minutes,
    required this.pages,
    this.daysOfWeek = everyDay,
    this.isEnabled = true,
  });

  final String planId;
  final String bookId;
  final String bookTitle;

  /// The session's position in its plan. Part of the notification id, so it
  /// has to be dense and stable — which is why sessions are rewritten whole.
  final int ordinal;

  /// Minutes after local midnight.
  final int minutes;
  final int pages;

  /// Bitmask, bit 0 = Monday, matching [DateTime.monday] − 1.
  final int daysOfWeek;
  final bool isEnabled;
}

/// One scheduled notification.
class Reminder {
  const Reminder({
    required this.id,
    required this.bookId,
    required this.bookTitle,
    required this.minutes,
    required this.pages,
    this.weekday,
  });

  /// Stable across restarts and reinstalls: derived from the plan id and the
  /// session's ordinal, never from a counter. A reminder can therefore be
  /// replaced or cancelled without remembering what was scheduled last time.
  final int id;

  final String bookId;
  final String bookTitle;

  /// Minutes after local midnight.
  final int minutes;
  final int pages;

  /// `null` means every day. Otherwise [DateTime.monday]..[DateTime.sunday].
  final int? weekday;

  int get hour => minutes ~/ 60;
  int get minute => minutes % 60;

  bool get isDaily => weekday == null;

  @override
  bool operator ==(Object other) =>
      other is Reminder &&
      other.id == id &&
      other.bookId == bookId &&
      other.bookTitle == bookTitle &&
      other.minutes == minutes &&
      other.pages == pages &&
      other.weekday == weekday;

  @override
  int get hashCode =>
      Object.hash(id, bookId, bookTitle, minutes, pages, weekday);

  @override
  String toString() =>
      'Reminder($id, $bookTitle, $hour:$minute, $pages pages, '
      'weekday: ${weekday ?? 'every'})';
}

/// A notification id that depends only on what the reminder *is*.
///
/// Android ids are 32-bit signed, so the plan's UUID is folded down to 24 bits
/// of SHA-1 and the low bits carry the ordinal and the weekday. A hash that
/// narrow will collide eventually; the cost of a collision is one reminder
/// overwriting another, and the alternative — a stored id table that has to
/// stay in step with the sessions — buys less than it costs.
int reminderId(String planId, int ordinal, [int? weekday]) {
  final digest = sha1.convert(utf8.encode(planId)).bytes;
  final plan = (digest[0] << 16) | (digest[1] << 8) | digest[2];
  return (plan << 6) | ((ordinal & 7) << 3) | (weekday ?? 0);
}

/// Turns the sessions worth reminding about into the notifications to schedule.
///
/// Sessions are dropped when they are switched off, hold no pages, or repeat on
/// no day at all: a reminder that says "read 0 pages" is noise, and the reader
/// did not ask for it.
List<Reminder> buildReminders(Iterable<ReminderRequest> requests) {
  final reminders = <Reminder>[];

  for (final request in requests) {
    if (!request.isEnabled || request.pages <= 0) continue;
    final days = request.daysOfWeek & everyDay;
    if (days == 0) continue;

    if (days == everyDay) {
      reminders.add(
        Reminder(
          id: reminderId(request.planId, request.ordinal),
          bookId: request.bookId,
          bookTitle: request.bookTitle,
          minutes: request.minutes,
          pages: request.pages,
        ),
      );
      continue;
    }

    // A partial week has no single repeating notification behind it, so it
    // becomes one weekly notification per selected day.
    for (var weekday = DateTime.monday; weekday <= DateTime.sunday; weekday++) {
      if (days & (1 << (weekday - 1)) == 0) continue;
      reminders.add(
        Reminder(
          id: reminderId(request.planId, request.ordinal, weekday),
          bookId: request.bookId,
          bookTitle: request.bookTitle,
          minutes: request.minutes,
          pages: request.pages,
          weekday: weekday,
        ),
      );
    }
  }

  // Earliest in the day first, so that if the cap bites it is the late-night
  // reminders that are lost rather than an arbitrary set.
  reminders.sort((a, b) {
    final byTime = a.minutes.compareTo(b.minutes);
    if (byTime != 0) return byTime;
    final byTitle = a.bookTitle.compareTo(b.bookTitle);
    return byTitle != 0 ? byTitle : a.id.compareTo(b.id);
  });

  if (reminders.length > maxScheduledReminders) {
    reminders.length = maxScheduledReminders;
  }
  return reminders;
}
