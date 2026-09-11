import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:pdfrx/pdfrx.dart';

import '../../../core/db/app_database.dart';
import '../../../core/planning/plan_math.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/figure.dart';
import '../../../core/widgets/progress_shapes.dart';
import '../../../core/widgets/screen_header.dart';
import '../../../l10n/app_localizations.dart';
import '../../plan/application/plan_providers.dart';
import '../application/reader_providers.dart';
import '../domain/sitting_clock.dart';
import '../domain/sitting_credit.dart';

/// Screen 8 — the page itself, and one way to say you are done.
///
/// Progress is recorded when the reader says so, not silently as pages turn.
/// Flipping ahead to check a footnote is not reading, and a plan that advanced
/// on scroll position would quietly lie about how far the reader has got.
///
/// The whole book is always open. The day's portion is a mark in the margin and
/// a sentence at the foot — never a fence: a reader who wants to look something
/// up two chapters on, carry on past the portion, or read a book they have set
/// no goal for at all is still reading, and an app that locked the covers on
/// them would be answering a question nobody asked.
class ReaderScreen extends ConsumerWidget {
  const ReaderScreen({
    required this.bookId,
    this.startPage,
    this.fromPage,
    this.toPage,
    super.key,
  });

  final String bookId;

  /// Where to open. Today and the library pass the first unread page of the
  /// session; with nothing passed the book opens on the portion, and a book
  /// with no portion opens where this device last left it.
  final int? startPage;

  /// The stretch the reader came here to read, inclusive.
  ///
  /// Today passes the session's own share. When nothing is passed — a tapped
  /// reminder, or "keep reading" from the shelf — the day's whole portion is
  /// worked out from the plan instead. It bounds what is *counted*, not what
  /// can be seen.
  final int? fromPage;
  final int? toPage;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final book = ref.watch(bookProvider(bookId));
    final plan = ref.watch(activePlanProvider(bookId));
    final path = ref.watch(bookFilePathProvider(bookId));
    final lastPage = ref.watch(lastPageOpenProvider(bookId));

    // Waits on the async values rather than on their contents: three of these
    // have a null that means "no" rather than "not yet", and a book with no
    // plan is a book to read, not a screen still loading.
    final ready =
        book.hasValue && plan.hasValue && path.hasValue && lastPage.hasValue;

    return Scaffold(
      backgroundColor: Theme.of(context).appColors.readerBackground,
      body: SafeArea(
        child: switch ((ready, book.value, path.value)) {
          (false, _, _) || (_, null, _) => const SizedBox.shrink(),
          (_, final book?, null) => Column(
            children: [
              ScreenBackBar(title: book.title),
              Expanded(
                child: EmptyState(
                  title: l10n.fileMissing,
                  message: l10n.fileMissingHint,
                  // The reader came here to read, so the way out of an empty
                  // screen has to be the thing that makes reading possible —
                  // not an instruction to go and find it somewhere else.
                  action: OutlinedButton(
                    onPressed: () => context.push('/books/$bookId/locate'),
                    child: Text(l10n.libraryLocateFile),
                  ),
                ),
              ),
            ],
          ),
          (_, final book?, final path?) => _Reader(
            book: book,
            plan: plan.value,
            path: path,
            startPage: startPage,
            lastPageOpen: lastPage.value,
            portion: _portionFor(ref, plan.value),
          ),
        },
      ),
    );
  }

  /// The stretch the ruler counts and the finish button speaks for.
  ///
  /// Null when there is nothing to count — a book with no plan, or one whose
  /// plan is read out. That is a reader with no portion, not a reader with
  /// nothing to read: the book opens either way.
  DayAssignment? _portionFor(WidgetRef ref, ReadingPlan? plan) {
    if (plan == null) return null;
    final spec = ref.read(appDatabaseProvider).specOf(plan);

    if (fromPage case final from?) {
      final to = toPage ?? from;
      return DayAssignment(
        fromPage: from.clamp(spec.startPage, spec.endPage),
        toPage: to.clamp(from, spec.endPage),
      );
    }

    return nextAssignment(spec, plan.lastPageRead);
  }
}

class _Reader extends ConsumerStatefulWidget {
  const _Reader({
    required this.book,
    required this.plan,
    required this.path,
    required this.startPage,
    required this.lastPageOpen,
    required this.portion,
  });

  final Book book;

  /// Null for a book the reader has set no goal for. It reads exactly the
  /// same; there is simply nothing to credit at the end of it.
  final ReadingPlan? plan;
  final String path;
  final int? startPage;

  /// The page this device last had the book open on, or null if it never has.
  final int? lastPageOpen;
  final DayAssignment? portion;

  @override
  ConsumerState<_Reader> createState() => _ReaderState();
}

class _ReaderState extends ConsumerState<_Reader>
    with WidgetsBindingObserver, TickerProviderStateMixin {
  final _controller = PdfViewerController();

  /// Drives the sheet that swings across when a page is turned.
  late final _turn = AnimationController(
    duration: const Duration(milliseconds: 420),
    vsync: this,
  );

  /// True while the turning sheet is swinging toward the spine rather than
  /// away from it — a tap near the spine goes back.
  var _turningForward = true;

  /// The viewer's own width, recorded as it is laid out.
  ///
  /// Measured here rather than read off the tap's `BuildContext`: the context
  /// the viewer hands its tap handler is its own internals, not the box the
  /// page is drawn in, so its size is not the width the tap should be split
  /// against.
  double? _viewportWidth;

  /// Drives the brass sweep that confirms a finished portion.
  late final _sweep = AnimationController(
    duration: const Duration(milliseconds: 520),
    vsync: this,
  );

  /// Time the book has actually been in front of the reader this sitting.
  final _spentReading = SittingClock();

  /// The page the reader started this sitting on. Everything from here to the
  /// furthest page they reached is what gets credited.
  late final int _openedAt = (widget.startPage ?? _resumePage).clamp(
    1,
    widget.book.pageCount,
  );

  late int _page = _openedAt;

  /// The furthest page this sitting has reached.
  ///
  /// Kept apart from [_page] because the reader may turn back — to re-read a
  /// paragraph, to check a footnote, to look at the map at the front — and the
  /// pages they had already read stay read. Crediting the page they happen to
  /// be standing on when they finish would punish them for looking back.
  late int _furthest = _openedAt;

  var _saving = false;
  var _copying = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _turn.dispose();
    _sweep.dispose();
    super.dispose();
  }

  /// Turns the page, and runs the sheet that makes it look turned.
  ///
  /// The jump itself is instantaneous — the viewer is told `Duration.zero` —
  /// because the motion the reader sees is the sheet swinging over the top of
  /// it. Letting the viewer scroll *and* the sheet turn would be two different
  /// animations of the same event, half a beat apart.
  void _turnPage({required bool forward}) {
    if (_turn.isAnimating) return;

    final next = forward ? _page + 1 : _page - 1;
    if (next < 1 || next > _lastPage) return;

    setState(() => _turningForward = forward);
    unawaited(_controller.goToPage(pageNumber: next, duration: Duration.zero));
    unawaited(_turn.forward(from: 0));
  }

  /// Turns the page unless the tap was doing something else.
  ///
  /// Long-press and double-tap fall through to the viewer, which is what picks
  /// a word and what zooms. A plain tap on *selected* text falls through too —
  /// there the reader is dismissing a selection, and turning the page out from
  /// under them would lose the thing they had just picked.
  bool _onTap(
    BuildContext context,
    PdfViewerController controller,
    PdfViewerGeneralTapHandlerDetails details,
  ) {
    if (details.type != PdfViewerGeneralTapType.tap) return false;
    if (details.tapOn == PdfViewerPart.selectedText) return false;

    final width = _viewportWidth;
    if (width == null || width <= 0) return false;

    // The strip along the spine goes back; the rest of the page goes on. In a
    // bound book the hand that turns forward reaches for the fore edge, and
    // `Directionality` is what decides which side that is.
    final fromStart = Directionality.of(context) == TextDirection.rtl
        ? width - details.localPosition.dx
        : details.localPosition.dx;
    _turnPage(forward: fromStart > width * _spineStripFraction);
    return true;
  }

  /// How much of the page's width, measured from the spine, turns back rather
  /// than forward.
  static const _spineStripFraction = 0.22;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Anything short of resumed means nobody is looking at the page. Without
    // this, a reader who locks the phone mid-portion and comes back tomorrow
    // banks a night's sleep as an evening's reading.
    if (state == AppLifecycleState.resumed) {
      _spentReading.resume();
    } else {
      _spentReading.pause();
    }
  }

  /// The page on screen changed — by a tap, a scroll, or a pinch.
  ///
  /// The bookmark is written on every turn rather than on the way out: the
  /// reader leaves this screen by the back gesture, by the home button, or by
  /// the phone dying, and only one of those three gives us a chance to save.
  /// It is a single-row write to a local table, and nothing reads it until the
  /// book is opened again.
  void _onPageChanged(int? page) {
    if (page == null || page == _page) return;
    setState(() {
      _page = page;
      if (page > _furthest) _furthest = page;
    });
    unawaited(
      ref
          .read(readerBookmarkProvider)
          .remember(bookId: widget.book.id, page: page),
    );
  }

  /// Where to open when the caller named no page.
  ///
  /// The portion comes first: a tapped reminder is asking for the day's pages,
  /// not for wherever the reader last happened to be browsing. The bookmark
  /// answers only when there is no portion to point at — which is exactly what
  /// it was written for, a book with no plan or one already read out.
  int get _resumePage => widget.portion?.fromPage ?? widget.lastPageOpen ?? 1;

  /// The last page there is to turn to.
  ///
  /// The file's own count once the viewer has opened it, because a book
  /// relinked from another edition may be longer or shorter than the count
  /// recorded when it was added.
  int get _lastPage =>
      _controller.isReady ? _controller.pages.length : widget.book.pageCount;

  /// Copy, and nothing else.
  ///
  /// "Select all" means the whole file to the viewer — eight hundred pages onto
  /// the clipboard in one tap. Copying a line out of a book is part of reading
  /// it; taking the book is not, and it is not a thing a reader does by
  /// accident except through this menu item.
  void _copyOnly(
    PdfViewerContextMenuBuilderParams params,
    List<ContextMenuButtonItem> items,
  ) {
    items.removeWhere((item) => item.type == ContextMenuButtonType.selectAll);
  }

  /// Pages this sitting has covered, at least one — being on a page counts as
  /// having read it.
  int get _pagesThisSitting => _furthest - _openedAt + 1;

  /// The stretch a finished portion credits, or null if it credits nothing.
  DayAssignment? _credit(ReadingPlan plan) => sittingCredit(
    openedAt: _openedAt,
    furthest: _furthest,
    planStart: plan.startPage,
    planEnd: plan.endPage,
  );

  /// The whole of the page on screen, on the clipboard.
  ///
  /// Word-by-word selection is for a phrase; a reader who wants the page wants
  /// the page, and dragging two handles down a scan to get it is a chore. The
  /// current page only — never the portion, never the book — because that is
  /// what the reader can see, and seeing it is what makes taking it honest.
  Future<void> _copyPage() async {
    if (_copying || !_controller.isReady) return;
    setState(() => _copying = true);

    String text;
    try {
      final page = _controller.pages[_page - 1];
      text = (await page.loadStructuredText()).fullText.trim();
    } finally {
      if (mounted) setState(() => _copying = false);
    }

    if (!mounted) return;
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);

    // A scanned page with no OCR layer yields nothing. Saying so beats a
    // "copied" that leaves the reader pasting emptiness into a note.
    if (text.isEmpty) {
      messenger.showSnackBar(SnackBar(content: Text(l10n.readerPageHasNoText)));
      return;
    }

    await Clipboard.setData(ClipboardData(text: text));
    messenger.showSnackBar(
      SnackBar(content: Text(l10n.readerPageCopied(_page))),
    );
  }

  Future<void> _finish() async {
    // Only ever offered with a plan behind it — there is nowhere to record a
    // portion of a book the reader set no goal for.
    final plan = widget.plan;
    if (_saving || plan == null) return;
    setState(() => _saving = true);

    // The brass sweep runs *with* the write rather than after it: the reader
    // has finished, and the screen should say so at the moment they say it,
    // not once the database agrees. It is a confirmation, not a spinner —
    // v2's rule for this moment is "a quiet confirmation, not a modal".
    final swept = _sweep.forward(from: 0);

    try {
      // Null only for a sitting spent entirely outside the plan, which is not
      // something the button is offered for. Nothing to say to the plan, but
      // the reader still said they had finished, so the screen still answers.
      if (_credit(plan) case final credit?) {
        await ref
            .read(progressWriterProvider)
            .record(
              planId: plan.id,
              fromPage: credit.fromPage,
              toPage: credit.toPage,
              spent: _spentReading.elapsed,
            );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }

    // Never leaves before the sweep has landed, however fast the write was.
    // `orCancel` matters: leaving the screen mid-sweep disposes the controller,
    // and a plain ticker future would simply never complete.
    await swept.orCancel.catchError((Object _) {});

    if (!mounted) return;
    final navigator = Navigator.of(context);
    if (navigator.canPop()) navigator.pop();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final portion = widget.portion;

    // The portion is finished once the reader has *reached* its last page,
    // whatever page they have since turned to. Offering the button before
    // that would invite them to call a day's reading done that they have not
    // done, and the plan would take them at their word.
    //
    // It takes a sitting that began at or before the portion, too. A reader
    // who opens the book somewhere past it — on the bookmark, or deep in a
    // chapter they were looking something up in — has not read today's pages
    // by standing there, and must not be offered a button that says they have.
    final portionRead =
        portion != null &&
        _openedAt <= portion.toPage &&
        _furthest >= portion.toPage;

    // How far into the portion the page on screen is, floored at nothing: the
    // reader may be standing in front of it, at the index or the map.
    final done = portion == null
        ? 0
        : (_page - portion.fromPage + 1).clamp(0, portion.pageCount);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _ReaderHead(book: widget.book, page: _page),
        Expanded(
          child: Stack(
            children: [
              Positioned.fill(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    // A plain field, not `setState`: this is recorded during
                    // layout and only ever read by a later tap, so asking for
                    // another frame here would be a rebuild loop for nothing.
                    _viewportWidth = constraints.maxWidth;
                    return PdfViewer.file(
                      widget.path,
                      controller: _controller,
                      initialPageNumber: _openedAt,
                      params: PdfViewerParams(
                        backgroundColor: theme.appColors.readerBackground,
                        // Long-press picks a word, the handles widen it, and the
                        // menu offers to copy. Stated rather than left to the
                        // viewer's default, because copying a line out of the book
                        // is part of reading it, not an incidental of the package.
                        textSelectionParams: const PdfTextSelectionParams(
                          enabled: true,
                        ),
                        customizeContextMenuItems: _copyOnly,
                        onGeneralTap: _onTap,
                        onPageChanged: _onPageChanged,
                      ),
                    );
                  },
                ),
              ),
              // The marginal ruler, on the fore edge — the side the hand turns
              // from. It is the portion at page resolution, and it advances as
              // the reader does.
              //
              // It is also the only thing left saying where the portion is, now
              // that the reader can turn anywhere in the book: turn behind it
              // and every mark goes faint, turn past it and every mark is
              // inked. That is the whole readout.
              //
              // Deliberately deaf: it sits over the viewer, on the very strip
              // the reader reaches for to turn forward, and a readout that ate
              // those taps would break the gesture it is drawn beside.
              if (portion != null)
                PositionedDirectional(
                  end: 7,
                  top: 0,
                  bottom: 0,
                  child: IgnorePointer(
                    child: Center(
                      child: _PortionRuler(
                        pages: portion.pageCount,
                        at: _page - portion.fromPage,
                      ),
                    ),
                  ),
                ),
              // Above everything, and never in the way of a tap.
              Positioned.fill(
                child: IgnorePointer(
                  child: _TurningSheet(turn: _turn, forward: _turningForward),
                ),
              ),
              Positioned.fill(
                child: IgnorePointer(child: _BrassSweep(sweep: _sweep)),
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
              Row(
                children: [
                  Text(
                    // Two separate figures in one sentence are safe under
                    // RTL; only an adjacent pair like a page range needs
                    // isolating.
                    portion == null || portionRead
                        ? l10n.sessionPages(_pagesThisSitting)
                        : l10n.readerPortionProgress(done, portion.pageCount),
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontSize: 11.5,
                      color: theme.appColors.muted,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.x3),
                  // The rule measures whatever the reader is actually doing:
                  // the portion while there is one to read, the book itself
                  // when they are reading without a goal. Scope and shape stay
                  // in step — that is the whole point of having three shapes.
                  Expanded(
                    child: portion == null
                        ? BookRule(fraction: (_page / _lastPage).clamp(0, 1))
                        : SessionRule(fraction: done / portion.pageCount),
                  ),
                  // Sits with the progress rather than under it: it is about
                  // the page on screen, not about the day's reading, and the
                  // buttons below all speak to the plan.
                  IconButton(
                    onPressed: _copying ? null : _copyPage,
                    icon: const Icon(Icons.content_copy_outlined, size: 17),
                    color: theme.appColors.muted,
                    tooltip: l10n.readerCopyPage,
                    visualDensity: VisualDensity.compact,
                    constraints: const BoxConstraints.tightFor(
                      width: AppSpacing.minTapTarget,
                      height: AppSpacing.minTapTarget,
                    ),
                  ),
                ],
              ),
              // Said once, small, and only while there is nothing else being
              // asked: a gesture nobody can see has to be told, but a reader
              // who has finished their portion is being asked something now.
              if (!portionRead) ...[
                const SizedBox(height: AppSpacing.x2),
                Text(
                  l10n.readerTapToTurn,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontSize: 11.5,
                    color: theme.appColors.muted,
                  ),
                ),
              ],
              // Appears once the portion has been read to its end, and stays
              // there — the reader who carries on into tomorrow's pages is
              // still free to stop and say so, and everything they read past
              // the portion is credited with it.
              if (portionRead) ...[
                const SizedBox(height: AppSpacing.x3),
                FilledButton(
                  onPressed: _saving ? null : _finish,
                  child: Text(l10n.readerFinishSession),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

/// The line of small type across the top of the reader: the way out, the book
/// you are in, and the folio.
///
/// A running head, not an app bar. The same furniture the Today page wears, for
/// the same reason — this is a page of a book, and a book names itself in the
/// margin rather than in a bar of chrome above the text.
class _ReaderHead extends StatelessWidget {
  const _ReaderHead({required this.book, required this.page});

  final Book book;
  final int page;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final head = theme.textTheme.labelSmall?.copyWith(
      fontSize: 11,
      letterSpacing: 0.4,
      color: theme.appColors.muted,
    );

    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(
        AppSpacing.x2,
        AppSpacing.x1,
        AppSpacing.x3,
        AppSpacing.x2,
      ),
      child: Row(
        children: [
          IconButton(
            onPressed: () => Navigator.of(context).maybePop(),
            // `chevron_left` carries `matchTextDirection`, so it points the
            // right way under RTL without a manual flip.
            icon: const Icon(Icons.chevron_left, size: 20),
            color: theme.appColors.muted,
            tooltip: l10n.actionBack,
            constraints: const BoxConstraints.tightFor(
              width: AppSpacing.minTapTarget,
              height: AppSpacing.minTapTarget,
            ),
          ),
          Expanded(
            child: Text(
              book.author == null
                  ? book.title
                  : l10n.todayRunningHead(book.title, book.author!),
              style: head,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: AppSpacing.x2),
          Figure.number(page, size: 13, color: theme.appColors.muted),
        ],
      ),
    );
  }
}

/// The portion, ruled down the fore edge: one mark per page, inked behind the
/// reader, brass at the page they are on, faint ahead of them.
///
/// Small and off to the side on purpose. It is not a control and not a
/// readout — it is the thickness of what is left, which in a real book you can
/// see without looking.
class _PortionRuler extends StatelessWidget {
  const _PortionRuler({required this.pages, required this.at});

  final int pages;

  /// 0-based index of the current page within the portion.
  final int at;

  /// Past this the marks stop being countable and become a smudge.
  static const _maxPages = 40;

  @override
  Widget build(BuildContext context) {
    if (pages < 2 || pages > _maxPages) return const SizedBox.shrink();
    final theme = Theme.of(context);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        for (var i = 0; i < pages; i++) ...[
          if (i > 0) const SizedBox(height: 4),
          AnimatedContainer(
            duration: const Duration(milliseconds: 260),
            curve: Curves.easeOutCubic,
            height: 1.5,
            width: switch (i) {
              _ when i == at => 18,
              _ when i < at => 13,
              _ => 8,
            },
            color: switch (i) {
              _ when i == at => theme.appColors.accentStroke,
              _ when i < at => theme.colorScheme.onSurface,
              _ => theme.appColors.hairline,
            },
          ),
        ],
      ],
    );
  }
}

/// The sheet that swings across when a page is turned.
///
/// Hinged at the spine and rotated about Y, with a shadow that deepens as it
/// lifts — the thing a turning page actually does. It is drawn as paper rather
/// than as a copy of the page underneath: both sides of the turn are the same
/// cream, and at 420ms nobody reads the sheet, they read the motion.
class _TurningSheet extends AnimatedWidget {
  const _TurningSheet({required this.turn, required this.forward})
    : super(listenable: turn);

  final Animation<double> turn;
  final bool forward;

  @override
  Widget build(BuildContext context) {
    final t = turn.value;
    if (t == 0 || t == 1) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final colors = theme.appColors;
    final isRtl = Directionality.of(context) == TextDirection.rtl;

    // Which way the sheet swings: toward the spine going forward, away from it
    // coming back — and mirrored again for a right-to-left book.
    final direction = (forward ? -1.0 : 1.0) * (isRtl ? -1.0 : 1.0);
    final angle = direction * (t * 1.5708);

    return Opacity(
      // Fades out over the last third, so the page underneath is not revealed
      // by a hard edge snapping away.
      opacity: t < 0.66 ? 1 : (1 - t) / 0.34,
      child: Transform(
        alignment: AlignmentDirectional.centerStart,
        transform: Matrix4.identity()
          // Perspective. Without it `rotateY` is an orthographic squash and
          // the sheet reads as a shrinking rectangle rather than a turning one.
          ..setEntry(3, 2, 0.0012)
          ..rotateY(angle),
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: AlignmentDirectional.centerStart,
              end: AlignmentDirectional.centerEnd,
              colors: [
                colors.gutter,
                colors.readerBackground,
                colors.readerBackground,
              ],
              stops: const [0, 0.12, 1],
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.28 * t),
                blurRadius: 26 * t,
                offset: Offset(isRtl ? 10 * t : -10 * t, 6 * t),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The brass wash that sweeps down the screen when a portion is finished.
///
/// v2 asked for a confirmation that is not a modal: nothing to dismiss, nothing
/// to read, no decision. A band of the accent falls the height of the page and
/// is gone — the reader has already turned away by the time it lands.
class _BrassSweep extends AnimatedWidget {
  const _BrassSweep({required this.sweep}) : super(listenable: sweep);

  final Animation<double> sweep;

  @override
  Widget build(BuildContext context) {
    final t = sweep.value;
    if (t == 0) return const SizedBox.shrink();

    final colors = Theme.of(context).appColors;

    return FractionallySizedBox(
      alignment: Alignment.topCenter,
      heightFactor: 1,
      child: ShaderMask(
        blendMode: BlendMode.dstIn,
        shaderCallback: (bounds) => LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          // A band, not a curtain: opaque in the middle and clear at both
          // ends, travelling from above the screen to below it.
          colors: const [Colors.transparent, Colors.white, Colors.transparent],
          stops: [
            (t * 1.6 - 0.45).clamp(0.0, 1.0),
            (t * 1.6 - 0.22).clamp(0.0, 1.0),
            (t * 1.6).clamp(0.0, 1.0),
          ],
        ).createShader(bounds),
        child: ColoredBox(color: colors.accentStroke.withValues(alpha: 0.55)),
      ),
    );
  }
}
