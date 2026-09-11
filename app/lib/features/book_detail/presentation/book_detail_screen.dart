import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/db/app_database.dart';
import '../../../core/format/app_dates.dart';
import '../../../core/format/app_durations.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/figure.dart';
import '../../../core/widgets/kicker.dart';
import '../../../core/widgets/progress_shapes.dart';
import '../../../core/widgets/reading_calendar_grid.dart';
import '../../../l10n/app_localizations.dart';
import '../../plan/application/plan_providers.dart';
import '../application/book_detail_providers.dart';
import '../domain/book_progress.dart';

/// Screen 9 — one book, its goal, and how it is actually going.
///
/// The order is the order the reader asks the questions in: how far am I, what
/// did I sign up for, when will I actually finish, which days did I read. The
/// actions come last, because none of them is why the screen was opened.
///
/// Redesign v2 took the boxes off. The cover plate, the bordered plan card and
/// the ruled progress bar are gone; what is left is a title, the book drawn at
/// page resolution as a [BookComb], and three sections separated by hairlines.
/// A screen about one book should look like a page from it, not like a form.
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
        child: book == null
            ? const SizedBox.shrink()
            : ListView(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.gutter,
                  AppSpacing.x3,
                  AppSpacing.gutter,
                  AppSpacing.x8,
                ),
                children: [
                  const _Breadcrumb(),
                  const SizedBox(height: AppSpacing.x4),
                  _Masthead(book: book),
                  const SizedBox(height: AppSpacing.x4),
                  if (plan == null || progress == null)
                    _NoPlan(bookId: bookId)
                  else ...[
                    _Progress(progress: progress),
                    const SizedBox(height: AppSpacing.x6 - 6),
                    const Divider(),
                    const SizedBox(height: AppSpacing.x4),
                    _PlanSection(book: book, plan: plan, progress: progress),
                    const SizedBox(height: AppSpacing.x4),
                    const Divider(),
                    const SizedBox(height: AppSpacing.x4),
                    _ReadingDays(plan: plan),
                    const SizedBox(height: AppSpacing.x6 - 4),
                  ],
                  _Actions(book: book, plan: plan),
                  const SizedBox(height: AppSpacing.x4),
                  _DeleteBook(bookId: bookId),
                ],
              ),
      ),
    );
  }
}

/// The way back, set as a breadcrumb rather than an arrow in a bar.
///
/// v2 dropped the back bar here: it was 56 points of chrome above a screen
/// whose own title starts the page, and the arrow said nothing about where it
/// went. This says it. It still leaves by [Navigator.maybePop], so it is right
/// however the screen was reached.
class _Breadcrumb extends StatelessWidget {
  const _Breadcrumb();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);

    return Align(
      alignment: AlignmentDirectional.centerStart,
      child: InkWell(
        onTap: () => Navigator.of(context).maybePop(),
        borderRadius: BorderRadius.circular(AppSpacing.radius),
        child: Padding(
          // Keeps the 44pt target the arrow used to have, without drawing a
          // control around six small words.
          padding: const EdgeInsets.symmetric(vertical: 11, horizontal: 4),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // `chevron_left` carries `matchTextDirection`, so it points the
              // right way under RTL without a manual flip.
              Icon(Icons.chevron_left, size: 15, color: theme.appColors.muted),
              const SizedBox(width: 2),
              Text(
                l10n.navLibrary,
                style: theme.textTheme.bodySmall?.copyWith(
                  fontSize: 12,
                  color: theme.appColors.muted,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Title and author, set as the page's own masthead.
class _Masthead extends StatelessWidget {
  const _Masthead({required this.book});

  final Book book;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          book.title,
          style: theme.textTheme.headlineMedium,
          maxLines: 3,
          overflow: TextOverflow.ellipsis,
        ),
        if (book.author case final author?) ...[
          const SizedBox(height: 2),
          Text(
            author,
            style: theme.textTheme.bodySmall?.copyWith(
              fontSize: 13,
              color: theme.appColors.muted,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ],
    );
  }
}

/// The whole book as a run of pages, and the percentage standing under it.
///
/// The comb is the point: 46% is a number the reader has to convert into a
/// feeling, and the comb *is* the feeling — this much inked, that much to go,
/// and a brass rule at the place they stopped. The figure is kept because some
/// readers want the number, and the page count because some want the fact.
class _Progress extends StatelessWidget {
  const _Progress({required this.progress});

  final BookProgress progress;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final caption = theme.textTheme.bodySmall?.copyWith(
      fontSize: 12.5,
      color: theme.appColors.muted,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        BookComb.progress(fraction: progress.fraction),
        const SizedBox(height: AppSpacing.x3),
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Figure.number(
              (progress.fraction * 100).round(),
              size: 44,
              height: 0.82,
              // Green is completion and nothing else, so it appears here only
              // once the whole plan is read — never as "you are doing well".
              color: progress.isComplete
                  ? theme.appColors.done
                  : theme.colorScheme.onSurface,
            ),
            const SizedBox(width: AppSpacing.x2),
            // Both captions flex. Neither is load-bearing enough to push the
            // other off the screen, and between a long translation and a large
            // text scale there are two ways for them not to fit.
            Flexible(
              child: Padding(
                // Sits the caption on the percentage's baseline rather than on
                // its descender.
                padding: const EdgeInsets.only(bottom: 5),
                child: Text(
                  l10n.bookOfTheBook,
                  style: caption,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.x2),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(bottom: 5),
                child: Text(
                  l10n.libraryReadOfTotal(
                    progress.pagesRead,
                    progress.totalPages,
                  ),
                  style: caption,
                  textAlign: TextAlign.end,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// The goal, and the date it now points at.
///
/// This is the only place in the app that mentions lateness, and it says it as
/// a date: the daily portion is fixed, so missing days moves the finish and
/// nothing else. No red, no percentage, no broken streak.
///
/// v2 unboxed it. The border made the plan look like a thing you had to fill
/// in; between two hairlines it reads as a paragraph about the book, which is
/// what it is.
class _PlanSection extends StatelessWidget {
  const _PlanSection({
    required this.book,
    required this.plan,
    required this.progress,
  });

  final Book book;

  /// Carried alongside [progress] for one thing only: the day the plan began,
  /// which is a fact about the plan rather than about how it is going.
  final ReadingPlan plan;
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

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Kicker(l10n.bookPlanSection, color: colors.muted),
        const SizedBox(height: AppSpacing.x2 + 2),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Text(
                '${l10n.libraryDailyPortion(progress.pagesPerDay)} · '
                '${l10n.bookSessionCount(progress.sessionCount)}',
                style: theme.textTheme.titleMedium?.copyWith(fontSize: 16.5),
              ),
            ),
            const SizedBox(width: AppSpacing.x2),
            // Beside the plan rather than down with the actions: this edits
            // the sentence it sits next to, and nothing else on the screen.
            TextButton(
              onPressed: () => context.push('/books/${book.id}/plan'),
              style: TextButton.styleFrom(
                foregroundColor: theme.colorScheme.primary,
                minimumSize: const Size(0, 30),
                padding: const EdgeInsets.symmetric(horizontal: 4),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: Text(l10n.planEdit),
            ),
          ],
        ),
        const SizedBox(height: 2),
        // The two facts that never change about a book, kept here rather than
        // in the masthead: v2's masthead is the title and the author and
        // nothing else, and these are dates — which is what this section is.
        Text(
          '${l10n.bookPageCount(book.pageCount)} · '
          '${l10n.bookStartedOn(AppDates.dayAndMonth(plan.startDate, locale))}',
          style: aside,
        ),
        Text(
          l10n.progressProjectedEnd(
            AppDates.dayAndMonth(progress.projectedEndDate, locale),
          ),
          style: aside,
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
        // Two answers, in the order the screen believes in them: a goal is
        // what turns a file into something finishable, and is asked for first.
        // But a reader who just wants to open the book is not doing anything
        // wrong, and making the plan the toll gate would only teach them that
        // this app is where books go to become homework.
        action: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            OutlinedButton(
              onPressed: () => context.push('/books/$bookId/plan'),
              child: Text(l10n.planCreate),
            ),
            const SizedBox(height: AppSpacing.x1),
            TextButton(
              onPressed: () => context.push('/books/$bookId/read'),
              child: Text(l10n.readerOpenBook),
            ),
          ],
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

    // The way into the book, on whatever shelf it is sitting. A finished book
    // is opened to be looked at again, a reading one to be carried on with —
    // and neither of those has to be due, or planned, or asked permission for.
    Widget openBook(String label) => _ActionRow(
      children: [
        _Action(
          label: label,
          onPressed: () => context.push('/books/${book.id}/read'),
        ),
      ],
    );

    return switch (book.status) {
      BookStatus.finished => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          openBook(l10n.readerOpenBook),
          const SizedBox(height: AppSpacing.x2 - 1),
          _ActionRow(
            children: [
              _Action(
                primary: true,
                label: l10n.bookReturnToReading,
                onPressed: () => setStatus(BookStatus.reading),
              ),
            ],
          ),
        ],
      ),
      // Editing the plan is not here: v2 moved it up beside the plan sentence
      // it edits, which leaves this row as the two things you do to the *book*
      // rather than to its goal. Neither is primary — a screen whose reason for
      // existing is to be read should not end in something to press.
      BookStatus.reading when plan != null => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          openBook(l10n.readerKeepReading),
          const SizedBox(height: AppSpacing.x2 - 1),
          _ActionRow(
            children: [
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
