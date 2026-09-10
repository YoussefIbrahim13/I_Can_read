import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/format/app_dates.dart';
import '../../../core/format/app_durations.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/figure.dart';
import '../../../core/widgets/screen_header.dart';
import '../../../l10n/app_localizations.dart';
import '../../plan/application/plan_providers.dart';
import '../application/book_detail_providers.dart';
import '../domain/read_portions.dart';

/// Screen 11 — every portion of one book, day by day.
///
/// The calendar on the book screen answers "how consistent have I been"; this
/// answers "what did I actually do, and what did it cost". Days with no
/// reading are absent rather than listed empty — the app moves a date when a
/// day is missed and does not also keep a ledger of them.
class ReadingRecordScreen extends ConsumerWidget {
  const ReadingRecordScreen({required this.bookId, super.key});

  final String bookId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final plan = ref.watch(activePlanProvider(bookId)).value;
    final record = plan == null
        ? null
        : ref.watch(readingRecordProvider(plan.id)).value;

    return Scaffold(
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ScreenBackBar(title: l10n.recordTitle),
            const Divider(),
            Expanded(
              child: switch (record) {
                // Null covers both "no plan" and "the query has not landed".
                // Neither is worth a spinner: the list arrives in a frame.
                null => const SizedBox.shrink(),
                final record when record.isEmpty => EmptyState(
                  title: l10n.recordEmpty,
                  message: l10n.recordEmptyHint,
                ),
                final record => _Record(record: record),
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _Record extends StatelessWidget {
  const _Record({required this.record});

  final ReadingRecord record;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.gutter,
        AppSpacing.x4,
        AppSpacing.gutter,
        AppSpacing.x8,
      ),
      children: [
        _Totals(record: record),
        const SizedBox(height: AppSpacing.x4),
        for (final portion in record.portions) _PortionRow(portion: portion),
      ],
    );
  }
}

/// What the record adds up to, before the days themselves.
///
/// Days and pages always; time only once something has been measured, so a
/// book read entirely before the clock existed is not told it took no time.
class _Totals extends StatelessWidget {
  const _Totals({required this.record});

  final ReadingRecord record;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.recordSummary(
            l10n.recordDays(record.daysRead),
            l10n.sessionPages(record.totalPages),
          ),
          style: theme.textTheme.bodyMedium?.copyWith(fontSize: 14.5),
        ),
        if (record.hasAnyTime)
          Text(
            l10n.recordTotalTime(AppDurations.compact(record.totalTime, l10n)),
            style: theme.textTheme.bodySmall?.copyWith(
              fontSize: 12,
              height: 1.7,
              color: theme.appColors.muted,
            ),
          ),
      ],
    );
  }
}

/// One day: when, what it cost, and which pages it covered.
class _PortionRow extends StatelessWidget {
  const _PortionRow({required this.portion});

  final ReadPortion portion;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final locale = Localizations.localeOf(context);
    final muted = theme.textTheme.bodySmall?.copyWith(
      fontSize: 11.5,
      color: theme.appColors.muted,
    );

    // A day nobody timed says so, rather than showing a zero it did not earn.
    // The sitting count only appears when it is more than one, which is the
    // only time it tells the reader something they could not assume.
    final detail = [
      l10n.sessionPages(portion.pages),
      portion.isTimed
          ? AppDurations.compact(portion.time, l10n)
          : l10n.recordUntimed,
      if (portion.sittings > 1) l10n.recordSittings(portion.sittings),
    ].join(' · ');

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.x3 - 4),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      AppDates.dayAndMonth(portion.day, locale),
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontSize: 14.5,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(detail, style: muted),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.x2 + 1),
              // Isolated through Figure: «ص 42–48» reorders under RTL and the
              // range comes out backwards without it.
              Text.rich(
                TextSpan(
                  children: figureInSentence(
                    l10n.todayPageRange(figureMarker),
                    figureSpan(
                      AppNumbers.range(portion.fromPage, portion.toPage),
                      size: 11.5,
                      color: theme.appColors.muted,
                    ),
                  ),
                ),
                style: muted,
              ),
            ],
          ),
        ),
        const Divider(height: 1),
      ],
    );
  }
}
