/// What the reader owes today, across every book, as pure data.
///
/// The clock is deliberately absent. "This session" is the earliest session the
/// reader has not finished — not the one nearest to now — so a portion missed
/// at breakfast is still waiting at midnight instead of being written off. That
/// is the same rule as the plan itself: missing time moves the work, it does
/// not delete it.
library;

import '../../../core/planning/plan_math.dart';

/// Where a session stands, from the reader's point of view.
enum SessionState {
  /// Every page of this session's stretch has been read.
  done,

  /// The next thing to do — exactly one session in the whole day has this.
  current,

  /// Still ahead.
  upcoming,
}

/// One book's contribution to today, before the day is laid out.
class TodayBook {
  const TodayBook({
    required this.bookId,
    required this.planId,
    required this.title,
    this.author,
    required this.plan,
    required this.lastPageRead,
    required this.pagesReadToday,
    required this.sessions,
  });

  final String bookId;
  final String planId;
  final String title;
  final String? author;
  final PlanSpec plan;
  final int lastPageRead;

  /// Pages credited to today, used to work out where the day began.
  final int pagesReadToday;

  /// Time order.
  final List<({String id, int minutes, int pages})> sessions;
}

/// One session of one book, on today's list.
class TodayEntry {
  const TodayEntry({
    required this.bookId,
    required this.planId,
    required this.sessionId,
    required this.title,
    this.author,
    required this.minutes,
    required this.fromPage,
    required this.toPage,
    required this.pagesDone,
    required this.state,
  });

  final String bookId;
  final String planId;
  final String sessionId;
  final String title;
  final String? author;

  /// Minutes after local midnight.
  final int minutes;

  /// This session's stretch of today's portion, inclusive.
  final int fromPage;
  final int toPage;

  /// How much of that stretch is already read.
  final int pagesDone;

  final SessionState state;

  int get hour => minutes ~/ 60;
  int get minute => minutes % 60;
  int get pages => toPage - fromPage + 1;
  int get pagesLeft => pages - pagesDone;

  /// The page to open the reader on.
  int get nextPage => pagesDone >= pages ? toPage : fromPage + pagesDone;

  TodayEntry _as(SessionState next) => TodayEntry(
    bookId: bookId,
    planId: planId,
    sessionId: sessionId,
    title: title,
    author: author,
    minutes: minutes,
    fromPage: fromPage,
    toPage: toPage,
    pagesDone: pagesDone,
    state: next,
  );

  @override
  String toString() =>
      'TodayEntry($title, $hour:$minute, $fromPage-$toPage, '
      '$pagesDone done, ${state.name})';
}

/// Today, laid out.
class TodayAgenda {
  const TodayAgenda(this.entries);

  /// Every session due today, in time order across all books.
  final List<TodayEntry> entries;

  bool get isEmpty => entries.isEmpty;

  /// The session the screen leads with, or null when the day is finished.
  TodayEntry? get current {
    for (final entry in entries) {
      if (entry.state == SessionState.current) return entry;
    }
    return null;
  }

  /// Everything after [current] in time order.
  ///
  /// Strictly *later*: a session finished earlier in the day is not repeated as
  /// a row. It is still part of the day — it keeps its segment in the day's bar
  /// and its pages in the totals — but the list is about what is still coming.
  ///
  /// An entry in this list can still be finished, when it belongs to a
  /// different book whose pages were read out of clock order.
  List<TodayEntry> get later {
    final lead = current;
    if (lead == null) return const [];
    final at = entries.indexOf(lead);
    return entries.sublist(at + 1);
  }

  int get totalPages => entries.fold(0, (sum, entry) => sum + entry.pages);
  int get pagesDone => entries.fold(0, (sum, entry) => sum + entry.pagesDone);

  /// What the day still owes, across every book.
  int get pagesLeft => totalPages - pagesDone;

  /// True when there was work today and all of it is finished.
  bool get isDone => entries.isNotEmpty && current == null;

  int get bookCount => {for (final entry in entries) entry.bookId}.length;
}

/// Lays today out: which pages belong to which session, and what is left.
///
/// Each book's daily portion starts where the reader stood when the day began —
/// `lastPageRead` less whatever was read today — so the ranges shown are the
/// ones the reader actually worked through, not a fresh quota computed from
/// progress that already includes this morning.
TodayAgenda buildTodayAgenda(Iterable<TodayBook> books) {
  final entries = <TodayEntry>[];

  for (final book in books) {
    final plan = book.plan;
    if (plan.isComplete(book.lastPageRead)) continue;

    final stoodAt = book.lastPageRead - book.pagesReadToday;
    final assignment = nextAssignment(plan, stoodAt);
    if (assignment == null) continue;

    var next = assignment.fromPage;
    for (final session in book.sessions) {
      if (session.pages <= 0) continue;
      // The last day of a book can be shorter than the quota, so a session may
      // fall entirely outside the portion. It has nothing to say today.
      if (next > assignment.toPage) break;

      final to = (next + session.pages - 1).clamp(next, assignment.toPage);
      final done = (book.lastPageRead - next + 1).clamp(0, to - next + 1);
      entries.add(
        TodayEntry(
          bookId: book.bookId,
          planId: book.planId,
          sessionId: session.id,
          title: book.title,
          author: book.author,
          minutes: session.minutes,
          fromPage: next,
          toPage: to,
          pagesDone: done,
          // Filled in below, once the whole day is in time order.
          state: done == to - next + 1
              ? SessionState.done
              : SessionState.upcoming,
        ),
      );
      next = to + 1;
    }
  }

  entries.sort((a, b) {
    final byTime = a.minutes.compareTo(b.minutes);
    if (byTime != 0) return byTime;
    // Two books at the same time need *an* order; the title is one the reader
    // can predict, unlike whatever the database returned.
    final byTitle = a.title.compareTo(b.title);
    return byTitle != 0 ? byTitle : a.fromPage.compareTo(b.fromPage);
  });

  for (var i = 0; i < entries.length; i++) {
    if (entries[i].state != SessionState.done) {
      entries[i] = entries[i]._as(SessionState.current);
      break;
    }
  }

  return TodayAgenda(entries);
}
