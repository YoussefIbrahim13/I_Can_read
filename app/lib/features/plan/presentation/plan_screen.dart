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
import '../../../core/widgets/screen_header.dart';
import '../../../core/widgets/segmented_control.dart';
import '../../../core/widgets/stepper_field.dart';
import '../../../l10n/app_localizations.dart';
import '../application/plan_providers.dart';
import '../domain/plan_draft.dart';

/// Screen 6 — set a goal for a book.
///
/// The preview is the screen: the sentence at the top is the whole plan in
/// words, and every control below only moves that sentence. The reader should
/// never have to assemble the outcome from three separate fields.
class PlanScreen extends ConsumerWidget {
  const PlanScreen({required this.bookId, super.key});

  final String bookId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final book = ref.watch(bookProvider(bookId));
    final plan = ref.watch(activePlanProvider(bookId));

    // Both are needed before the form can be seeded — the book for its page
    // count, the plan to decide whether this is a first goal or an edit.
    final loaded = book.hasValue && plan.hasValue;

    return Scaffold(
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ScreenBackBar(
              title: plan.value == null ? l10n.planCreate : l10n.planEdit,
            ),
            const Divider(),
            Expanded(
              child: switch ((loaded, book.value)) {
                (false, _) => const SizedBox.shrink(),
                (true, null) => const SizedBox.shrink(),
                (true, final found?) => _PlanForm(
                  book: found,
                  existing: plan.value,
                ),
              },
            ),
          ],
        ),
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
        today: DateTime.now(),
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

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final spec = _draft.spec;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _PreviewBand(book: widget.book, draft: _draft),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.gutter,
              AppSpacing.x6 - 4,
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
              const SizedBox(height: AppSpacing.x6 - 2),
              if (_draft.mode == PlanMode.byDeadline)
                _DeadlineFields(
                  draft: _draft,
                  onPickDate: _pickDate,
                  onPreset: (days) => _edit(_draft.withDayCount(days)),
                )
              else
                _PagesPerDayField(
                  draft: _draft,
                  onChanged: (pages) => _edit(_draft.withPagesPerDay(pages)),
                ),
              const SizedBox(height: AppSpacing.x6 - 2),
              const Divider(),
              const SizedBox(height: AppSpacing.x4),
              _StartPageField(
                draft: _draft,
                onChanged: (page) => _edit(_draft.withStartPage(page)),
              ),
            ],
          ),
        ),
        const Divider(),
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.gutter,
            AppSpacing.x3 - 2,
            AppSpacing.gutter,
            AppSpacing.x4,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              OutlinedButton(
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
            ],
          ),
        ),
      ],
    );
  }
}

/// The hero band: what the plan means, in one sentence, before any control.
class _PreviewBand extends StatelessWidget {
  const _PreviewBand({required this.book, required this.draft});

  final Book book;
  final PlanDraft draft;

  /// Placeholders for the two values the sentence sets apart. Control
  /// characters, so they cannot collide with anything a translator writes.
  static const _pagesSlot = '\u0001';
  static const _dateSlot = '\u0002';

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final locale = Localizations.localeOf(context);
    final theme = Theme.of(context);
    final colors = theme.appColors;
    final spec = draft.spec;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.gutter,
        AppSpacing.x6 - 4,
        AppSpacing.gutter,
        AppSpacing.x6 - 2,
      ),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        border: Border(bottom: BorderSide(color: colors.hairline)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Kicker('${book.title} · ${l10n.bookPageCount(book.pageCount)}'),
          const SizedBox(height: AppSpacing.x3),
          if (spec == null)
            Text(l10n.planCreate, style: theme.textTheme.titleLarge)
          else ...[
            Text.rich(
              TextSpan(
                children: _fill(
                  l10n.planPreview(_pagesSlot, _dateSlot),
                  slots: {
                    // The daily portion is the number the reader is deciding,
                    // so it is the one thing set as a standing figure.
                    _pagesSlot: figureSpan(
                      AppNumbers.format(spec.pagesPerDay),
                      size: 30,
                      color: theme.colorScheme.primary,
                    ),
                    _dateSlot: TextSpan(
                      text: AppDates.dayAndMonth(spec.targetEndDate, locale),
                      style: TextStyle(color: theme.colorScheme.primary),
                    ),
                  },
                ),
              ),
              style: theme.textTheme.titleLarge,
            ),
            const SizedBox(height: AppSpacing.x3 - 2),
            Text(
              '${l10n.planDayCount(inclusiveDayCount(spec.startDate, spec.targetEndDate))} · '
              '${draft.startPage == 1 ? l10n.planTotalPages(spec.totalPages) : l10n.planPagesFromPage(spec.totalPages, draft.startPage)}',
              style: theme.textTheme.bodySmall?.copyWith(
                fontSize: 12.5,
                color: colors.muted,
              ),
            ),
          ],
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
    final spans = <InlineSpan>[];
    var index = 0;

    for (final match in RegExp('[${slots.keys.join()}]').allMatches(template)) {
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

class _DeadlineFields extends StatelessWidget {
  const _DeadlineFields({
    required this.draft,
    required this.onPickDate,
    required this.onPreset,
  });

  final PlanDraft draft;
  final VoidCallback onPickDate;
  final ValueChanged<int> onPreset;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final locale = Localizations.localeOf(context);
    final theme = Theme.of(context);
    final colors = theme.appColors;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.planTargetDate,
          style: theme.textTheme.labelMedium?.copyWith(
            fontSize: 12,
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: AppSpacing.x2 - 1),
        InkWell(
          onTap: onPickDate,
          borderRadius: BorderRadius.circular(AppSpacing.radius),
          child: Container(
            height: 46,
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.x3),
            decoration: BoxDecoration(
              border: Border.all(color: colors.hairline),
              borderRadius: BorderRadius.circular(AppSpacing.radius),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    AppDates.full(draft.targetEndDate, locale),
                    style: theme.textTheme.bodyLarge?.copyWith(fontSize: 15),
                  ),
                ),
                Icon(
                  Icons.calendar_today_outlined,
                  size: 16,
                  color: colors.accentStroke,
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.x3),
        // The presets are the three answers most readers actually want; the
        // picker above is for everyone else.
        Wrap(
          spacing: AppSpacing.x2 - 1,
          runSpacing: AppSpacing.x2 - 1,
          children: [
            for (final days in planDayPresets)
              _PresetChip(
                label: l10n.planDayCount(days),
                selected: draft.matchesDayCount(days),
                onTap: () => onPreset(days),
              ),
          ],
        ),
      ],
    );
  }
}

class _PresetChip extends StatelessWidget {
  const _PresetChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.appColors;

    return Semantics(
      selected: selected,
      button: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(3),
        child: Container(
          height: 32,
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.x3 - 2),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            border: Border.all(
              color: selected ? colors.accentStroke : colors.hairline,
            ),
            borderRadius: BorderRadius.circular(3),
          ),
          child: Text(
            label,
            style: theme.textTheme.labelMedium?.copyWith(
              fontSize: 12,
              color: selected
                  ? theme.colorScheme.primary
                  : theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ),
    );
  }
}

class _PagesPerDayField extends StatelessWidget {
  const _PagesPerDayField({required this.draft, required this.onChanged});

  final PlanDraft draft;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);

    return Row(
      children: [
        Expanded(
          child: Text(
            l10n.planPagesPerDay,
            style: theme.textTheme.bodyLarge?.copyWith(fontSize: 14.5),
          ),
        ),
        StepperField(
          value: draft.pagesPerDay,
          onChanged: onChanged,
          max: draft.totalPages,
          decreaseLabel: l10n.planPagesPerDayFewer,
          increaseLabel: l10n.planPagesPerDayMore,
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
