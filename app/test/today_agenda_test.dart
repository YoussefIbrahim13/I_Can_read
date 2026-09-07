import 'package:flutter_test/flutter_test.dart';
import 'package:i_can_read/core/planning/plan_math.dart';
import 'package:i_can_read/features/today/domain/today_agenda.dart';

final _jan1 = DateTime(2026, 1, 1);

PlanSpec plan({
  int startPage = 1,
  int endPage = 240,
  int pagesPerDay = 15,
}) {
  return PlanSpec(
    mode: PlanMode.byPagesPerDay,
    startPage: startPage,
    endPage: endPage,
    startDate: _jan1,
    targetEndDate: DateTime(2026, 1, 16),
    pagesPerDay: pagesPerDay,
  );
}

TodayBook book({
  String bookId = 'book-1',
  String planId = 'plan-1',
  String title = 'The Muqaddimah',
  String? author,
  PlanSpec? spec,
  int lastPageRead = 0,
  int pagesReadToday = 0,
  List<(int minutes, int pages)> sessions = const [(20 * 60, 15)],
}) {
  return TodayBook(
    bookId: bookId,
    planId: planId,
    title: title,
    author: author,
    plan: spec ?? plan(),
    lastPageRead: lastPageRead,
    pagesReadToday: pagesReadToday,
    sessions: [
      for (final (index, session) in sessions.indexed)
        (id: '$planId-$index', minutes: session.$1, pages: session.$2),
    ],
  );
}

void main() {
  test('one session holds the whole daily portion', () {
    final agenda = buildTodayAgenda([book()]);

    expect(agenda.entries, hasLength(1));
    final entry = agenda.entries.single;
    expect(entry.fromPage, 1);
    expect(entry.toPage, 15);
    expect(entry.pagesLeft, 15);
    expect(entry.state, SessionState.current);
  });

  test('sessions take consecutive stretches in time order', () {
    final agenda = buildTodayAgenda([
      book(sessions: const [(8 * 60, 8), (20 * 60, 7)]),
    ]);

    expect([
      for (final e in agenda.entries) (e.fromPage, e.toPage),
    ], [(1, 8), (9, 15)]);
  });

  test('the portion starts where the reader stood when the day began', () {
    // Eight pages already read today: the day's portion is still 1–15, not a
    // fresh fifteen starting at page 9.
    final agenda = buildTodayAgenda([
      book(
        lastPageRead: 8,
        pagesReadToday: 8,
        sessions: const [(8 * 60, 8), (20 * 60, 7)],
      ),
    ]);

    expect(agenda.entries.first.state, SessionState.done);
    expect(agenda.entries.first.pagesDone, 8);
    expect(agenda.entries.last.fromPage, 9);
    expect(agenda.entries.last.pagesDone, 0);
    expect(agenda.entries.last.state, SessionState.current);
  });

  test('reading ahead yesterday moves today forward', () {
    final agenda = buildTodayAgenda([book(lastPageRead: 20)]);

    expect(agenda.entries.single.fromPage, 21);
    expect(agenda.entries.single.toPage, 35);
  });

  test('a partly-read session is still the current one', () {
    final agenda = buildTodayAgenda([
      book(
        lastPageRead: 4,
        pagesReadToday: 4,
        sessions: const [(8 * 60, 8), (20 * 60, 7)],
      ),
    ]);

    final first = agenda.entries.first;
    expect(first.state, SessionState.current);
    expect(first.pagesDone, 4);
    expect(first.pagesLeft, 4);
    // Resuming opens on the first unread page, not the start of the session.
    expect(first.nextPage, 5);
  });

  test('the last day of a book is short, and empties later sessions', () {
    final agenda = buildTodayAgenda([
      book(
        lastPageRead: 235,
        sessions: const [(8 * 60, 8), (20 * 60, 7)],
      ),
    ]);

    expect(agenda.entries, hasLength(1));
    expect(agenda.entries.single.fromPage, 236);
    expect(agenda.entries.single.toPage, 240);
  });

  test('a finished book is not on today at all', () {
    final agenda = buildTodayAgenda([book(lastPageRead: 240)]);

    expect(agenda.isEmpty, isTrue);
  });

  test('sessions with no pages are skipped', () {
    final agenda = buildTodayAgenda([
      book(sessions: const [(8 * 60, 15), (20 * 60, 0)]),
    ]);

    expect(agenda.entries, hasLength(1));
  });

  test('two books interleave by time of day', () {
    final agenda = buildTodayAgenda([
      book(sessions: const [(21 * 60, 15)]),
      book(
        bookId: 'book-2',
        planId: 'plan-2',
        title: 'Kalila wa Dimna',
        spec: plan(pagesPerDay: 8),
        sessions: const [(7 * 60, 8)],
      ),
    ]);

    expect([
      for (final e in agenda.entries) e.title,
    ], ['Kalila wa Dimna', 'The Muqaddimah']);
    expect(agenda.current?.title, 'Kalila wa Dimna');
    expect(agenda.later.single.title, 'The Muqaddimah');
    expect(agenda.bookCount, 2);
  });

  test('exactly one session is current, however many are unread', () {
    final agenda = buildTodayAgenda([
      book(sessions: const [(8 * 60, 5), (13 * 60, 5), (20 * 60, 5)]),
    ]);

    expect(
      agenda.entries.where((e) => e.state == SessionState.current),
      hasLength(1),
    );
    expect(agenda.entries.first.state, SessionState.current);
  });

  test('the day is done when every session is read', () {
    final agenda = buildTodayAgenda([
      book(
        lastPageRead: 15,
        pagesReadToday: 15,
        sessions: const [(8 * 60, 8), (20 * 60, 7)],
      ),
    ]);

    expect(agenda.isDone, isTrue);
    expect(agenda.current, isNull);
    expect(agenda.later, isEmpty);
  });

  test('an empty day is not a finished day', () {
    // Nothing to read and nothing done are different states, and the screen
    // says different things about them.
    expect(buildTodayAgenda(const []).isDone, isFalse);
    expect(buildTodayAgenda(const []).isEmpty, isTrue);
  });

  test('totals cover every book', () {
    final agenda = buildTodayAgenda([
      book(
        lastPageRead: 8,
        pagesReadToday: 8,
        sessions: const [(8 * 60, 8), (20 * 60, 7)],
      ),
      book(
        bookId: 'book-2',
        planId: 'plan-2',
        title: 'Kalila wa Dimna',
        spec: plan(pagesPerDay: 8),
        sessions: const [(7 * 60, 8)],
      ),
    ]);

    expect(agenda.totalPages, 23);
    expect(agenda.pagesDone, 8);
  });

  test('a plan that has not started yet begins at its start page', () {
    final agenda = buildTodayAgenda([
      book(spec: plan(startPage: 40, endPage: 240)),
    ]);

    expect(agenda.entries.single.fromPage, 40);
    expect(agenda.entries.single.toPage, 54);
  });
}
