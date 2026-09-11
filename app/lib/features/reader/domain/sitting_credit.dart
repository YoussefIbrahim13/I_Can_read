/// What a sitting hands back to the plan when the reader says they are done.
///
/// Pure arithmetic, so the one rule that decides whether progress is honest can
/// be argued with in a test rather than inside a PDF viewer.
library;

import '../../../core/planning/plan_math.dart';

/// The pair this returns is the plan's own, so callers need not reach past it.
export '../../../core/planning/plan_math.dart' show DayAssignment;

/// The stretch to credit, or null when this sitting owes the plan nothing.
///
/// The reader can turn to any page of the book — that is the point of the
/// reader — but the plan only covers [planStart]..[planEnd]. Pages outside it
/// were left out deliberately: front matter, an index, a chapter read months
/// ago. So the sitting is credited with the part of itself that fell inside
/// the plan, and a sitting spent entirely outside it is credited with nothing.
///
/// [furthest] rather than the page on screen: turning back to re-read a
/// paragraph does not un-read the pages behind it.
DayAssignment? sittingCredit({
  required int openedAt,
  required int furthest,
  required int planStart,
  required int planEnd,
}) {
  // Nowhere near the plan — the reader opened the index and stayed there, or
  // spent the sitting in a chapter that is already behind them.
  if (furthest < planStart || openedAt > planEnd) return null;

  final from = openedAt < planStart ? planStart : openedAt;
  final to = furthest > planEnd ? planEnd : furthest;
  return DayAssignment(fromPage: from, toPage: to < from ? from : to);
}
