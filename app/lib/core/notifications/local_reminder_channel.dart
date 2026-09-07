import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_10y.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

import 'reminder.dart';
import 'reminder_channel.dart';

/// The real channel: `flutter_local_notifications` over the device clock.
///
/// A reminder is a *repeating* notification — one per session, matched on the
/// time of day — rather than one notification per day queued in advance. The
/// app cannot rely on being run to top up a queue, and a fixed daily time is
/// exactly what the system schedulers are built for.
class LocalReminderChannel implements ReminderChannel {
  LocalReminderChannel._(this.plugin, this._taps);

  /// The Android notification channel. Its id is baked into every posted
  /// notification, so renaming it strands the reader's per-channel settings.
  static const _channelId = 'reading_reminders';
  static const _channelName = 'Reading reminders';

  /// Public only so a device test can read back what the system actually
  /// accepted; nothing else should reach past this class.
  @visibleForTesting
  final FlutterLocalNotificationsPlugin plugin;

  final StreamController<String> _taps;

  var _launchPayloadTaken = false;

  @override
  Stream<String> get taps => _taps.stream;

  @override
  Future<String?> takeLaunchPayload() async {
    // Asked once and only once: the launch details do not clear themselves, so
    // a second read would reopen the same book on every hot restart.
    if (_launchPayloadTaken) return null;
    _launchPayloadTaken = true;

    final details = await plugin.getNotificationAppLaunchDetails();
    if (details?.didNotificationLaunchApp != true) return null;
    return details?.notificationResponse?.payload;
  }

  /// Initialises the plugin and pins the timezone database to the device zone.
  ///
  /// The zone is read once at startup and again by whoever calls this: a
  /// reader who flies across three zones gets their reminders re-pinned on the
  /// next launch, which is the first moment the app can do anything about it.
  static Future<LocalReminderChannel> open() async {
    tz_data.initializeTimeZones();
    try {
      final zone = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(zone.identifier));
    } catch (error) {
      // An unknown zone name must not stop the app from starting; UTC is wrong
      // but harmless, and the next launch tries again.
      debugPrint('Falling back to UTC for reminders: $error');
    }

    final taps = StreamController<String>.broadcast();
    final plugin = FlutterLocalNotificationsPlugin();
    await plugin.initialize(
      onDidReceiveNotificationResponse: (response) {
        final payload = response.payload;
        if (payload != null && payload.isNotEmpty) taps.add(payload);
      },
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        // Permission is asked for later, when the reader has actually made a
        // plan, rather than in the first second of the first launch.
        iOS: DarwinInitializationSettings(
          requestAlertPermission: false,
          requestSoundPermission: false,
          requestBadgePermission: false,
        ),
      ),
    );
    return LocalReminderChannel._(plugin, taps);
  }

  @override
  Future<bool> requestPermission() async {
    final android = plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    if (android != null) {
      // Android 13+ only; older versions answer true without a prompt.
      // `USE_EXACT_ALARM` is deliberately never requested — Play treats it as
      // a restricted permission and a reading reminder does not need a
      // to-the-second alarm.
      return await android.requestNotificationsPermission() ?? false;
    }

    final ios = plugin
        .resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin
        >();
    if (ios != null) {
      return await ios.requestPermissions(alert: true, badge: true, sound: true) ??
          false;
    }
    return false;
  }

  @override
  Future<void> replaceAll(
    List<Reminder> reminders,
    ReminderText Function(Reminder) text,
  ) async {
    await plugin.cancelAll();
    for (final reminder in reminders) {
      final words = text(reminder);
      await plugin.zonedSchedule(
        id: reminder.id,
        title: words.title,
        body: words.body,
        scheduledDate: nextOccurrence(reminder),
        payload: reminder.bookId,
        notificationDetails: const NotificationDetails(
          android: AndroidNotificationDetails(
            _channelId,
            _channelName,
            importance: Importance.defaultImportance,
            priority: Priority.defaultPriority,
          ),
          iOS: DarwinNotificationDetails(),
        ),
        // Inexact by design: the system may batch the reminder with other work
        // to save battery, and a reading nudge that arrives at 20:04 is the
        // same reminder.
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        matchDateTimeComponents: reminder.isDaily
            ? DateTimeComponents.time
            : DateTimeComponents.dayOfWeekAndTime,
      );
    }
  }

  /// The first time this reminder should fire, at or after [from].
  ///
  /// Days are stepped by building a new date rather than adding 24 hours, so a
  /// daylight-saving change moves the wall-clock time with the reader instead
  /// of dragging the reminder an hour off.
  @visibleForTesting
  static tz.TZDateTime nextOccurrence(Reminder reminder, {tz.TZDateTime? from}) {
    final now = from ?? tz.TZDateTime.now(tz.local);
    var when = tz.TZDateTime(
      now.location,
      now.year,
      now.month,
      now.day,
      reminder.hour,
      reminder.minute,
    );
    if (!when.isAfter(now)) when = _nextDay(when);
    while (reminder.weekday != null && when.weekday != reminder.weekday) {
      when = _nextDay(when);
    }
    return when;
  }

  static tz.TZDateTime _nextDay(tz.TZDateTime day) => tz.TZDateTime(
    day.location,
    day.year,
    day.month,
    day.day + 1,
    day.hour,
    day.minute,
  );
}
