import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/db/app_database.dart';
import '../../../core/format/app_dates.dart';
import '../../../core/format/app_durations.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/widgets/cover_plate.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/figure.dart';
import '../../../core/widgets/kicker.dart';
import '../../../core/widgets/progress_shapes.dart';
import '../../../core/widgets/reading_calendar_grid.dart';
import '../../../core/widgets/screen_header.dart';
import '../../../l10n/app_localizations.dart';
import '../../plan/application/plan_providers.dart';
import '../application/book_detail_providers.dart';
import '../domain/book_progress.dart';

/// Screen 9 — one book, its goal, and how it is actually going.
///
/// The order is the order the reader asks the questions in: how far am I, what
/// did I sign up for, when will I actually finish, which days did I read. The
/// actions come last, because none of them is why the screen was opened.
class BookDetailScreen extends ConsumerWidget {
  const BookDetailScreen({required this.bookId, super.key});

  final String bookId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final book = ref.watch(bookProvider(bookId)).value;
    final plan = ref.watch(activePlanProvider(bookId)).value;
    final progress = ref.watch(bookProgressProvider(plan)).value;

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // No title: the book's own title sets two lines below, and naming
            // it twice would make the arrow read as chrome from another screen.
            const ScreenBackBar(),
            Expanded(
              child: book == null
                  ? const SizedBox.shrink()
                  : ListView(
                      padding: const EdgeInsets.fromLTRB(
                        AppSpacing.gutter,
                        0,
                        AppSpacing.gutter,
                        AppSpacing.x8,
                      ),
                      children: [
                        _Masthead(book: book, plan: plan),
                        const SizedBox(height: AppSpacing.x4 + 2),
                        if (plan == null || progress == null)
                          _NoPlan(bookId: bookId)
                        else ...[
                          _Progress(progress: progress),
                          const SizedBox(height: AppSpacing.x6 - 6),
                          _PlanCard(progress: progress),
                          const SizedBox(height: AppSpacing.x4 + 2),
                          _ReadingDays(plan: plan),
                          const SizedBox(height: AppSpacing.x4 + 2),
                        ],
                        _Actions(book: book, plan: plan),
                        const SizedBox(height: AppSpacing.x4),
                        _DeleteBook(bookId: bookId),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Cover, title, author, and the two facts that never change: how long the
/// book is, and when the reader started it.
class _Masthead extends StatelessWidget {
  const _Masthead({required this.book, required this.plan});

  final Book book;
  final ReadingPlan? plan;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final locale = Localizations.localeOf(context);

    final started = plan == null
        ? null
        : l10n.bookStartedOn(AppDates.dayAndMonth(plan!.startDate, locale));

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const CoverPlate(width: 58, height: 80),
        const SizedBox(width: AppSpacing.x3),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                book.title,
                style: theme.textTheme.titleLarge,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              if (book.author case final author?)
                Text(
                  author,
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontSize: 12.5,
                    color: theme.appColors.muted,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              const SizedBox(height: AppSpacing.x1),
              Text(
                [l10n.bookPageCount(book.pageCount), ?started].join(' · '),
                style: theme.textTheme.bodySmall?.copyWith(
                  fontSize: 11.5,
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

/// The percentage at display size, over the book-scope rule.
///
/// The figure is the largest thing on the screen because it answers the
/// question the reader opened it with. The pages beside it state the same fact
/// exactly, for the reader who wants the number rather than the impression.
class _Progress extends StatelessWidget {
  const _Progress({required this.progress});

  final BookProgress progress;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Figure(
              AppNumbers.percent(progress.fraction),
              size: 60,
              height: 0.82,
              // Green is completion and nothing else, so it appears here only
              // once the whole plan is read — never as "you are doing well".
              color: progress.isComplete
                  ? theme.appColors.done
                  : theme.colorScheme.onSurface,
            ),
            const SizedBox(width: AppSpacing.x3),
            Expanded(
              child: Padding(
                // Sits the caption on the percentage's baseline rather than on
                // its descender.
                padding: const EdgeInsets.only(bottom: 6),
                child: Text(
                  '${l10n.bookOfTheBook}\n'
                  '${l10n.libraryReadOfTotal(progress.pagesRead, progress.totalPages)}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontSize: 12.5,
                    height: 1.6,
                    color: theme.appColors.muted,
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.x2),
        BookRule(fraction: progress.fraction, height: 2),
      ],
    );
  }
}

/// The goal, and the date it now points at.
///
/// This is the only place in the app that mentions lateness, and it says it as
/// a date: the daily portion is fixed, so missing days moves the finish and
/// nothing else. No red, no percentage, no broken streak.
class _PlanCard extends StatelessWidget {
  const _PlanCard({required this.progress});

  final BookProgress progress;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final locale = Localizations.localeOf(context);
    final colors = theme.appColors;

    final aside = theme.textTheme.bodySmall?.copyWith(
      fontSize: 12.5,
      height: 1.85,
      color: colors.muted,
    );

    return Container(
      padding: const EdgeInsets.all(AppSpacing.x3),
      decoration: BoxDecoration(
        // A hairline, not a shadow: nothing in this app floats.
        border: Border.all(color: colors.hairline),
        borderRadius: BorderRadius.circular(AppSpacing.radius),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Kicker(l10n.bookPlanSection),
          const SizedBox(height: AppSpacing.x2 + 2),
          Text(
            '${l10n.libraryDailyPortion(progress.pagesPerDay)} · '
            '${l10n.bookSessionCount(progress.sessionCount)}',
            style: theme.textTheme.bodyMedium?.copyWith(height: 1.75),
          ),
          const SizedBox(height: AppSpacing.x3 - 2),
          const Divider(height: 1),
          const SizedBox(height: AppSpacing.x3 - 2),
          Text(
            l10n.progressProjectedEnd(
              AppDates.dayAndMonth(progress.projectedEndDate, locale),
            ),
            style: theme.textTheme.bodyMedium?.copyWith(
              fontSize: 13.5,
              height: 1.85,
            ),
          ),
          // Stated only when it is true. A book that is on time says nothing
          // about time, which is the whole point of the rule.
          if (progress.isLate)
            Text(
              l10n.bookTargetWas(
                AppDates.dayAndMonth(progress.targetEndDate, locale),
              ),
              style: aside,
            ),
          if (progress.pausedAt case final pausedAt?)
            Text(
              l10n.bookPausedSince(AppDates.dayAndMonth(pausedAt, locale)),
              style: aside,
            ),
          // Said only once something has actually been timed. A book read
          // before the clock existed would otherwise be told it took no time
          // at all, which is a measurement nobody made.
          if (progress.hasTimeReading)
            Text(
              l10n.bookTimeReading(
                AppDurations.compact(progress.timeReading, l10n),
              ),
              style: aside,
            ),
        ],
      ),
    );
  }
}

/// The reading calendar: seventy days, densest where the reading was.
class _ReadingDays extends ConsumerWidget {
  const _ReadingDays({required this.plan});

  final ReadingPlan plan;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final colors = Theme.of(context).appColors;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Kicker(l10n.bookReadingDays, color: colors.muted),
        const SizedBox(height: AppSpacing.x2 + 2),
        ReadingCalendarGrid(columns: ref.watch(bookHeatmapProvider(plan))),
        // Under the grid, because it is the same question asked in detail:
        // the squares say which days, the record says what was in them.
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: TextButton(
            onPressed: () => context.push('/books/${plan.bookId}/record'),
            child: Text(l10n.bookSeeRecord),
          ),
        ),
      ],
    );
  }
}

/// A book that has no goal yet. The screen has nothing to report, so it asks
/// for the one thing that would give it something.
class _NoPlan extends StatelessWidget {
  const _NoPlan({required this.bookId});

  final String bookId;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.x6),
      child: EmptyState(
        title: l10n.bookNoPlanTitle,
        message: l10n.bookNoPlanHint,
        action: OutlinedButton(
          onPressed: () => context.push('/books/$bookId/plan'),
          child: Text(l10n.planCreate),
        ),
      ),
    );
  }
}

/// What the reader can do to the book from here.
///
/// The set changes with the shelf the book is on, rather than greying out the
/// actions that do not apply: a finished book cannot be paused, and offering a
/// disabled "pause" would only pose a question with no answer.
class _Actions extends ConsumerWidget {
  const _Actions({required this.book, required this.plan});

  final Book book;
  final ReadingPlan? plan;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final actions = ref.read(bookActionsProvider);

    Future<void> setStatus(BookStatus status) =>
        actions.setStatus(book.id, status);

    return switch (book.status) {
      BookStatus.finished => _ActionRow(
        children: [
          _Action(
            primary: true,
            label: l10n.bookReturnToReading,
            onPressed: () => setStatus(BookStatus.reading),
          ),
        ],
      ),
      BookStatus.reading when plan != null => _ActionRow(
        children: [
          _Action(
            primary: true,
            label: l10n.planEdit,
            onPressed: () => context.push('/books/${book.id}/plan'),
          ),
          if (plan!.pausedAt == null)
            _Action(
              label: l10n.bookPause,
              onPressed: () => actions.pause(plan!.id),
            )
          else
            _Action(
              label: l10n.bookResume,
              onPressed: () => actions.resume(plan!.id),
            ),
          _Action(
            label: l10n.bookMarkFinished,
            onPressed: () => setStatus(BookStatus.finished),
          ),
        ],
      ),
      // No plan: `_NoPlan` above already carries the only useful action, so
      // repeating it here would put the same button on screen twice.
      BookStatus.reading => const SizedBox.shrink(),
    };
  }
}

/// Removing the book, in two taps.
///
/// The first tap does nothing but ask, and the second one is the only place in
/// this screen that speaks in the error colour. Two taps rather than a
/// confirmation dialog: the sentence explaining what is about to be lost is
/// longer than a dialog would hold, and it belongs next to the button rather
/// than on top of the screen it is about.
class _DeleteBook extends ConsumerStatefulWidget {
  const _DeleteBook({required this.bookId});

  final String bookId;

  @override
  ConsumerState<_DeleteBook> createState() => _DeleteBookState();
}

class _DeleteBookState extends ConsumerState<_DeleteBook> {
  var _asking = false;
  var _busy = false;

  Future<void> _delete() async {
    setState(() => _busy = true);
    await ref.read(bookActionsProvider).delete(widget.bookId);

    // Back to the shelf. Staying would leave the reader looking at a screen
    // about a book that no longer exists.
    //
    // `maybePop`, the same way the back arrow leaves: it asks the navigator
    // rather than the router, so it is right whether this screen was pushed
    // from the library, from today, or from a tapped reminder.
    if (mounted) await Navigator.of(context).maybePop();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);

    if (!_asking) {
      return Align(
        alignment: AlignmentDirectional.centerStart,
        child: TextButton(
          onPressed: () => setState(() => _asking = true),
          style: TextButton.styleFrom(foregroundColor: theme.appColors.muted),
          child: Text(l10n.bookDelete),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.bookDeleteConfirm,
          style: theme.textTheme.bodySmall?.copyWith(
            height: 1.7,
            color: theme.appColors.muted,
          ),
        ),
        const SizedBox(height: AppSpacing.x2),
        _ActionRow(
          children: [
            OutlinedButton(
              onPressed: _busy ? null : _delete,
              style: OutlinedButton.styleFrom(
                minimumSize: const Size(0, 42),
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.x1),
                textStyle: theme.textTheme.labelLarge?.copyWith(fontSize: 13),
                foregroundColor: theme.colorScheme.error,
                side: BorderSide(color: theme.colorScheme.error),
              ),
              child: Text(
                l10n.bookDeleteYes,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            _Action(
              label: l10n.actionCancel,
              onPressed: _busy ? () {} : () => setState(() => _asking = false),
            ),
          ],
        ),
      ],
    );
  }
}

class _ActionRow extends StatelessWidget {
  const _ActionRow({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (final (index, child) in children.indexed) ...[
          if (index > 0) const SizedBox(width: AppSpacing.x2 - 1),
          Expanded(child: child),
        ],
      ],
    );
  }
}

class _Action extends StatelessWidget {
  const _Action({
    required this.label,
    required this.onPressed,
    this.primary = false,
  });

  final String label;
  final VoidCallback onPressed;

  /// Gold outline and gold label. Exactly one action per row is primary.
  final bool primary;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return OutlinedButton(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(0, 42),
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.x1),
        textStyle: theme.textTheme.labelLarge?.copyWith(
          fontSize: 13,
          fontWeight: primary ? FontWeight.w500 : FontWeight.w400,
        ),
        foregroundColor: primary
            ? theme.colorScheme.primary
            : theme.colorScheme.onSurfaceVariant,
        side: BorderSide(
          color: primary
              ? theme.appColors.accentStroke
              : theme.appColors.hairline,
        ),
      ),
      child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
    );
  }
}
