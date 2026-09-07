import 'package:flutter_test/flutter_test.dart';
import 'package:i_can_read/core/notifications/reminder.dart';

ReminderRequest request({
  String planId = 'plan-1',
  String bookId = 'book-1',
  String bookTitle = 'The Muqaddimah',
  int ordinal = 0,
  int minutes = 20 * 60,
  int pages = 15,
  int daysOfWeek = everyDay,
  bool isEnabled = true,
}) {
  return ReminderRequest(
    planId: planId,
    bookId: bookId,
    bookTitle: bookTitle,
    ordinal: ordinal,
    minutes: minutes,
    pages: pages,
    daysOfWeek: daysOfWeek,
    isEnabled: isEnabled,
  );
}

void main() {
  group('reminderId', () {
    test('is the same for the same session every time', () {
      expect(reminderId('plan-1', 0), reminderId('plan-1', 0));
    });

    test('differs by plan, by ordinal and by weekday', () {
      expect(reminderId('plan-1', 0), isNot(reminderId('plan-2', 0)));
      expect(reminderId('plan-1', 0), isNot(reminderId('plan-1', 1)));
      expect(
        reminderId('plan-1', 0, DateTime.monday),
        isNot(reminderId('plan-1', 0, DateTime.tuesday)),
      );
    });

    test('stays inside a 32-bit signed integer', () {
      // Android notification ids are Java ints; overflowing one silently
      // truncates and two reminders start overwriting each other.
      for (var i = 0; i < 500; i++) {
        final id = reminderId('plan-$i', i % 8, 1 + (i % 7));
        expect(id, greaterThanOrEqualTo(0));
        expect(id, lessThan(1 << 31));
      }
    });

    test('does not collide across the ordinals one plan can hold', () {
      final ids = {for (var i = 0; i < 8; i++) reminderId('plan-1', i)};
      expect(ids, hasLength(8));
    });
  });

  group('buildReminders', () {
    test('a daily session becomes one repeating reminder', () {
      final reminders = buildReminders([request()]);

      expect(reminders, hasLength(1));
      expect(reminders.single.isDaily, isTrue);
      expect(reminders.single.hour, 20);
      expect(reminders.single.minute, 0);
      expect(reminders.single.pages, 15);
      expect(reminders.single.bookTitle, 'The Muqaddimah');
    });

    test('drops sessions the reader switched off', () {
      expect(buildReminders([request(isEnabled: false)]), isEmpty);
    });

    test('drops sessions with no pages to read', () {
      // More sessions than pages is allowed by the split; a reminder that says
      // "0 pages" is not.
      expect(buildReminders([request(pages: 0)]), isEmpty);
    });

    test('drops sessions that repeat on no day', () {
      expect(buildReminders([request(daysOfWeek: 0)]), isEmpty);
    });

    test('a partial week becomes one weekly reminder per day', () {
      // Monday, Wednesday, Friday.
      final days = (1 << 0) | (1 << 2) | (1 << 4);
      final reminders = buildReminders([request(daysOfWeek: days)]);

      expect(
        [for (final r in reminders) r.weekday],
        [DateTime.monday, DateTime.wednesday, DateTime.friday],
      );
      expect(reminders.every((r) => r.pages == 15), isTrue);
      expect({for (final r in reminders) r.id}, hasLength(3));
    });

    test('orders by time of day', () {
      final reminders = buildReminders([
        request(ordinal: 0, minutes: 21 * 60),
        request(ordinal: 1, minutes: 7 * 60 + 30),
        request(ordinal: 2, minutes: 13 * 60),
      ]);

      expect([
        for (final r in reminders) r.minutes,
      ], [7 * 60 + 30, 13 * 60, 21 * 60]);
    });

    test('caps the set, keeping the earliest times', () {
      final requests = [
        for (var i = 0; i < maxScheduledReminders + 10; i++)
          request(planId: 'plan-$i', minutes: i),
      ];

      final reminders = buildReminders(requests);

      expect(reminders, hasLength(maxScheduledReminders));
      expect(reminders.last.minutes, maxScheduledReminders - 1);
    });

    test('is stable: the same input gives the same ids in the same order', () {
      final requests = [
        request(planId: 'b', minutes: 9 * 60),
        request(planId: 'a', minutes: 9 * 60),
      ];

      expect(
        [for (final r in buildReminders(requests)) r.id],
        [for (final r in buildReminders(requests)) r.id],
      );
    });
  });
}
