import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/format/app_dates.dart';
import '../../../core/format/app_durations.dart';
import '../../../core/planning/pace_providers.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/figure.dart';
import '../../../core/widgets/kicker.dart';
import '../../../core/widgets/page_sheet.dart';
import '../../../core/widgets/progress_shapes.dart';
import '../../../core/widgets/screen_header.dart';
import '../../../l10n/app_localizations.dart';
import '../application/today_providers.dart';
import '../domain/today_agenda.dart';

/// Screen 2 — one hero, the rest quiet.
///
/// Redesign v2 sets this screen as a **page** rather than a card: a ribbon
/// falling from the top edge, a running head, the portion typeset large over a
/// gutter shadow, and a folio at the foot. See `core/widgets/page_sheet.dart`
/// for why.
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
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ScreenHeader(
                  kicker: AppDates.weekdayAndDate(
                    ref.watch(todayProvider),
                    locale,
                  ),
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
            // Hangs from the top edge, crossing the header to land on the page
            // below it. Only when there is something to mark — a ribbon in a
            // finished book is just a loose thread.
            if (agenda?.current != null)
              PositionedDirectional(
                top: 0,
                end: PageRibbon.inset,
                child: const IgnorePointer(child: PageRibbon()),
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

    // The page sheet is the one thing that reaches past the text margin: it is
    // paper the margin text sits on, so it cannot share that margin. Everything
    // else is stepped back in by [_Margin] to the usual gutter.
    return ListView(
      padding: const EdgeInsets.fromLTRB(
        _sheetInset,
        AppSpacing.x4,
        _sheetInset,
        AppSpacing.x6,
      ),
      children: [
        if (agenda.current case final current?)
          _HeroSession(entry: current)
        else
          const _Margin(child: _DoneForToday()),
        if (later.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.x6 - 4),
          _Margin(
            child: Kicker(
              l10n.todayLater,
              color: Theme.of(context).appColors.muted,
            ),
          ),
          const SizedBox(height: AppSpacing.x1 - 1),
          for (final entry in later) _Margin(child: _LaterRow(entry: entry)),
        ],
        const SizedBox(height: AppSpacing.x6 - 8),
        _Margin(child: _AllOfToday(agenda: agenda)),
      ],
    );
  }
}

/// Where the page sheet's edge falls, 4px outside the text gutter.
const _sheetInset = AppSpacing.gutter - 4;

/// Steps a child back in from [_sheetInset] to the screen's text gutter.
class _Margin extends StatelessWidget {
  const _Margin({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(
      horizontal: AppSpacing.gutter - _sheetInset,
    ),
    child: child,
  );
}

/// The one thing the screen is asking for, set as a page.
///
/// Running head at the top, the portion typeset large, the comb, the committing
/// action, and a folio line at the foot — the furniture of a printed page, in
/// the order a page uses it.
class _HeroSession extends ConsumerWidget {
  const _HeroSession({required this.entry});

  final TodayEntry entry;

  /// Opens the reader on this session's own stretch and nothing else.
  void _read(BuildContext context, int page) => context.push(
    '/books/${entry.bookId}/read'
    '?from=${entry.fromPage}&to=${entry.toPage}&page=$page',
  );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    // Null until the reader has been timed enough to be worth predicting from.
    // The line simply is not there until then — an estimate the app is not
    // sure of is worse than no estimate, because the reader would plan by it.
    final estimate = ref
        .watch(currentPaceProvider)
        .estimateFor(entry.pagesLeft);
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: theme.appColors.muted,
    );

    return PageSheet(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          RunningHead(
            title: entry.author == null
                ? entry.title
                : l10n.todayRunningHead(entry.title, entry.author!),
            scope: l10n.todayThisSession,
          ),
          const SizedBox(height: 16),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              // The number is the screen's loudest element by a wide margin:
              // this is the one figure the reader is meant to act on.
              Figure.number(entry.pagesLeft, size: 76, height: .76),
              const SizedBox(width: 13),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        l10n.todayPagesLeftLabel(entry.pagesLeft),
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontSize: 13.5,
                        ),
                      ),
                      Text.rich(
                        TextSpan(
                          children: figureInSentence(
                            l10n.todayPageRange(figureMarker),
                            figureSpan(
                              AppNumbers.range(entry.nextPage, entry.toPage),
                              size: 12.5,
                              color: theme.appColors.muted,
                            ),
                          ),
                        ),
                        style: muted,
                      ),
                      if (estimate != null)
                        Text(
                          l10n.todayEstimate(
                            AppDurations.estimate(estimate, l10n),
                          ),
                          style: muted,
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          SessionComb(
            pages: entry.pages,
            pagesDone: entry.pagesDone,
            onTapPage: (index) => _read(context, entry.fromPage + index),
          ),
          const SizedBox(height: 5),
          Row(
            children: [
              Expanded(
                child: Text(
                  l10n.todaySessionProgress(
                    AppNumbers.format(entry.pagesDone),
                    AppNumbers.format(entry.pages),
                  ),
                  style: muted?.copyWith(fontSize: 11),
                ),
              ),
              Text(l10n.todayTapComb, style: muted?.copyWith(fontSize: 11)),
            ],
          ),
          const SizedBox(height: 18),
          FilledButton(
            // Opens on the first page not yet read — resuming mid-portion is
            // the norm, so the button says where it will land.
            onPressed: () => _read(context, entry.nextPage),
            child: Text(
              entry.pagesDone > 0
                  ? l10n.todayResumeAt(AppNumbers.format(entry.nextPage))
                  : l10n.todayStartPortion,
            ),
          ),
          const SizedBox(height: 13),
          Row(
            children: [
              Expanded(
                child: Text(
                  clockOf(entry),
                  style: theme.textTheme.labelSmall?.copyWith(
                    fontSize: 10,
                    letterSpacing: 1.1,
                    color: theme.appColors.muted,
                  ),
                ),
              ),
              Figure(
                l10n.todayFolio(
                  AppNumbers.format(entry.nextPage),
                  AppNumbers.format(entry.bookEndPage),
                ),
                size: 12,
                color: theme.appColors.muted,
              ),
            ],
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
class _AllOfToday extends ConsumerWidget {
  const _AllOfToday({required this.agenda});

  final TodayAgenda agenda;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);

    // Only worth saying when the day is actually split; "1 session across
    // 1 book" is the bar restated in words.
    final across = agenda.entries.length > 1
        ? l10n.todayAcross(
            l10n.todaySessionCount(agenda.entries.length),
            l10n.libraryBookCount(agenda.bookCount),
          )
        : null;

    // What is *left*, not what the day holds: a reader halfway through wants
    // to know how much longer, and the bar above already says how far along
    // they are.
    final remaining = agenda.pagesLeft > 0
        ? ref.watch(currentPaceProvider).estimateFor(agenda.pagesLeft)
        : null;
    final footnote = [
      ?across,
      if (remaining != null)
        l10n.todayEstimate(AppDurations.estimate(remaining, l10n)),
    ].join(' · ');

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
          if (footnote.isNotEmpty) ...[
            const SizedBox(height: 7),
            Text(
              footnote,
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
