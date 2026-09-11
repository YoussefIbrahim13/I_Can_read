import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/db/app_database.dart';
import '../../../core/format/app_dates.dart';
import '../../../core/planning/plan_math.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/widgets/figure.dart';
import '../../../core/widgets/kicker.dart';
import '../../../core/widgets/page_sheet.dart';
import '../../../core/widgets/progress_shapes.dart';
import '../../../core/widgets/segmented_control.dart';
import '../../../core/widgets/stepper_field.dart';
import '../../../l10n/app_localizations.dart';
import '../../today/application/today_providers.dart';
import '../application/plan_providers.dart';
import '../domain/plan_draft.dart';

/// Screen 6 — set a goal for a book.
///
/// The preview is the screen: the sentence at the top is the whole plan in
/// words, and every control below only moves that sentence. The reader should
/// never have to assemble the outcome from three separate fields.
///
/// Redesign v2 went further and made the sentence the *only* reading of the
/// plan. There is one slider under it; whichever value the chosen mode owns is
/// what the slider moves, and the other value — the date, the day count, the
/// brass stretch — recomputes as the thumb travels. Fields the reader had to
/// fill in became a sentence they watch change.
class PlanScreen extends ConsumerWidget {
  const PlanScreen({required this.bookId, super.key});

  final String bookId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final book = ref.watch(bookProvider(bookId));
    final plan = ref.watch(activePlanProvider(bookId));

    // Both are needed before the form can be seeded — the book for its page
    // count, the plan to decide whether this is a first goal or an edit.
    final loaded = book.hasValue && plan.hasValue;

    return Scaffold(
      body: SafeArea(
        child: switch ((loaded, book.value)) {
          (false, _) => const SizedBox.shrink(),
          (true, null) => const SizedBox.shrink(),
          (true, final found?) => _PlanForm(book: found, existing: plan.value),
        },
      ),
    );
  }
}

class _PlanForm extends ConsumerStatefulWidget {
  const _PlanForm({required this.book, required this.existing});

  final Book book;

  /// The plan being edited, or null when the book has none yet.
  final ReadingPlan? existing;

  @override
  ConsumerState<_PlanForm> createState() => _PlanFormState();
}

class _PlanFormState extends ConsumerState<_PlanForm> {
  late PlanDraft _draft = _seed();
  var _saving = false;

  PlanDraft _seed() {
    final existing = widget.existing;
    if (existing == null) {
      return PlanDraft.forBook(
        pageCount: widget.book.pageCount,
        // The app's own idea of today, not the wall clock: every other screen
        // reads the day through this provider, and a plan that started from a
        // different "now" than Today uses would be a day out at the boundary.
        today: ref.read(todayProvider),
      );
    }
    return PlanDraft.fromSpec(
      ref.read(appDatabaseProvider).specOf(existing),
      pageCount: widget.book.pageCount,
    );
  }

  void _edit(PlanDraft next) => setState(() => _draft = next);

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _draft.targetEndDate,
      // Finishing before you start is not a goal, so it is not offered.
      firstDate: _draft.startDate,
      lastDate: addDays(_draft.startDate, 365 * 5),
    );
    if (picked != null) _edit(_draft.withTargetEndDate(picked));
  }

  Future<void> _save() async {
    final spec = _draft.spec;
    if (spec == null || _saving) return;

    setState(() => _saving = true);
    try {
      await ref
          .read(planWriterProvider)
          .save(bookId: widget.book.id, spec: spec);
    } finally {
      // Released even though the screen normally leaves straight afterwards:
      // if the pop does not happen, a button stuck disabled would strand the
      // reader on a form they can no longer submit.
      if (mounted) setState(() => _saving = false);
    }

    if (!mounted) return;

    // A brand new plan continues to its sessions, replacing this screen: the
    // reader is setting one thing up, and backing out of the sessions should
    // land them where they started rather than back on the goal they just set.
    final router = GoRouter.maybeOf(context);
    if (widget.existing == null && router != null) {
      // The returned future completes when the sessions screen pops, which
      // this screen no longer exists to care about.
      unawaited(
        router.pushReplacement('/books/${widget.book.id}/plan/sessions'),
      );
      return;
    }

    // Plain `Navigator`, not `context.pop()`: go_router's extension throws
    // when the screen is hosted without a router, and this one is a leaf that
    // does not otherwise care which navigator pushed it.
    final navigator = Navigator.of(context);
    if (navigator.canPop()) navigator.pop();
  }

  /// Moves whichever value this mode owns. The other one is derived, so the
  /// slider is the single control the sentence answers to.
  void _slideTo(int value) => _edit(
    _draft.mode == PlanMode.byPagesPerDay
        ? _draft.withPagesPerDay(value)
        : _draft.withDayCount(value),
  );

  /// What the slider currently reads.
  int get _sliderValue => _draft.mode == PlanMode.byPagesPerDay
      ? _draft.pagesPerDay
      : inclusiveDayCount(_draft.startDate, _draft.targetEndDate);

  /// The far end of the track.
  ///
  /// Not the true maximum — a 900-page book at one page per pixel would make
  /// the slider useless for the range anyone actually picks from. The track
  /// covers the usual answers, and stretches to hold a stored plan that is
  /// already past it, so reopening an unusual goal never pins the thumb at the
  /// end and quietly rewrites it.
  int get _sliderMax {
    final reach = _draft.mode == PlanMode.byPagesPerDay
        ? (_draft.totalPages < 100 ? _draft.totalPages : 100)
        : 180;
    final value = _sliderValue;
    return value > reach ? value : reach;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final spec = _draft.spec;
    final byPages = _draft.mode == PlanMode.byPagesPerDay;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Masthead(
          book: widget.book,
          title: widget.existing == null ? l10n.planCreate : l10n.planEdit,
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.gutter,
              0,
              AppSpacing.gutter,
              AppSpacing.x6,
            ),
            children: [
              AppSegmentedControl<PlanMode>(
                value: _draft.mode,
                onChanged: (mode) => _edit(_draft.withMode(mode)),
                segments: [
                  AppSegment(
                    value: PlanMode.byDeadline,
                    label: l10n.planModeByDeadline,
                  ),
                  AppSegment(
                    value: PlanMode.byPagesPerDay,
                    label: l10n.planModeByPagesPerDay,
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.x4),
              _Dial(
                draft: _draft,
                value: _sliderValue.toDouble(),
                max: _sliderMax.toDouble(),
                onChanged: _slideTo,
                onPickDate: _pickDate,
                onPickMode: (mode) => _edit(_draft.withMode(mode)),
                stepLabels: byPages
                    ? (l10n.planPagesPerDayFewer, l10n.planPagesPerDayMore)
                    : (l10n.planDaysFewer, l10n.planDaysMore),
              ),
              const SizedBox(height: AppSpacing.x6 - 4),
              const Divider(),
              const SizedBox(height: AppSpacing.x4),
              if (spec != null) _Span(draft: _draft, spec: spec),
              const SizedBox(height: AppSpacing.x4),
              _StartPageField(
                draft: _draft,
                onChanged: (page) => _edit(_draft.withStartPage(page)),
              ),
              const SizedBox(height: AppSpacing.x6 - 4),
              FilledButton(
                onPressed: spec == null || _saving ? null : _save,
                child: Text(
                  widget.existing == null
                      ? l10n.sessionsContinue
                      : l10n.actionSave,
                ),
              ),
              // Only on an edit: a new plan reaches its sessions through the
              // button above, so offering both would be two doors to one room.
              if (widget.existing != null)
                TextButton(
                  onPressed: () => GoRouter.maybeOf(
                    context,
                  )?.push('/books/${widget.book.id}/plan/sessions'),
                  child: Text(l10n.sessionsEdit),
                ),
              const SizedBox(height: AppSpacing.x3),
              // The rule the whole app is built on, said once, where the reader
              // is deciding how hard to push. It is the answer to the question
              // a daily quota always raises.
              Text(
                l10n.planMissedDayNote,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(
                  fontSize: 11.5,
                  height: 1.7,
                  color: theme.appColors.muted,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Cancel, the screen's name, and the book it is about.
class _Masthead extends StatelessWidget {
  const _Masthead({required this.book, required this.title});

  final Book book;
  final String title;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(
        AppSpacing.gutter,
        AppSpacing.x2,
        AppSpacing.gutter,
        AppSpacing.x4,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // A word, not an arrow: this screen is a decision the reader can
          // walk away from, and "cancel" says that where a chevron does not.
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: TextButton(
              onPressed: () => Navigator.of(context).maybePop(),
              style: TextButton.styleFrom(
                foregroundColor: theme.colorScheme.primary,
                minimumSize: const Size(0, AppSpacing.minTapTarget),
                padding: const EdgeInsets.symmetric(horizontal: 4),
              ),
              child: Text(l10n.actionCancel),
            ),
          ),
          const SizedBox(height: AppSpacing.x1),
          Text(title, style: theme.textTheme.headlineMedium),
          const SizedBox(height: 2),
          Text(
            book.title,
            style: theme.textTheme.bodySmall?.copyWith(
              fontSize: 13,
              color: theme.appColors.muted,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

/// The plan as a sentence, with the one control that moves it.
///
/// Set on a page rather than in a card: this is the reader deciding what they
/// are going to do, and v2's page furniture — paper ground, a gutter down the
/// spine — is how the app says "this is about reading".
///
/// Both figures in the sentence are underlined in brass because both are live:
/// tapping the date opens the picker, and tapping either one hands the slider
/// over to that value. The mode slab above does the same thing more plainly;
/// this is the shortcut for a reader who is already looking at the number they
/// want to change.
class _Dial extends StatelessWidget {
  const _Dial({
    required this.draft,
    required this.value,
    required this.max,
    required this.onChanged,
    required this.onPickDate,
    required this.onPickMode,
    required this.stepLabels,
  });

  final PlanDraft draft;
  final double value;
  final double max;
  final ValueChanged<int> onChanged;
  final VoidCallback onPickDate;
  final ValueChanged<PlanMode> onPickMode;

  /// Decrease and increase, spoken — the two keys carry a glyph only.
  final (String, String) stepLabels;

  /// Placeholders for the two values the sentence sets apart. Same shape as
  /// `figureMarker`: visible ASCII, so a failing test prints the marker rather
  /// than an invisible byte, and clearly not something a translator would type.
  static const _pagesSlot = '{#pages}';
  static const _dateSlot = '{#date}';

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final locale = Localizations.localeOf(context);
    final theme = Theme.of(context);
    final spec = draft.spec;

    return PageSheet(
      padding: const EdgeInsetsDirectional.fromSTEB(26, 20, 18, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (spec == null)
            Text(l10n.planCreate, style: theme.textTheme.titleLarge)
          else
            Text.rich(
              TextSpan(
                children: _fill(
                  l10n.planPreview(_pagesSlot, _dateSlot),
                  slots: {
                    // The daily portion is the number the reader is deciding,
                    // so it is the one thing set as a standing figure.
                    _pagesSlot: WidgetSpan(
                      alignment: PlaceholderAlignment.baseline,
                      baseline: TextBaseline.alphabetic,
                      child: _Live(
                        onTap: () => onPickMode(PlanMode.byPagesPerDay),
                        child: Figure.number(
                          spec.pagesPerDay,
                          size: 26,
                          color: theme.colorScheme.primary,
                        ),
                      ),
                    ),
                    _dateSlot: WidgetSpan(
                      alignment: PlaceholderAlignment.baseline,
                      baseline: TextBaseline.alphabetic,
                      child: _Live(
                        onTap: onPickDate,
                        child: Text(
                          AppDates.dayAndMonth(spec.targetEndDate, locale),
                          style: theme.textTheme.titleLarge?.copyWith(
                            color: theme.colorScheme.primary,
                          ),
                        ),
                      ),
                    ),
                  },
                ),
              ),
              style: theme.textTheme.titleLarge?.copyWith(height: 1.8),
            ),
          const SizedBox(height: AppSpacing.x4),
          Row(
            children: [
              _Step(
                icon: Icons.remove,
                label: stepLabels.$1,
                onPressed: value > 1 ? () => onChanged(value.round() - 1) : null,
              ),
              Expanded(
                child: Slider(
                  value: value.clamp(1, max),
                  min: 1,
                  max: max,
                  // One stop per page, or per day: the reader is choosing a
                  // whole number, and a continuous track would let the thumb
                  // sit between two answers.
                  divisions: max > 1 ? (max - 1).round() : null,
                  onChanged: (next) => onChanged(next.round()),
                ),
              ),
              _Step(
                icon: Icons.add,
                label: stepLabels.$2,
                onPressed: value < max
                    ? () => onChanged(value.round() + 1)
                    : null,
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.x2),
          Text(
            l10n.planSliderHint,
            style: theme.textTheme.bodySmall?.copyWith(
              fontSize: 11.5,
              height: 1.6,
              color: theme.appColors.muted,
            ),
          ),
        ],
      ),
    );
  }

  /// Splits a translated sentence on its slot markers and swaps in spans.
  ///
  /// Substituting widgets rather than strings is what lets the page count keep
  /// its own font and direction inside an Arabic sentence, without breaking the
  /// sentence into fragments a translator cannot reorder.
  static List<InlineSpan> _fill(
    String template, {
    required Map<String, InlineSpan> slots,
  }) {
    final pattern = RegExp(slots.keys.map(RegExp.escape).join('|'));
    final spans = <InlineSpan>[];
    var index = 0;

    for (final match in pattern.allMatches(template)) {
      if (match.start > index) {
        spans.add(TextSpan(text: template.substring(index, match.start)));
      }
      spans.add(slots[match[0]]!);
      index = match.end;
    }
    if (index < template.length) {
      spans.add(TextSpan(text: template.substring(index)));
    }
    return spans;
  }
}

/// A value inside the sentence that answers to a tap, marked by the brass rule
/// under it — the printed convention for "this is the blank being filled in".
class _Live extends StatelessWidget {
  const _Live({required this.child, required this.onTap});

  final Widget child;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(color: Theme.of(context).appColors.accentStroke),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 3),
          child: child,
        ),
      ),
    );
  }
}

/// One of the two square keys flanking the slider, for the reader who wants
/// exactly one more rather than whatever the thumb lands on.
class _Step extends StatelessWidget {
  const _Step({
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final enabled = onPressed != null;

    return Semantics(
      button: true,
      label: label,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(AppSpacing.radius),
        child: Container(
          width: AppSpacing.minTapTarget,
          height: AppSpacing.minTapTarget,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            border: Border.all(color: theme.appColors.hairline),
            borderRadius: BorderRadius.circular(AppSpacing.radius),
          ),
          child: Icon(
            icon,
            size: 17,
            // Disabled loses opacity rather than turning grey — grey is
            // exactly what v2 removed from the palette.
            color: enabled
                ? theme.colorScheme.onSurfaceVariant
                : theme.appColors.muted.withValues(alpha: 0.4),
          ),
        ),
      ),
    );
  }
}

/// What the plan covers, drawn on the book: the brass stretch, its two ends,
/// and what it adds up to.
class _Span extends StatelessWidget {
  const _Span({required this.draft, required this.spec});

  final PlanDraft draft;
  final PlanSpec spec;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final caption = theme.textTheme.bodySmall?.copyWith(
      fontSize: 12,
      color: theme.appColors.muted,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Kicker(l10n.planSpanSection, color: theme.appColors.muted),
        const SizedBox(height: AppSpacing.x2 + 2),
        BookComb.span(
          from: spec.startPage,
          to: spec.endPage,
          of: draft.pageCount,
        ),
        const SizedBox(height: AppSpacing.x2),
        Row(
          children: [
            Expanded(
              child: Text(
                l10n.planSpanRange(spec.startPage, spec.endPage),
                style: caption,
              ),
            ),
            Text(
              '${l10n.planDayCount(inclusiveDayCount(spec.startDate, spec.targetEndDate))}'
              ' · ${l10n.planTotalPages(spec.totalPages)}',
              style: caption,
            ),
          ],
        ),
      ],
    );
  }
}

class _StartPageField extends StatelessWidget {
  const _StartPageField({required this.draft, required this.onChanged});

  final PlanDraft draft;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                l10n.planStartPage,
                style: theme.textTheme.bodyLarge?.copyWith(fontSize: 14.5),
              ),
              Text(
                l10n.planStartPageHint,
                style: theme.textTheme.bodySmall?.copyWith(
                  fontSize: 11.5,
                  color: theme.appColors.muted,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: AppSpacing.x3),
        StepperField(
          value: draft.startPage,
          onChanged: onChanged,
          max: draft.pageCount,
          decreaseLabel: l10n.planPageFewer,
          increaseLabel: l10n.planPageMore,
        ),
      ],
    );
  }
}
