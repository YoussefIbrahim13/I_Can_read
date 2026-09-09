import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/format/app_dates.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/figure.dart';
import '../../../core/widgets/kicker.dart';
import '../../../core/widgets/progress_shapes.dart';
import '../../../core/widgets/screen_header.dart';
import '../../../l10n/app_localizations.dart';
import '../application/today_providers.dart';
import '../domain/today_agenda.dart';

/// Screen 2 — one hero, the rest quiet.
///
/// Lateness is never mentioned here. A portion missed yesterday simply appears
/// as today's work; the only place the app states a slipped date is the book's
/// own projected finish.
class TodayScreen extends ConsumerWidget {
  const TodayScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final locale = Localizations.localeOf(context);
    final agenda = ref.watch(todayAgendaProvider).value;

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ScreenHeader(
              kicker: AppDates.weekdayAndDate(ref.watch(todayProvider), locale),
              title: l10n.navToday,
            ),
            Expanded(
              child: switch (agenda) {
                null => const SizedBox.shrink(),
                final agenda when agenda.isEmpty => EmptyState(
                  title: l10n.todayEmpty,
                  message: l10n.todayEmptyHint,
                  action: OutlinedButton(
                    onPressed: () => context.push('/books/add'),
                    child: Text(l10n.addBook),
                  ),
                ),
                final agenda => _Agenda(agenda: agenda),
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _Agenda extends StatelessWidget {
  const _Agenda({required this.agenda});

  final TodayAgenda agenda;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final later = agenda.later;

    return ListView(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.gutter,
        AppSpacing.x4,
        AppSpacing.gutter,
        AppSpacing.x6,
      ),
      children: [
        if (agenda.current case final current?)
          _HeroSession(entry: current)
        else
          const _DoneForToday(),
        if (later.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.x6 - 4),
          Kicker(l10n.todayLater, color: Theme.of(context).appColors.muted),
          const SizedBox(height: AppSpacing.x1 - 1),
          for (final entry in later) _LaterRow(entry: entry),
        ],
        const SizedBox(height: AppSpacing.x6 - 8),
        _AllOfToday(agenda: agenda),
      ],
    );
  }
}

/// The one thing the screen is asking for, inside a gold-edged card.
class _HeroSession extends StatelessWidget {
  const _HeroSession({required this.entry});

  final TodayEntry entry;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);

    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        // Half-strength gold: the card is the subject, but a full stroke around
        // something this large stops reading as an accent and starts reading as
        // a warning.
        border: Border.all(
          color: theme.appColors.accentStroke.withValues(alpha: .5),
        ),
        borderRadius: BorderRadius.circular(AppSpacing.radius),
      ),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 15),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Expanded(child: Kicker(l10n.todayThisSession)),
              Figure(
                clockOf(entry),
                size: 15,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.x2 + 1),
          Text(
            entry.title,
            style: theme.textTheme.titleMedium,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          if (entry.author case final author?)
            Text(
              author,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.appColors.muted,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          const SizedBox(height: AppSpacing.x3),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              // The number is the screen's loudest element by a wide margin:
              // this is the one figure the reader is meant to act on.
              Figure.number(entry.pagesLeft, size: 54, height: .85),
              const SizedBox(width: AppSpacing.x3 - 2),
              Padding(
                padding: const EdgeInsets.only(bottom: 5),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l10n.todayPagesLeftLabel(entry.pagesLeft),
                      style: theme.textTheme.bodyMedium,
                    ),
                    Text.rich(
                      TextSpan(
                        children: figureInSentence(
                          l10n.todayPageRange(figureMarker),
                          figureSpan(
                            AppNumbers.range(entry.fromPage, entry.toPage),
                            size: 12.5,
                            color: theme.appColors.muted,
                          ),
                        ),
                      ),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.appColors.muted,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.x4),
          Row(
            children: [
              Expanded(
                child: SessionRule(fraction: entry.pagesDone / entry.pages),
              ),
              const SizedBox(width: AppSpacing.x2),
              Text(
                l10n.todaySessionProgress(
                  AppNumbers.format(entry.pagesDone),
                  AppNumbers.format(entry.pages),
                ),
                style: theme.textTheme.bodySmall?.copyWith(
                  fontSize: 11,
                  color: theme.appColors.muted,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.x4 - 3),
          OutlinedButton(
            // The reader is handed this session's own stretch and shows
            // nothing else, opening on the first page not yet read —
            // resuming mid-portion is the norm.
            onPressed: () => context.push(
              '/books/${entry.bookId}/read'
              '?from=${entry.fromPage}&to=${entry.toPage}'
              '&page=${entry.nextPage}',
            ),
            child: Text(l10n.todayReadNow),
          ),
        ],
      ),
    );
  }
}

/// Shown in place of the hero once every session is finished.
class _DoneForToday extends StatelessWidget {
  const _DoneForToday();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);

    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: theme.appColors.hairline),
        borderRadius: BorderRadius.circular(AppSpacing.radius),
      ),
      padding: const EdgeInsets.fromLTRB(16, 15, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Kicker(l10n.todayDone, color: theme.appColors.done),
          const SizedBox(height: AppSpacing.x2 + 1),
          Text(l10n.todayAllDone, style: theme.textTheme.titleMedium),
          const SizedBox(height: AppSpacing.x1),
          Text(
            l10n.todayAllDoneHint,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

/// A later session: time, book, its stretch — and a tick when it is already
/// done, because a row that disappeared would make the day look shorter.
class _LaterRow extends StatelessWidget {
  const _LaterRow({required this.entry});

  final TodayEntry entry;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final isDone = entry.state == SessionState.done;

    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: theme.appColors.hairline)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 13),
        child: Row(
          children: [
            SizedBox(
              width: 38,
              child: Figure(
                clockOf(entry),
                size: 15,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(width: AppSpacing.x3),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Opacity(
                    // Finished work recedes rather than vanishing.
                    opacity: isDone ? .5 : 1,
                    child: Text(
                      entry.title,
                      style: theme.textTheme.titleSmall,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text.rich(
                    TextSpan(
                      children: figureInSentence(
                        l10n.todayRowDetail(
                          figureMarker,
                          l10n.sessionPages(entry.pages),
                        ),
                        figureSpan(
                          AppNumbers.range(entry.fromPage, entry.toPage),
                          size: 11.5,
                          color: theme.appColors.muted,
                        ),
                      ),
                    ),
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontSize: 11.5,
                      color: theme.appColors.muted,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            if (isDone) ...[
              const SizedBox(width: AppSpacing.x2),
              Icon(Icons.check, size: 14, color: theme.appColors.done),
            ],
          ],
        ),
      ),
    );
  }
}

/// The whole day in one card: the split, drawn, and what it adds up to.
class _AllOfToday extends StatelessWidget {
  const _AllOfToday({required this.agenda});

  final TodayAgenda agenda;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);

    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: theme.appColors.hairline),
        borderRadius: BorderRadius.circular(AppSpacing.radius),
      ),
      padding: const EdgeInsets.fromLTRB(14, 13, 14, 13),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Expanded(
                child: Kicker(l10n.todayAll, color: theme.appColors.muted),
              ),
              Text(
                l10n.todayPagesDone(
                  AppNumbers.format(agenda.pagesDone),
                  AppNumbers.format(agenda.totalPages),
                ),
                style: theme.textTheme.bodySmall?.copyWith(
                  fontSize: 12,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.x2 + 1),
          TodayBar(
            segments: [
              for (final entry in agenda.entries)
                TodaySegment(
                  pages: entry.pages,
                  done: entry.state == SessionState.done,
                ),
            ],
          ),
          // Only worth saying when the day is actually split; "1 session across
          // 1 book" is the bar restated in words.
          if (agenda.entries.length > 1) ...[
            const SizedBox(height: 7),
            Text(
              l10n.todayAcross(
                l10n.todaySessionCount(agenda.entries.length),
                l10n.libraryBookCount(agenda.bookCount),
              ),
              style: theme.textTheme.bodySmall?.copyWith(
                fontSize: 10.5,
                color: theme.appColors.muted,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// `21:00`, always in western digits and always two-and-two.
String clockOf(TodayEntry entry) =>
    '${entry.hour.toString().padLeft(2, '0')}:'
    '${entry.minute.toString().padLeft(2, '0')}';
