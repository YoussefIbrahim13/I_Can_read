import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:i_can_read/core/db/app_database.dart';
import 'package:i_can_read/core/notifications/reminder.dart';
import 'package:i_can_read/core/notifications/reminder_channel.dart';
import 'package:i_can_read/core/notifications/reminder_sync.dart';
import 'package:i_can_read/core/planning/plan_math.dart';
import 'package:i_can_read/core/settings/app_settings.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Records what the app asked the system to schedule.
class RecordingChannel implements ReminderChannel {
  final passes = <List<Reminder>>[];
  final bodies = <String>[];

  List<Reminder> get latest => passes.isEmpty ? const [] : passes.last;

  @override
  Stream<String> get taps => const Stream.empty();

  @override
  Future<String?> takeLaunchPayload() async => null;

  @override
  Future<bool> requestPermission() async => true;

  @override
  Future<void> replaceAll(
    List<Reminder> reminders,
    ReminderText Function(Reminder) text,
  ) async {
    passes.add(reminders);
    bodies
      ..clear()
      ..addAll([for (final reminder in reminders) text(reminder).body]);
  }
}

final _jan1 = DateTime(2026, 1, 1);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late RecordingChannel channel;
  late SharedPreferences prefs;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    channel = RecordingChannel();
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
  });

  tearDown(() => db.close());

  Future<void> addBook({
    String bookId = 'book-1',
    String planId = 'plan-1',
    String title = 'The Muqaddimah',
    BookStatus status = BookStatus.reading,
    bool isActive = true,
    List<(int minutes, int pages)> sessions = const [(20 * 60, 15)],
  }) async {
    await db
        .into(db.books)
        .insert(
          BooksCompanion.insert(
            id: bookId,
            title: title,
            pageCount: 240,
            status: Value(status),
            createdAt: _jan1,
            updatedAt: _jan1,
          ),
        );
    await db
        .into(db.readingPlans)
        .insert(
          ReadingPlansCompanion.insert(
            id: planId,
            bookId: bookId,
            mode: PlanMode.byPagesPerDay,
            startPage: 1,
            endPage: 240,
            startDate: _jan1,
            targetEndDate: DateTime(2026, 1, 16),
            pagesPerDay: 15,
            isActive: Value(isActive),
            createdAt: _jan1,
            updatedAt: _jan1,
          ),
        );
    await db.replaceSessions(planId, [
      for (final (ordinal, session) in sessions.indexed)
        ReadingSessionsCompanion.insert(
          id: '$planId-$ordinal',
          planId: planId,
          ordinal: ordinal,
          timeOfDayMinutes: session.$1,
          pagesShare: session.$2,
          updatedAt: _jan1,
        ),
    ]);
  }

  ProviderContainer open() {
    final container = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        sharedPreferencesProvider.overrideWithValue(prefs),
        reminderChannelProvider.overrideWithValue(channel),
      ],
    );
    addTearDown(container.dispose);
    // Listened, not read: providers are disposed the moment nothing holds
    // them, and a sync with no listener would stop rescheduling immediately.
    container.listen(reminderSyncProvider, (_, _) {});
    return container;
  }

  test('schedules one reminder per session of an active plan', () async {
    await addBook(sessions: const [(8 * 60, 8), (20 * 60, 7)]);
    open();

    await pumpEventQueue();

    expect(channel.latest, hasLength(2));
    expect([for (final r in channel.latest) r.minutes], [8 * 60, 20 * 60]);
    expect([for (final r in channel.latest) r.pages], [8, 7]);
  });

  test('writes the reminder in English by default', () async {
    await addBook();
    open();

    await pumpEventQueue();

    expect(channel.bodies, ['15 pages from The Muqaddimah']);
  });

  test('writes the reminder in the language the reader chose', () async {
    await addBook();
    final container = open();
    await pumpEventQueue();

    await container
        .read(appSettingsProvider.notifier)
        .setLocale(const Locale('ar'));
    container.read(reminderSyncProvider);
    await pumpEventQueue();

    expect(channel.bodies, ['15 صفحة من The Muqaddimah']);
  });

  test('a finished book stops reminding', () async {
    await addBook(status: BookStatus.finished);
    open();

    await pumpEventQueue();

    expect(channel.latest, isEmpty);
  });

  test('an inactive plan stops reminding', () async {
    await addBook(isActive: false);
    open();

    await pumpEventQueue();

    expect(channel.latest, isEmpty);
  });

  test('reschedules the whole set when a session changes', () async {
    await addBook();
    open();
    await pumpEventQueue();
    final before = channel.passes.length;

    await db.replaceSessions('plan-1', [
      ReadingSessionsCompanion.insert(
        id: 'plan-1-0',
        planId: 'plan-1',
        ordinal: 0,
        timeOfDayMinutes: 6 * 60 + 30,
        pagesShare: 15,
        updatedAt: _jan1,
      ),
    ]);
    await pumpEventQueue();

    expect(channel.passes.length, greaterThan(before));
    expect(channel.latest.single.minutes, 6 * 60 + 30);
  });

  test('books are reminded about independently', () async {
    await addBook();
    await addBook(
      bookId: 'book-2',
      planId: 'plan-2',
      title: 'Kalila wa Dimna',
      sessions: const [(7 * 60, 10)],
    );
    open();

    await pumpEventQueue();

    expect(
      [for (final r in channel.latest) r.bookTitle],
      ['Kalila wa Dimna', 'The Muqaddimah'],
    );
    expect({for (final r in channel.latest) r.id}, hasLength(2));
  });

  group('reminderLocale', () {
    test('honours the reader\'s choice', () {
      expect(
        reminderLocale(const Locale('ar'), const Locale('en')),
        const Locale('ar'),
      );
    });

    test('follows the platform when no choice was made', () {
      expect(
        reminderLocale(null, const Locale('ar', 'EG')),
        const Locale('ar'),
      );
    });

    test('falls back to a supported language', () {
      expect(reminderLocale(null, const Locale('fr')), supportedLocales.first);
    });
  });
}
