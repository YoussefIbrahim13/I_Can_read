import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pdfrx/pdfrx.dart';

import '../../../core/db/app_database.dart';
import '../../../core/planning/plan_math.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/progress_shapes.dart';
import '../../../core/widgets/screen_header.dart';
import '../../../l10n/app_localizations.dart';
import '../../plan/application/plan_providers.dart';
import '../application/reader_providers.dart';
import '../domain/portion_layout.dart';

/// Screen 8 — the page itself, and one way to say you are done.
///
/// Progress is recorded when the reader says so, not silently as pages turn.
/// Flipping ahead to check a footnote is not reading, and a plan that advanced
/// on scroll position would quietly lie about how far the reader has got.
class ReaderScreen extends ConsumerWidget {
  const ReaderScreen({
    required this.bookId,
    this.startPage,
    this.fromPage,
    this.toPage,
    super.key,
  });

  final String bookId;

  /// Where to open. Today passes the first unread page of the session.
  final int? startPage;

  /// The stretch the reader is here to read, inclusive.
  ///
  /// Today passes the session's own share. When nothing is passed — a tapped
  /// reminder, or the library — the day's whole portion is worked out from the
  /// plan instead. The reader never shows the book outside this.
  final int? fromPage;
  final int? toPage;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final book = ref.watch(bookProvider(bookId)).value;
    final plan = ref.watch(activePlanProvider(bookId)).value;
    final path = ref.watch(bookFilePathProvider(bookId)).value;

    return Scaffold(
      backgroundColor: Theme.of(context).appColors.readerBackground,
      body: SafeArea(
        child: switch ((book, plan, path)) {
          (null, _, _) || (_, null, _) => const SizedBox.shrink(),
          (final book?, _, null) => Column(
            children: [
              ScreenBackBar(title: book.title),
              Expanded(
                child: EmptyState(
                  title: l10n.fileMissing,
                  message: l10n.fileMissingHint,
                ),
              ),
            ],
          ),
          (final book?, final plan?, final path?) => _Reader(
            book: book,
            plan: plan,
            path: path,
            startPage: startPage,
            portion: _portionFor(ref, plan, book),
          ),
        },
      ),
    );
  }

  /// The pages this sitting is allowed to show.
  ///
  /// Falls back to the day's portion, and then to the plan itself: the reader
  /// must never open onto nothing, even for a book that is already finished or
  /// reached from somewhere that had no session in mind.
  DayAssignment _portionFor(WidgetRef ref, ReadingPlan plan, Book book) {
    final spec = ref.read(appDatabaseProvider).specOf(plan);

    if (fromPage case final from?) {
      final to = toPage ?? from;
      return DayAssignment(
        fromPage: from.clamp(spec.startPage, spec.endPage),
        toPage: to.clamp(from, spec.endPage),
      );
    }

    return nextAssignment(spec, plan.lastPageRead) ??
        DayAssignment(fromPage: spec.startPage, toPage: spec.endPage);
  }
}

class _Reader extends ConsumerStatefulWidget {
  const _Reader({
    required this.book,
    required this.plan,
    required this.path,
    required this.startPage,
    required this.portion,
  });

  final Book book;
  final ReadingPlan plan;
  final String path;
  final int? startPage;
  final DayAssignment portion;

  @override
  ConsumerState<_Reader> createState() => _ReaderState();
}

class _ReaderState extends ConsumerState<_Reader> {
  final _controller = PdfViewerController();

  /// The page the reader started this sitting on. Everything from here to the
  /// current page is what gets credited.
  late final int _openedAt = (widget.startPage ?? _resumePage).clamp(
    widget.portion.fromPage,
    widget.portion.toPage,
  );

  late int _page = _openedAt;
  var _saving = false;

  /// Set once the reader asks to carry on past the day's portion.
  ///
  /// One-way, and only for this sitting: the next time they open the book they
  /// are back to a bounded portion, because that is the thing that makes the
  /// book finishable. Nothing is lost by reading on — pages past the portion
  /// are recorded like any other, and the finish date moves closer.
  var _unlocked = false;

  /// What the viewer is allowed to show. The plan's own range once unlocked,
  /// never the whole file: pages the reader excluded from the plan — front
  /// matter, indexes — were excluded on purpose.
  DayAssignment get _portion => _unlocked
      ? DayAssignment(
          fromPage: widget.plan.startPage,
          toPage: widget.plan.endPage,
        )
      : widget.portion;

  void _keepReading() {
    setState(() => _unlocked = true);
    // `layoutPages` is only consulted on a relayout, so changing what it
    // returns is not enough on its own.
    _controller.invalidate();
  }

  /// Where to open when nobody said: the page after the last one read.
  int get _resumePage {
    final next = widget.plan.lastPageRead + 1;
    return next.clamp(widget.plan.startPage, widget.book.pageCount);
  }

  PdfPageLayout _layoutPortion(List<PdfPage> pages, PdfViewerParams params) {
    final layout = portionLayout(
      pages: [for (final page in pages) Size(page.width, page.height)],
      from: _portion.fromPage,
      to: _portion.toPage,
      margin: params.margin,
    );
    return PdfPageLayout(
      pageLayouts: layout.rects,
      documentSize: layout.size,
    );
  }

  int? _currentPage(
    Rect visible,
    List<Rect> rects,
    PdfViewerController controller,
  ) {
    return currentPortionPage(
      visible: visible,
      rects: rects,
      from: _portion.fromPage,
      to: _portion.toPage,
    );
  }

  /// Pages this sitting has covered, at least one — being on a page counts as
  /// having read it.
  int get _pagesThisSitting => (_page - _openedAt + 1).clamp(1, _page);

  Future<void> _finish() async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      await ref
          .read(progressWriterProvider)
          .record(
            planId: widget.plan.id,
            fromPage: _openedAt,
            toPage: _page < _openedAt ? _openedAt : _page,
          );
    } finally {
      if (mounted) setState(() => _saving = false);
    }

    if (!mounted) return;
    final navigator = Navigator.of(context);
    if (navigator.canPop()) navigator.pop();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    // The rule measures whatever the reader can actually see: the session
    // while the portion holds, the book once they have read past it. Scope and
    // shape stay in step — that is the whole point of having three shapes.
    final done = _page - _portion.fromPage + 1;
    final left = widget.portion.toPage - _page;
    final atPortionEnd = left <= 0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ScreenBackBar(title: widget.book.title),
        Expanded(
          child: PdfViewer.file(
            widget.path,
            controller: _controller,
            initialPageNumber: _openedAt,
            params: PdfViewerParams(
              backgroundColor: theme.appColors.readerBackground,
              layoutPages: _layoutPortion,
              calculateCurrentPageNumber: _currentPage,
              onPageChanged: (page) {
                if (page != null && page != _page) setState(() => _page = page);
              },
            ),
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
                  Expanded(
                    child: Text(
                      // Two separate figures in one sentence are safe under
                      // RTL; only an adjacent pair like a page range needs
                      // isolating.
                      l10n.readerPageOf(_page, widget.book.pageCount),
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
                  Text(
                    // Once past the portion, "pages left today" is no longer
                    // true of anything; what is left is the sitting itself.
                    atPortionEnd
                        ? l10n.sessionPages(_pagesThisSitting)
                        : l10n.todayRemaining(left),
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontSize: 11.5,
                      color: theme.appColors.muted,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.x2),
              if (_unlocked)
                BookRule(fraction: done / _portion.pageCount)
              else
                SessionRule(fraction: done / _portion.pageCount),
              const SizedBox(height: AppSpacing.x4 - 4),
              OutlinedButton(
                onPressed: _saving ? null : _finish,
                child: Text(l10n.readerFinishSession),
              ),
              // Offered only at the end of the portion, where it answers the
              // question the reader is actually asking. Anywhere earlier it
              // would just be a way out of the frame the plan exists to hold.
              if (atPortionEnd && !_unlocked)
                TextButton(
                  onPressed: _keepReading,
                  child: Text(l10n.readerKeepReading),
                ),
            ],
          ),
        ),
      ],
    );
  }
}
