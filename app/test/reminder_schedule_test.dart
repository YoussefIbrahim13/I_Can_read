import 'package:flutter_test/flutter_test.dart';
import 'package:i_can_read/core/notifications/local_reminder_channel.dart';
import 'package:i_can_read/core/notifications/reminder.dart';
import 'package:timezone/data/latest_10y.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

Reminder at(int hour, int minute, {int? weekday}) => Reminder(
  id: 1,
  bookId: 'book-1',
  bookTitle: 'The Muqaddimah',
  minutes: hour * 60 + minute,
  pages: 15,
  weekday: weekday,
);

void main() {
  late tz.Location newYork;

  setUpAll(() {
    tz_data.initializeTimeZones();
    // A zone that actually observes daylight saving, which is the only way to
    // test that reminders keep their wall-clock time across the change.
    newYork = tz.getLocation('America/New_York');
  });

  tz.TZDateTime moment(int year, int month, int day, int hour, int minute) =>
      tz.TZDateTime(newYork, year, month, day, hour, minute);

  group('nextOccurrence', () {
    test('is later today when the time has not passed', () {
      final next = LocalReminderChannel.nextOccurrence(
        at(20, 0),
        from: moment(2026, 5, 4, 9, 0),
      );

      expect(next, moment(2026, 5, 4, 20, 0));
    });

    test('is tomorrow when the time has passed', () {
      final next = LocalReminderChannel.nextOccurrence(
        at(20, 0),
        from: moment(2026, 5, 4, 20, 30),
      );

      expect(next, moment(2026, 5, 5, 20, 0));
    });

    test('is tomorrow when the time is exactly now', () {
      // Scheduling for the current instant is a reminder that may or may not
      // fire depending on how long the write took; tomorrow is the honest one.
      final next = LocalReminderChannel.nextOccurrence(
        at(20, 0),
        from: moment(2026, 5, 4, 20, 0),
      );

      expect(next, moment(2026, 5, 5, 20, 0));
    });

    test('keeps its wall-clock time across a daylight-saving change', () {
      // Clocks in New York jump forward at 02:00 on 8 March 2026.
      final next = LocalReminderChannel.nextOccurrence(
        at(20, 0),
        from: moment(2026, 3, 7, 21, 0),
      );

      expect(next.day, 8);
      expect(next.hour, 20);
      expect(next.minute, 0);
    });

    test('a weekly reminder lands on its weekday', () {
      // 4 May 2026 is a Monday.
      final next = LocalReminderChannel.nextOccurrence(
        at(7, 30, weekday: DateTime.friday),
        from: moment(2026, 5, 4, 9, 0),
      );

      expect(next.weekday, DateTime.friday);
      expect(next, moment(2026, 5, 8, 7, 30));
    });

    test('a weekly reminder due today still fires today', () {
      final next = LocalReminderChannel.nextOccurrence(
        at(20, 0, weekday: DateTime.monday),
        from: moment(2026, 5, 4, 9, 0),
      );

      expect(next, moment(2026, 5, 4, 20, 0));
    });

    test('a weekly reminder already past today waits a week', () {
      final next = LocalReminderChannel.nextOccurrence(
        at(7, 0, weekday: DateTime.monday),
        from: moment(2026, 5, 4, 9, 0),
      );

      expect(next, moment(2026, 5, 11, 7, 0));
    });
  });
}
