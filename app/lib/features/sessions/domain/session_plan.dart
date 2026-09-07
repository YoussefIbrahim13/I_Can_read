/// How a day's reading is split across times of day, as pure data.
///
/// The invariant the whole file exists to hold: **the slots always sum to the
/// plan's daily quota.** A reader editing one session must never be able to
/// produce a day that reads 14 pages when the plan says 15 — so every edit
/// rebalances the others rather than reporting an error.
library;

import '../../../core/planning/plan_math.dart';

/// Where a fresh plan puts its one reminder: an evening read.
const defaultSessionMinutes = 20 * 60;

/// A new session lands here when the reader adds one without picking a time.
const addedSessionMinutes = 8 * 60;

/// Roughly when in the day a session falls, for the caption under its time.
enum SessionPeriod { morning, afternoon, evening, night }

/// One reminder: a time of day and its share of the daily quota.
class SessionSlot {
  const SessionSlot({required this.minutes, required this.pages});

  /// Minutes after local midnight. Stored as a plain integer so it cannot be
  /// dragged around by a timezone or a DST shift; the zone is applied when the
  /// notification is scheduled.
  final int minutes;

  /// This session's pages. May be 0 when there are more sessions than pages.
  final int pages;

  int get hour => minutes ~/ 60;
  int get minute => minutes % 60;

  SessionPeriod get period => switch (hour) {
    >= 5 && < 12 => SessionPeriod.morning,
    >= 12 && < 17 => SessionPeriod.afternoon,
    >= 17 && < 21 => SessionPeriod.evening,
    _ => SessionPeriod.night,
  };

  SessionSlot copyWith({int? minutes, int? pages}) =>
      SessionSlot(minutes: minutes ?? this.minutes, pages: pages ?? this.pages);

  @override
  bool operator ==(Object other) =>
      other is SessionSlot && other.minutes == minutes && other.pages == pages;

  @override
  int get hashCode => Object.hash(minutes, pages);

  @override
  String toString() => 'SessionSlot($hour:$minute, $pages)';
}

class SessionPlan {
  const SessionPlan({required this.pagesPerDay, required this.slots});

  /// What a plan starts with: one evening reminder holding the whole quota.
  factory SessionPlan.single(
    int pagesPerDay, {
    int minutes = defaultSessionMinutes,
  }) {
    return SessionPlan(
      pagesPerDay: pagesPerDay,
      slots: [SessionSlot(minutes: minutes, pages: pagesPerDay)],
    );
  }

  /// Rebuilds a plan from stored sessions, trusting their saved shares.
  ///
  /// If the plan's quota has since changed the shares are re-split evenly,
  /// because a stale split that no longer adds up is worse than losing a
  /// hand-tuned one.
  factory SessionPlan.restore({
    required int pagesPerDay,
    required List<SessionSlot> slots,
  }) {
    if (slots.isEmpty) return SessionPlan.single(pagesPerDay);
    final sorted = _sorted(slots);
    final total = sorted.fold<int>(0, (sum, slot) => sum + slot.pages);
    if (total == pagesPerDay) {
      return SessionPlan(pagesPerDay: pagesPerDay, slots: sorted);
    }
    return _evenly(pagesPerDay, sorted.map((slot) => slot.minutes).toList());
  }

  /// A soft cap, well under iOS's 64 pending notifications, chosen because a
  /// reader with nine reminders a day has a different problem than scheduling.
  static const maxSessions = 8;

  final int pagesPerDay;

  /// Ordered by time of day. The index doubles as the session's ordinal, which
  /// is what seeds its notification id.
  final List<SessionSlot> slots;

  int get assignedPages => slots.fold(0, (sum, slot) => sum + slot.pages);

  /// Always true by construction; kept as an assertion the tests can state.
  bool get isBalanced => assignedPages == pagesPerDay;

  /// More sessions than pages, so some reminders would arrive with nothing to
  /// read. Allowed, but the screen says so.
  bool get hasEmptySession => slots.any((slot) => slot.pages == 0);

  bool get canAdd => slots.length < maxSessions;
  bool get canRemove => slots.length > 1;

  /// Sets one session's share and takes the difference out of the others,
  /// working back from the last session.
  ///
  /// Moving pages into the morning takes them from the evening, which is how a
  /// reader thinks about it — not "everything rescales by a ratio".
  SessionPlan withPagesAt(int index, int pages) {
    // A lone session always holds the whole quota; there is nothing to trade
    // with, so the stepper on that row is inert by design.
    if (slots.length < 2) return this;

    final target = pages.clamp(0, pagesPerDay);
    final next = [...slots];
    next[index] = next[index].copyWith(pages: target);

    var surplus = next.fold<int>(0, (sum, slot) => sum + slot.pages) - pagesPerDay;

    // Take from the back, give to the back: the last session of the day is the
    // one that absorbs the change.
    while (surplus != 0) {
      var moved = false;
      for (var i = next.length - 1; i >= 0; i--) {
        if (i == index) continue;
        if (surplus > 0 && next[i].pages > 0) {
          next[i] = next[i].copyWith(pages: next[i].pages - 1);
          surplus--;
          moved = true;
        } else if (surplus < 0) {
          next[i] = next[i].copyWith(pages: next[i].pages + 1);
          surplus++;
          moved = true;
        }
        if (surplus == 0) break;
      }
      // Every other session is already empty and the surplus cannot be placed.
      if (!moved) break;
    }

    return SessionPlan(pagesPerDay: pagesPerDay, slots: next);
  }

  /// Moves a session to a new time, keeping the list in time order.
  SessionPlan withTimeAt(int index, int minutes) {
    final next = [...slots];
    next[index] = next[index].copyWith(minutes: minutes.clamp(0, 24 * 60 - 1));
    return SessionPlan(pagesPerDay: pagesPerDay, slots: _sorted(next));
  }

  /// Adds a session and re-splits the day evenly.
  ///
  /// Re-splitting rather than carving a share out of one neighbour: adding a
  /// session is a change to the shape of the day, and an even split is the
  /// answer the reader can predict.
  SessionPlan added({int minutes = addedSessionMinutes}) {
    if (!canAdd) return this;
    return _evenly(pagesPerDay, [
      ...slots.map((slot) => slot.minutes),
      minutes,
    ]);
  }

  SessionPlan removedAt(int index) {
    if (!canRemove) return this;
    final times = [
      for (final (i, slot) in slots.indexed)
        if (i != index) slot.minutes,
    ];
    return _evenly(pagesPerDay, times);
  }

  /// Re-splits for a new daily quota, after the plan itself was edited.
  SessionPlan withPagesPerDay(int pages) =>
      _evenly(pages, slots.map((slot) => slot.minutes).toList());

  /// An even split, largest share first, across the given times.
  static SessionPlan _evenly(int pagesPerDay, List<int> times) {
    final ordered = [...times]..sort();
    final shares = splitAcrossSessions(
      pagesPerDay,
      sessionCount: ordered.length,
    );
    return SessionPlan(
      pagesPerDay: pagesPerDay,
      slots: [
        for (final (i, minutes) in ordered.indexed)
          SessionSlot(minutes: minutes, pages: shares[i]),
      ],
    );
  }

  /// Time order, with equal times keeping their relative order.
  static List<SessionSlot> _sorted(List<SessionSlot> slots) =>
      [...slots]..sort((a, b) => a.minutes.compareTo(b.minutes));
}
