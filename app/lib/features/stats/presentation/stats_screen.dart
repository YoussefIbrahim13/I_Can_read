import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/format/app_dates.dart';
import '../../../core/format/app_durations.dart';
import '../../../core/planning/reading_pace.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/figure.dart';
import '../../../core/widgets/kicker.dart';
import '../../../core/widgets/reading_calendar_grid.dart';
import '../../../core/widgets/screen_header.dart';
import '../../../l10n/app_localizations.dart';
import '../application/stats_providers.dart';
import '../domain/reading_stats.dart';

/// Screen 10 — what the reader has actually done.
///
/// Three figures, a shape, and a list. Nothing on this screen is a score: no
/// days missed, no percentage of a target, nothing to fall short of. The app
/// answers lateness by moving a date, and this screen does not go behind its
/// back and grade the reader for it.
class StatsScreen extends ConsumerWidget {
  const StatsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final stats = ref.watch(readingStatsProvider).value;

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ScreenHeader(
              kicker: l10n.statsWindowLast30Days,
              title: l10n.navStats,
            ),
            Expanded(
              child: switch (stats) {
                null => const SizedBox.shrink(),
                final stats when stats.isEmpty => EmptyState(
                  title: l10n.statsEmpty,
                  message: l10n.statsEmptyHint,
                ),
                final stats => _Stats(stats: stats),
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _Stats extends StatelessWidget {
  const _Stats({required this.stats});

  final ReadingStats stats;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final muted = Theme.of(context).appColors.muted;

    return ListView(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.gutter,
        AppSpacing.x4,
        AppSpacing.gutter,
        AppSpacing.x8,
      ),
      children: [
        // The streak leads, alone and large. Redesign v2 pulled it out of the
        // three-across row because it is the only figure here that is about
        // *keeping going*, which is what the whole app is for — the other
        // three are measurements.
        _Streak(stats: stats),
        const SizedBox(height: AppSpacing.x4),
        _Figures(stats: stats),
        const SizedBox(height: AppSpacing.x6 - 2),
        const _ReadingCalendar(),
        const SizedBox(height: AppSpacing.x6 - 2),
        // After the calendar now: the calendar answers "have I been reading",
        // which is the question this screen is opened with, and the chart is
        // the same answer in more detail for the reader who wants it.
        Kicker(l10n.statsPagesPerDay, color: muted),
        const SizedBox(height: AppSpacing.x3),
        _PagesChart(stats: stats),
        if (stats.finished.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.x6 - 2),
          Kicker(l10n.statsFinishedSection, color: muted),
          const SizedBox(height: AppSpacing.x2),
          for (final book in stats.finished) _FinishedRow(book: book),
        ],
      ],
    );
  }
}

/// Days in a row, at display size, with what it adds up to underneath.
class _Streak extends StatelessWidget {
  const _Streak({required this.stats});

  final ReadingStats stats;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Figure.number(stats.streakDays, size: 56, height: 0.82),
        const SizedBox(width: AppSpacing.x3),
        Expanded(
          child: Padding(
            // Sits the gloss on the figure's baseline rather than under its
            // descender.
            padding: const EdgeInsets.only(bottom: 6),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.statsStreak,
                  style: theme.textTheme.bodyMedium?.copyWith(fontSize: 14),
                ),
                // Time is something the reader spent rather than something
                // they counted, so it glosses the streak instead of standing
                // as a figure of its own.
                if (stats.hasTimeRead)
                  Text(
                    l10n.statsTimeRead(
                      AppDurations.compact(stats.timeRead, l10n),
                    ),
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontSize: 12,
                      color: theme.appColors.muted,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// Every book's reading days on one grid.
///
/// The same calendar the detail screen draws for a single book, measured
/// against the sum of the portions the reader is committed to — so a full
/// square here means a day they did everything they had set out to do, not just
/// everything for one book.
class _ReadingCalendar extends ConsumerWidget {
  const _ReadingCalendar();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Kicker(l10n.statsCalendar, color: theme.appColors.muted),
        const SizedBox(height: AppSpacing.x3),
        // Full-bleed to the text margin, dividing the width between the
        // columns. v2 wants the grid to be the block it is; the old version
        // scrolled sideways at a fixed square, which hid a third of the
        // history behind a gesture nobody knew was there.
        ReadingCalendarGrid(columns: ref.watch(libraryCalendarProvider)),
        const SizedBox(height: AppSpacing.x2),
        Text(
          l10n.statsCalendarHint,
          style: theme.textTheme.bodySmall?.copyWith(
            fontSize: 11.5,
            height: 1.6,
            color: theme.appColors.muted,
          ),
        ),
      ],
    );
  }
}

/// The measurements, ruled into cells.
///
/// A boxed row rather than three loose columns: these are readings off the same
/// instrument, and the rules between them say so. The pace cell is absent until
/// enough pages have been timed to mean anything — see [ReadingPace] — because
/// a per-page figure from two timed pages is a number, not a measurement.
class _Figures extends StatelessWidget {
  const _Figures({required this.stats});

  final ReadingStats stats;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = Theme.of(context).appColors;
    final perPage = stats.pace.perPage;

    final cells = <Widget>[
      _Stat(
        value: AppNumbers.format(stats.averagePagesPerDay),
        label: l10n.statsAveragePages,
      ),
      _Stat(
        value: AppNumbers.format(stats.finishedCount),
        label: l10n.statsFinishedCount,
      ),
      if (perPage != null)
        _Stat(
          value: AppDurations.tight(perPage, l10n),
          label: l10n.statsPerPage,
        ),
    ];

    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border.all(color: colors.hairline),
        borderRadius: BorderRadius.circular(AppSpacing.radius),
      ),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final (index, cell) in cells.indexed) ...[
              if (index > 0)
                VerticalDivider(width: 1, thickness: 1, color: colors.hairline),
              Expanded(child: cell),
            ],
          ],
        ),
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.value, required this.label});

  /// Already formatted — these are not all integers. The pace cell carries a
  /// duration, and it is the same kind of reading as the two beside it.
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.symmetric(
        vertical: AppSpacing.x3,
        horizontal: AppSpacing.x2,
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Figure(value, size: 27, height: 1),
          const SizedBox(height: 5),
          Text(
            label,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(
              fontSize: 11.5,
              height: 1.35,
              color: theme.appColors.muted,
            ),
          ),
        ],
      ),
    );
  }
}

/// Pages a day across the window, drawn as bars on a baseline.
class _PagesChart extends StatelessWidget {
  const _PagesChart({required this.stats});

  final ReadingStats stats;

  static const _height = 120.0;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final colors = theme.appColors;
    final locale = Localizations.localeOf(context);

    final busiest = stats.busiestDay;
    final caption = theme.textTheme.bodySmall?.copyWith(
      fontSize: 10,
      color: colors.muted,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Always left-to-right, in both locales: the axis is time, and today
        // belongs at the end the reader's eye lands on last.
        Directionality(
          textDirection: TextDirection.ltr,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                height: _height,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    for (final (index, day) in stats.days.indexed) ...[
                      if (index > 0) const SizedBox(width: 3),
                      Expanded(
                        child: Container(
                          // A day with no reading still gets a mark, at the
                          // hairline: an absent bar and a one-page bar would
                          // otherwise look the same from across the room.
                          height: day.isEmpty
                              ? 1
                              : (_height * day.pages / busiest).clamp(
                                  2.0,
                                  _height,
                                ),
                          color: day.isEmpty
                              ? colors.hairline
                              : colors.accentStroke,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              Divider(height: 1, thickness: 1, color: colors.hairline),
              const SizedBox(height: AppSpacing.x2),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    AppDates.dayAndMonth(stats.days.first.date, locale),
                    style: caption,
                  ),
                  Text(l10n.statsToday, style: caption),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// One finished book: what it was, and how long it took.
///
/// Marked at the leading edge by a short sage rule — the only place in the app
/// besides a finished portion where green appears, and for exactly the same
/// reason. It means *done*, never "well read" and never "on target".
class _FinishedRow extends StatelessWidget {
  const _FinishedRow({required this.book});

  final FinishedBook book;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.x3 - 1),
          child: Row(
            children: [
              Container(width: 2, height: 26, color: theme.appColors.done),
              const SizedBox(width: AppSpacing.x3 - 2),
              Expanded(
                child: Text(
                  book.title,
                  style: theme.textTheme.titleSmall?.copyWith(fontSize: 15),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: AppSpacing.x2 + 1),
              Text(
                l10n.statsTookDays(book.days),
                style: theme.textTheme.bodySmall?.copyWith(
                  fontSize: 11.5,
                  color: theme.appColors.muted,
                ),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
      ],
    );
  }
}
