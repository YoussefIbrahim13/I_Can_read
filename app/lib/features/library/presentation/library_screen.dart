import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/db/app_database.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/widgets/cover_plate.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/figure.dart';
import '../../../core/widgets/screen_header.dart';
import '../../../l10n/app_localizations.dart';
import '../../plan/application/plan_providers.dart';
import '../../today/application/today_providers.dart';
import '../../today/domain/today_agenda.dart';
import '../application/library_providers.dart';

/// Screen 3 — the shelf.
///
/// Redesign v2 changed two things here. The hatched cover became a [SpinePlate]
/// — the book's own text block, inked as far as the reader has got — so a row
/// says how long the book is and how far in you are before you read a word of
/// it. And a row now **opens in place** rather than navigating: the day's
/// portion and the way into it are one tap from the shelf, because leaving the
/// shelf to find out what you owe and then coming back was the long way round.
class LibraryScreen extends ConsumerWidget {
  const LibraryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    // The kicker counts the shelf the screen opens on, which is the one the
    // reader thinks of as "my library".
    final reading = ref
        .watch(booksOnShelfProvider(LibraryShelf.reading))
        .asData
        ?.value;

    return DefaultTabController(
      length: 3,
      child: Scaffold(
        body: SafeArea(
          bottom: false,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ScreenHeader(
                kicker: reading == null
                    ? null
                    : l10n.libraryBookCount(reading.length),
                title: l10n.navLibrary,
                // The design has no floating action button, and v2 stepped the
                // outlined button down to a plain gold link: adding a book is
                // a deliberate act, but it is not what this screen is *for*,
                // and the shelf below has its own way in at the foot.
                trailing: TextButton(
                  onPressed: () => context.push('/books/add'),
                  style: TextButton.styleFrom(
                    foregroundColor: theme.colorScheme.primary,
                    minimumSize: const Size(0, 34),
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: Text(l10n.addBook),
                ),
                divider: false,
              ),
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.gutter,
                ),
                child: TabBar(
                  // Left-packed and only as wide as their labels, so the three
                  // shelves read as a line of links under the title rather
                  // than as three equal buttons.
                  isScrollable: true,
                  tabAlignment: TabAlignment.start,
                  padding: EdgeInsets.zero,
                  // The bar sits inside the gutter, so its own divider would
                  // stop short at both ends; the rule below is full-bleed.
                  dividerHeight: 0,
                  labelPadding: const EdgeInsetsDirectional.only(
                    end: AppSpacing.gutter,
                  ),
                  tabs: [
                    Tab(height: 34, text: l10n.libraryTabReading),
                    Tab(height: 34, text: l10n.libraryTabFinished),
                    Tab(height: 34, text: l10n.libraryTabPaused),
                  ],
                ),
              ),
              const Divider(),
              const Expanded(
                child: TabBarView(
                  children: [
                    _Shelf(shelf: LibraryShelf.reading),
                    _Shelf(shelf: LibraryShelf.finished),
                    _Shelf(shelf: LibraryShelf.paused),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Shelf extends ConsumerWidget {
  const _Shelf({required this.shelf});

  final LibraryShelf shelf;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final books = ref.watch(booksOnShelfProvider(shelf));
    final missingIds =
        ref.watch(missingFileBookIdsProvider).asData?.value ?? const <String>{};
    final plans =
        ref.watch(activePlansProvider).asData?.value ??
        const <String, ReadingPlan>{};
    final due = _dueByBook(ref.watch(todayAgendaProvider).asData?.value);

    return books.when(
      loading: () => const SizedBox.shrink(),
      error: (error, _) => Center(child: Text('$error')),
      data: (items) {
        if (items.isEmpty) {
          // Each shelf empties for its own reason, and only one of them is
          // solved by adding a book: telling a reader with no finished books
          // to import a PDF answers a question they did not ask.
          return switch (shelf) {
            LibraryShelf.reading => EmptyState(
              title: l10n.libraryEmpty,
              message: l10n.libraryEmptyHint,
              action: OutlinedButton(
                onPressed: () => context.push('/books/add'),
                child: Text(l10n.addBook),
              ),
            ),
            LibraryShelf.finished => EmptyState(
              title: l10n.libraryEmptyFinished,
              message: l10n.libraryEmptyFinishedHint,
            ),
            LibraryShelf.paused => EmptyState(
              title: l10n.libraryEmptyPaused,
              message: l10n.libraryEmptyPausedHint,
            ),
          };
        }
        return ListView.separated(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.gutter,
            0,
            AppSpacing.gutter,
            AppSpacing.x6,
          ),
          // One past the books: the last row is the way to add another. It
          // sits *in* the shelf rather than floating over it, so it never
          // covers the book underneath.
          itemCount: items.length + (shelf == LibraryShelf.reading ? 1 : 0),
          // A hairline between rows, not a gap between cards: the shelf is one
          // list, and boxing each book would make four books look like four
          // separate screens' worth of content.
          separatorBuilder: (_, _) => const Divider(),
          itemBuilder: (context, index) {
            if (index == items.length) return const _AddBookRow();
            final book = items[index];
            return _BookRow(
              // Keyed by the book, not by its place on the shelf: which row is
              // open is state, and the shelf reorders under it — finishing a
              // book or pausing one moves every row after it, and without this
              // the open row would stay behind and belong to its neighbour.
              key: ValueKey(book.id),
              book: book,
              fileMissing: missingIds.contains(book.id),
              plan: plans[book.id],
              due: due[book.id],
            );
          },
        );
      },
    );
  }

  /// The session each book still owes today, keyed by book.
  ///
  /// The *first* unfinished one, matching what Today would lead a reader into
  /// if they went there instead — the shelf must not offer a different next
  /// page from the one the day's own screen offers.
  static Map<String, TodayEntry> _dueByBook(TodayAgenda? agenda) {
    if (agenda == null) return const {};
    return {
      for (final entry in agenda.entries.reversed)
        if (entry.state != SessionState.done) entry.bookId: entry,
    };
  }
}

/// The last row of the reading shelf.
class _AddBookRow extends StatelessWidget {
  const _AddBookRow();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);

    return InkWell(
      onTap: () => context.push('/books/add'),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.x6 - 4),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.add, size: 17, color: theme.colorScheme.primary),
            const SizedBox(width: AppSpacing.x2),
            Text(
              l10n.addBook,
              style: theme.textTheme.labelLarge?.copyWith(
                fontSize: 14.5,
                color: theme.colorScheme.primary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// One book on the shelf, and — once tapped — what it wants today.
class _BookRow extends StatefulWidget {
  const _BookRow({
    required this.book,
    required this.fileMissing,
    required this.plan,
    required this.due,
    super.key,
  });

  final Book book;
  final bool fileMissing;

  /// The book's goal, or null while it has none.
  final ReadingPlan? plan;

  /// This book's unfinished session for today, if it has one.
  final TodayEntry? due;

  @override
  State<_BookRow> createState() => _BookRowState();
}

class _BookRowState extends State<_BookRow> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final progress = _progressOf(widget.plan);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // The brass band over the active book's plate, matching the ribbon
        // that hangs over the Today page. Reserved whether or not it is drawn,
        // so opening a row does not shunt the shelf by two pixels.
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: SizedBox(
            width: _plateWidth,
            // Height stated here rather than on a wrapper: `Align` hands its
            // child loose constraints, and a `ColoredBox` with no child takes
            // `constraints.smallest` under them — so a band sized only by its
            // parent would lay out zero high and never draw.
            height: 2,
            child: widget.due != null
                ? ColoredBox(color: theme.appColors.accentStroke)
                : const SizedBox.shrink(),
          ),
        ),
        InkWell(
          // The whole row is the target: the reader thinks of "the book" as
          // one thing, so tapping any part of it should answer.
          onTap: () => setState(() => _open = !_open),
          child: Padding(
            padding: const EdgeInsets.only(
              top: AppSpacing.x3,
              bottom: AppSpacing.x4 - 2,
            ),
            child: _Summary(
              book: widget.book,
              plan: widget.plan,
              progress: progress,
              ribbon: widget.due != null,
            ),
          ),
        ),
        // Grows the row in place. The shelf scrolls under it rather than being
        // replaced, which is the whole point of opening here instead of
        // pushing a screen.
        AnimatedSize(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOutCubic,
          alignment: AlignmentDirectional.topStart,
          child: _open
              ? _OpenRow(
                  book: widget.book,
                  plan: widget.plan,
                  due: widget.due,
                  fileMissing: widget.fileMissing,
                )
              : const SizedBox(width: double.infinity),
        ),
      ],
    );
  }
}

/// How far through its plan a book is, or null when it has no plan.
double? _progressOf(ReadingPlan? plan) {
  if (plan == null) return null;
  final total = plan.endPage - plan.startPage + 1;
  if (total <= 0) return 0;
  final read =
      plan.lastPageRead.clamp(plan.startPage - 1, plan.endPage) -
      plan.startPage +
      1;
  return read / total;
}

/// The plate's drawn width, which the brass band above it has to match.
const _plateWidth = 46.0;

/// The always-visible half of a row: plate, title, what it adds up to, and the
/// percentage standing on its own at the far end.
class _Summary extends StatelessWidget {
  const _Summary({
    required this.book,
    required this.plan,
    required this.progress,
    required this.ribbon,
  });

  final Book book;
  final ReadingPlan? plan;
  final double? progress;
  final bool ribbon;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final colors = theme.appColors;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (progress case final progress?)
          SpinePlate(fraction: progress, ribbon: ribbon, width: _plateWidth)
        else
          const CoverPlate(width: _plateWidth),
        const SizedBox(width: AppSpacing.x3),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                book.title,
                style: theme.textTheme.titleMedium?.copyWith(fontSize: 17),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              if (book.author case final author?) ...[
                const SizedBox(height: 1),
                Text(
                  author,
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontSize: 12.5,
                    color: colors.muted,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
              const SizedBox(height: AppSpacing.x2),
              Text(
                switch (plan) {
                  final plan? =>
                    '${l10n.libraryReadOfTotal(plan.lastPageRead.clamp(0, plan.endPage), plan.endPage)}'
                        ' · ${l10n.libraryDailyPortion(plan.pagesPerDay)}',
                  // A page count is a fact about the book, so it sets in the
                  // caption ink rather than in the accent.
                  null => l10n.bookPageCount(book.pageCount),
                },
                style: theme.textTheme.bodySmall?.copyWith(
                  fontSize: 12,
                  color: colors.muted,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
        if (progress case final progress?) ...[
          const SizedBox(width: AppSpacing.x3),
          _Percent(fraction: progress),
        ],
      ],
    );
  }
}

/// The percentage, standing alone: the figure large in Cormorant with its sign
/// tucked underneath rather than beside it.
///
/// Set apart from the caption line on purpose — it is the one number on the row
/// the reader scans for, and inside the sentence it was just another word.
class _Percent extends StatelessWidget {
  const _Percent({required this.fraction});

  final double fraction;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Figure.number(
          (fraction * 100).round(),
          size: 30,
          height: 1,
          color: theme.colorScheme.onSurface,
        ),
        Text(
          l10n.percentSign,
          style: theme.textTheme.bodySmall?.copyWith(
            fontSize: 10,
            color: theme.appColors.muted,
          ),
        ),
      ],
    );
  }
}

/// What the row shows once it is opened: the one thing this book wants next,
/// and the two ways on from it.
class _OpenRow extends StatelessWidget {
  const _OpenRow({
    required this.book,
    required this.plan,
    required this.due,
    required this.fileMissing,
  });

  final Book book;
  final ReadingPlan? plan;
  final TodayEntry? due;
  final bool fileMissing;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall?.copyWith(
      fontSize: 12,
      height: 1.6,
      color: theme.appColors.muted,
    );

    // In the order the reader can act on: a file that isn't here blocks
    // everything, a book with no goal has nothing to owe, and only then is
    // there a portion to talk about.
    final String note;
    final Widget action;
    // Gold for the two notes that are really a prompt — a file to find, a goal
    // to pick. Muted for the ones that are just a fact.
    var noteColor = theme.colorScheme.primary;
    // The quiet way into the book, under whatever the row is really asking
    // for. Every state that can open the file offers it: nothing here is due
    // is a fact about the plan, not about whether the reader may read.
    String? secondary;

    if (fileMissing) {
      // Stated in gold at body weight, not in red: the reader did nothing
      // wrong — they are on a different phone, or the file was moved — and
      // there is a one-tap way out.
      note = l10n.fileMissing;
      action = OutlinedButton(
        // Straight to this book's own locate flow rather than to the general
        // add-book screen: the reader already said which book they mean, and
        // the file they pick is checked against this book rather than treated
        // as a new import.
        onPressed: () => context.push('/books/${book.id}/locate'),
        child: Text(l10n.libraryLocateFile),
      );
    } else if (plan == null) {
      note = l10n.libraryNoPlanYet;
      action = FilledButton(
        onPressed: () => context.push('/books/${book.id}/plan'),
        child: Text(l10n.libraryPickGoal),
      );
      // A goal is what this app is for, so it keeps the slab. But a book with
      // no goal is still a book, and refusing to open it until the reader has
      // committed to finishing it by a date is the app getting in the way of
      // the only thing it exists to encourage.
      secondary = l10n.readerOpenBook;
    } else if (due case final due?) {
      noteColor = theme.appColors.muted;
      note = l10n.libraryTodayPortion(
        AppNumbers.range(due.nextPage, due.toPage),
        l10n.sessionPages(due.pagesLeft),
      );
      action = FilledButton(
        // Opens on this book's own stretch and nothing else, on the first page
        // not yet read — the same landing Today would give.
        onPressed: () => context.push(
          '/books/${book.id}/read'
          '?from=${due.fromPage}&to=${due.toPage}&page=${due.nextPage}',
        ),
        child: Text(
          due.pagesDone > 0
              ? l10n.todayResumeAt(AppNumbers.format(due.nextPage))
              : l10n.todayStartPortion,
        ),
      );
    } else {
      // Finished for today, paused, or done with — all of which are fine, and
      // none of which the reader owes anything for. Nothing is asked of them
      // here; carrying on is offered, and offered quietly, because a portion
      // that is done is done.
      noteColor = theme.appColors.muted;
      note = l10n.libraryNothingDue;
      action = const SizedBox.shrink();
      secondary = l10n.readerKeepReading;
    }
    final hasAction = action is! SizedBox;

    return Padding(
      padding: const EdgeInsetsDirectional.only(
        start: _plateWidth + AppSpacing.x3,
        bottom: AppSpacing.x4,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(note, style: muted?.copyWith(color: noteColor)),
          if (hasAction) ...[const SizedBox(height: AppSpacing.x3), action],
          const SizedBox(height: AppSpacing.x2),
          // The ways on, both quiet: into the book itself, and into everything
          // else about it. The reason to open a row is to start reading, not
          // to go somewhere — so neither of these is the row's own answer.
          //
          // A wrap rather than a row: two translated labels at a large text
          // scale are two ways to run off the end of a shelf.
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: Wrap(
              children: [
                if (secondary case final label?)
                  TextButton(
                    onPressed: () => context.push('/books/${book.id}/read'),
                    child: Text(label),
                  ),
                TextButton(
                  onPressed: () => context.push('/books/${book.id}'),
                  child: Text(l10n.libraryBookDetails),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
