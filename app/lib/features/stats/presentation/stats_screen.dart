import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/format/app_dates.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/figure.dart';
import '../../../core/widgets/kicker.dart';
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

    return ListView(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.gutter,
        AppSpacing.x4 + 4,
        AppSpacing.gutter,
        AppSpacing.x8,
      ),
      children: [
        _Figures(stats: stats),
        const SizedBox(height: AppSpacing.x6 - 2),
        Kicker(l10n.statsPagesPerDay, color: Theme.of(context).appColors.muted),
        const SizedBox(height: AppSpacing.x3),
        _PagesChart(stats: stats),
        if (stats.finished.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.x6 - 2),
          Kicker(
            l10n.statsFinishedSection,
            color: Theme.of(context).appColors.muted,
          ),
          const SizedBox(height: AppSpacing.x1),
          for (final book in stats.finished) _FinishedRow(book: book),
        ],
      ],
    );
  }
}

/// The three standing figures, divided by hairlines.
class _Figures extends StatelessWidget {
  const _Figures({required this.stats});

  final ReadingStats stats;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = Theme.of(context).appColors;

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: _Stat(value: stats.streakDays, label: l10n.statsStreak),
          ),
          VerticalDivider(width: 1, thickness: 1, color: colors.hairline),
          Expanded(
            child: _Stat(
              value: stats.averagePagesPerDay,
              label: l10n.statsAveragePages,
              inset: true,
            ),
          ),
          VerticalDivider(width: 1, thickness: 1, color: colors.hairline),
          Expanded(
            child: _Stat(
              value: stats.finishedCount,
              label: l10n.statsFinishedCount,
              inset: true,
            ),
          ),
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.value, required this.label, this.inset = false});

  final int value;
  final String label;

  /// Pads the columns that sit after a rule, so the figure does not touch it.
  final bool inset;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: EdgeInsetsDirectional.only(start: inset ? AppSpacing.x4 : 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Figure.number(value, size: 46, height: 0.9),
          const SizedBox(height: 6),
          Text(
            label,
            style: theme.textTheme.bodySmall?.copyWith(
              fontSize: 12,
              height: 1.4,
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
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.x3 - 2),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Expanded(
                child: Text(
                  book.title,
                  style: theme.textTheme.bodyMedium?.copyWith(fontSize: 14.5),
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
