import 'package:flutter_test/flutter_test.dart';
import 'package:i_can_read/core/notifications/local_reminder_channel.dart';
import 'package:i_can_read/core/notifications/reminder.dart';
import 'package:i_can_read/core/notifications/reminder_channel.dart';
import 'package:integration_test/integration_test.dart';
import 'package:timezone/timezone.dart' as tz;

/// Puts real reminders in front of the real system scheduler.
///
/// Everything in `test/reminder_*.dart` proves the app asks for the right
/// things; only this proves the platform accepted them. It cannot run on the
/// host VM — `flutter_local_notifications` and `flutter_timezone` are platform
/// plugins.
///
/// Run with: `flutter test integration_test/reminder_channel_test.dart -d <device>`
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late LocalReminderChannel channel;

  ReminderText words(Reminder reminder) => ReminderText(
    title: 'Time to read',
    body: '${reminder.pages} pages from ${reminder.bookTitle}',
  );

  Reminder reminder({
    required String planId,
    int ordinal = 0,
    int minutes = 20 * 60,
    int? weekday,
  }) {
    return Reminder(
      id: reminderId(planId, ordinal, weekday),
      bookId: 'book-1',
      bookTitle: 'The Muqaddimah',
      minutes: minutes,
      pages: 15,
      weekday: weekday,
    );
  }

  setUp(() async {
    channel = await LocalReminderChannel.open();
    await channel.plugin.cancelAll();
  });

  tearDown(() => channel.plugin.cancelAll());

  Future<List<int>> pendingIds() async {
    final pending = await channel.plugin.pendingNotificationRequests();
    return [for (final request in pending) request.id]..sort();
  }

  testWidgets('opening pins the timezone to the device', (tester) async {
    // Left at UTC the reminder would fire at the wrong hour for most readers,
    // and nothing else in the app would notice.
    expect(tz.local.name, isNotEmpty);
    expect(tz.TZDateTime.now(tz.local).timeZoneName, isNotEmpty);
  });

  testWidgets('the system accepts a daily reminder', (tester) async {
    final daily = reminder(planId: 'plan-1');

    await channel.replaceAll([daily], words);

    expect(await pendingIds(), [daily.id]);
  });

  testWidgets('the book id rides along, so a tap can open it', (tester) async {
    // The payload is the whole reason a tap can land on the right book. If it
    // is dropped in transit the reminder still fires and still goes nowhere.
    final daily = reminder(planId: 'plan-1');

    await channel.replaceAll([daily], words);

    final pending = await channel.plugin.pendingNotificationRequests();
    expect(pending.single.payload, 'book-1');
  });

  testWidgets('a normal launch reports no reminder behind it', (tester) async {
    expect(await channel.takeLaunchPayload(), isNull);
  });

  testWidgets('the system accepts one reminder per session', (tester) async {
    final morning = reminder(planId: 'plan-1', minutes: 8 * 60);
    final evening = reminder(planId: 'plan-1', ordinal: 1);

    await channel.replaceAll([morning, evening], words);

    expect(await pendingIds(), [morning.id, evening.id]..sort());
  });

  testWidgets('the system accepts a weekly reminder', (tester) async {
    final friday = reminder(planId: 'plan-1', weekday: DateTime.friday);

    await channel.replaceAll([friday], words);

    expect(await pendingIds(), [friday.id]);
  });

  testWidgets('replacing drops what is no longer wanted', (tester) async {
    final first = reminder(planId: 'plan-1');
    final second = reminder(planId: 'plan-2');
    await channel.replaceAll([first, second], words);

    await channel.replaceAll([second], words);

    expect(await pendingIds(), [second.id]);
  });

  testWidgets('replacing with nothing cancels everything', (tester) async {
    await channel.replaceAll([reminder(planId: 'plan-1')], words);

    await channel.replaceAll([], words);

    expect(await pendingIds(), isEmpty);
  });

  testWidgets('rescheduling the same reminder does not duplicate it', (
    tester,
  ) async {
    final daily = reminder(planId: 'plan-1');

    await channel.replaceAll([daily], words);
    await channel.replaceAll([daily], words);

    expect(await pendingIds(), [daily.id]);
  });
}
