/// The plan wizard's form state, as pure data.
///
/// Kept free of Flutter so the wizard's arithmetic — clamping, carrying an
/// answer across a mode switch, deciding whether the draft is even valid — can
/// be tested without pumping a widget. The screen holds one of these and
/// rebuilds from it; every edit returns a new draft.
library;

import '../../../core/planning/plan_math.dart';

/// The default goal a new plan opens on: finish in a month.
const defaultPlanDays = 30;

/// Offered as one-tap chips next to the date field.
const planDayPresets = [30, 60, 90];

/// Why a draft cannot become a plan yet.
///
/// The UI clamps as it edits, so these are unreachable through the steppers and
/// the date picker; they exist because a draft can also be built from stored
/// values, and a silent bad plan is worse than a stated one.
enum PlanDraftProblem {
  /// Start page outside 1..pageCount.
  startPageOutOfRange,

  /// A finish date earlier than the day the plan starts.
  targetDateBeforeStart,

  /// A daily quota of zero or less, which would never finish the book.
  pagesPerDayTooSmall,
}

class PlanDraft {
  const PlanDraft({
    required this.pageCount,
    required this.mode,
    required this.startPage,
    required this.startDate,
    required this.targetEndDate,
    required this.pagesPerDay,
  });

  /// A fresh draft for a book: the whole book, from today, in a month.
  factory PlanDraft.forBook({
    required int pageCount,
    required DateTime today,
    int days = defaultPlanDays,
  }) {
    final start = dateOnly(today);
    return PlanDraft(
      pageCount: pageCount,
      mode: PlanMode.byDeadline,
      startPage: 1,
      startDate: start,
      targetEndDate: addDays(start, days - 1),
      // Seeded from the deadline so switching to the other mode lands on the
      // same plan rather than on an arbitrary number.
      pagesPerDay: (pageCount + days - 1) ~/ days,
    );
  }

  /// Reopens an existing plan for editing.
  ///
  /// [startDate] is kept as it was: a plan that began three weeks ago is still
  /// three weeks old, and moving it would rewrite the reader's history.
  factory PlanDraft.fromSpec(PlanSpec spec, {required int pageCount}) {
    return PlanDraft(
      pageCount: pageCount,
      mode: spec.mode,
      startPage: spec.startPage,
      startDate: spec.startDate,
      targetEndDate: spec.targetEndDate,
      pagesPerDay: spec.pagesPerDay,
    );
  }

  /// Pages in the whole PDF. The plan's end page is always the last one; a
  /// reader who wants to stop early simply stops.
  final int pageCount;

  final PlanMode mode;

  /// 1-based physical page the plan starts at, so front matter can be skipped.
  final int startPage;

  final DateTime startDate;

  /// Only meaningful in [PlanMode.byDeadline], but carried in both modes so
  /// flipping back and forth does not lose the reader's answer.
  final DateTime targetEndDate;

  /// Only meaningful in [PlanMode.byPagesPerDay]. Carried in both, as above.
  final int pagesPerDay;

  /// Pages the plan actually covers.
  int get totalPages => pageCount - startPage + 1;

  PlanDraftProblem? get problem {
    if (startPage < 1 || startPage > pageCount) {
      return PlanDraftProblem.startPageOutOfRange;
    }
    // Each mode is judged on the field it actually uses; a stale value in the
    // other one must not block a plan the reader can see is fine.
    return switch (mode) {
      PlanMode.byDeadline => daysBetween(startDate, targetEndDate) < 0
          ? PlanDraftProblem.targetDateBeforeStart
          : null,
      PlanMode.byPagesPerDay => pagesPerDay < 1
          ? PlanDraftProblem.pagesPerDayTooSmall
          : null,
    };
  }

  bool get isValid => problem == null;

  /// The resolved plan, or null while the draft is unusable.
  ///
  /// This is what the preview renders, so the reader is reading the same
  /// numbers that will be saved rather than a separate estimate.
  PlanSpec? get spec {
    if (problem != null) return null;
    return switch (mode) {
      PlanMode.byDeadline => PlanSpec.fromDeadline(
        startPage: startPage,
        endPage: pageCount,
        startDate: startDate,
        targetEndDate: targetEndDate,
      ),
      PlanMode.byPagesPerDay => PlanSpec.fromPagesPerDay(
        startPage: startPage,
        endPage: pageCount,
        startDate: startDate,
        pagesPerDay: pagesPerDay,
      ),
    };
  }

  /// Switches modes, carrying the current plan across.
  ///
  /// Going from "finish by 3 November" to "pages a day" starts at the 12 pages
  /// that deadline implied, and back again returns the date those 12 pages
  /// reach. Anything else makes the toggle feel like it discards the answer.
  PlanDraft withMode(PlanMode next) {
    if (next == mode) return this;
    final current = spec;
    if (current == null) return copyWith(mode: next);
    return switch (next) {
      PlanMode.byPagesPerDay => copyWith(
        mode: next,
        pagesPerDay: current.pagesPerDay,
      ),
      PlanMode.byDeadline => copyWith(
        mode: next,
        targetEndDate: current.targetEndDate,
      ),
    };
  }

  /// Clamped to the book. The quota is re-clamped too, because skipping 40
  /// pages of front matter can leave fewer pages than the reader had asked for
  /// in a day.
  PlanDraft withStartPage(int page) {
    final clamped = page.clamp(1, pageCount);
    return copyWith(
      startPage: clamped,
      pagesPerDay: pagesPerDay.clamp(1, pageCount - clamped + 1),
    );
  }

  /// Clamped to the plan's own length: a quota larger than the book is just
  /// "finish it today" spelled confusingly.
  PlanDraft withPagesPerDay(int pages) =>
      copyWith(pagesPerDay: pages.clamp(1, totalPages));

  /// Never earlier than the start date; the picker enforces the same bound.
  PlanDraft withTargetEndDate(DateTime date) {
    final day = dateOnly(date);
    return copyWith(
      targetEndDate: daysBetween(startDate, day) < 0 ? startDate : day,
    );
  }

  /// Finish in [days] calendar days counting today, for the preset chips.
  PlanDraft withDayCount(int days) =>
      withTargetEndDate(addDays(startDate, (days < 1 ? 1 : days) - 1));

  /// True when [days] is exactly what the draft currently targets, so the
  /// matching chip can show as selected.
  bool matchesDayCount(int days) =>
      inclusiveDayCount(startDate, targetEndDate) == days;

  PlanDraft copyWith({
    PlanMode? mode,
    int? startPage,
    DateTime? startDate,
    DateTime? targetEndDate,
    int? pagesPerDay,
  }) {
    return PlanDraft(
      pageCount: pageCount,
      mode: mode ?? this.mode,
      startPage: startPage ?? this.startPage,
      startDate: startDate ?? this.startDate,
      targetEndDate: targetEndDate ?? this.targetEndDate,
      pagesPerDay: pagesPerDay ?? this.pagesPerDay,
    );
  }
}
