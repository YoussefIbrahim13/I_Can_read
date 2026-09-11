/// Three scopes, three shapes — the rule this file exists to enforce.
///
/// A reader must never see the same shape mean two things, so progress is
/// drawn by separate widgets rather than one parameterised bar:
///
/// * [SessionRule] — *this session*. A gold hairline filling from the inline
///   start.
/// * [SessionComb] — *this session*, at page resolution. Redesign v2's Today
///   hero. Same scope as [SessionRule]; the rule is that one shape must not
///   mean two scopes, not that one scope gets only one shape. The comb is used
///   where the session **is** the subject and the reader can act on individual
///   pages; the rule is used where progress is a footnote, such as the reader's
///   own footer, where a comb would compete with the text.
/// * [TodayBar]    — *today*. One segment per session, so the split is visible.
/// * [BookRule]    — *the whole book*. A thicker ink rule, paired with a
///   percentage in Cormorant figures.
/// * [BookComb]    — *the whole book*, at page resolution. Redesign v2's book
///   detail and plan screens. Book scope's second shape, for the two screens
///   where the book itself is the subject and a 2px rule is too thin to carry
///   it. Both of its constructors are book-scope statements — the rule is that
///   one shape must not mean two *scopes*, so a shape may say two things about
///   the same scope, and this one must never be pointed at a session or a day.
///
/// Keeping them as named widgets is what stops the scopes being conflated
/// later. Do not add a `style` parameter that lets one become another.
library;

import 'package:flutter/material.dart';

import '../theme/app_tokens.dart';

/// Session scope: a 1px gold hairline over a 1px ink track.
class SessionRule extends StatelessWidget {
  const SessionRule({required this.fraction, super.key});

  /// Clamped, so a session read past its quota still reads as full.
  final double fraction;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).appColors;
    return SizedBox(
      height: 1,
      child: Stack(
        children: [
          Positioned.fill(child: ColoredBox(color: colors.hairline)),
          FractionallySizedBox(
            alignment: AlignmentDirectional.centerStart,
            widthFactor: fraction.clamp(0.0, 1.0),
            // Without this the box is handed a *loose* height, and a
            // `ColoredBox` with no child takes `constraints.smallest` — so the
            // fill lays out one pixel wide and zero high, and the rule silently
            // never draws its progress at all.
            heightFactor: 1,
            child: ColoredBox(color: colors.accentStroke),
          ),
        ],
      ),
    );
  }
}

/// Session scope at page resolution: one tick per page in the portion, ink for
/// pages already read and gold at 58% height for those still ahead.
///
/// Reading it is immediate in a way a percentage is not — twelve marks, five
/// filled, and the reader knows the shape of what is left without doing any
/// arithmetic. Tapping a tick opens the reader at that page.
class SessionComb extends StatelessWidget {
  const SessionComb({
    required this.pages,
    required this.pagesDone,
    this.onTapPage,
    super.key,
  });

  /// Ticks drawn. A portion of zero pages renders nothing rather than an empty
  /// track, because there is no session to describe.
  final int pages;
  final int pagesDone;

  /// Passed the 0-based index of the tapped page within the portion.
  final ValueChanged<int>? onTapPage;

  /// The drawn height of a fully-read tick.
  static const _barHeight = 38.0;

  /// Pages still ahead are drawn short, so the read run reads as a solid block.
  static const _unreadFraction = 0.58;

  @override
  Widget build(BuildContext context) {
    if (pages < 1) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final done = pagesDone.clamp(0, pages);

    return SizedBox(
      // Taller than the bars so each tick clears the 44px tap target while the
      // drawn comb stays 38.
      height: AppSpacing.minTapTarget,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (var i = 0; i < pages; i++) ...[
            if (i > 0) const SizedBox(width: 4),
            Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: onTapPage == null ? null : () => onTapPage!(i),
                child: Align(
                  alignment: Alignment.bottomCenter,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 260),
                    curve: Curves.easeOutCubic,
                    height: i < done
                        ? _barHeight
                        : _barHeight * _unreadFraction,
                    decoration: BoxDecoration(
                      color: i < done
                          ? theme.colorScheme.onSurface
                          : theme.appColors.accentStroke,
                      borderRadius: BorderRadius.circular(1),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// One session's share of today, and whether it is done.
@immutable
class TodaySegment {
  const TodaySegment({required this.pages, required this.done});

  /// Weights the segment, so a 15-page session is visibly wider than a 5-page
  /// one. The split is the information; an even bar would hide it.
  final int pages;
  final bool done;
}

/// Today scope: one flex-weighted segment per session, separated by 3px gaps.
class TodayBar extends StatelessWidget {
  const TodayBar({required this.segments, this.height = 4, super.key});

  final List<TodaySegment> segments;
  final double height;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).appColors;
    if (segments.isEmpty) {
      return SizedBox(
        height: height,
        child: ColoredBox(color: colors.hairline),
      );
    }

    return SizedBox(
      height: height,
      child: Row(
        // Stretch, not the default centre: a centred child is given a loose
        // height, and a `ColoredBox` with no child collapses to zero under one
        // — which draws nothing while still being in the tree.
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final (index, segment) in segments.indexed) ...[
            if (index > 0) const SizedBox(width: 3),
            Expanded(
              // A zero-page session would otherwise collapse to nothing and
              // make the session count disagree with the segment count.
              flex: segment.pages < 1 ? 1 : segment.pages,
              child: ColoredBox(
                color: segment.done ? colors.done : colors.hairline,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Book scope at page resolution: the whole book drawn as a run of upright
/// strokes, one band of "pages" read left to right in the reading direction.
///
/// Two readings, both about the book:
///
/// * [BookComb.progress] inks the pages behind the reader, leaves the ones
///   ahead faint, and stands a brass rule at the place they stopped.
/// * [BookComb.span] brasses the stretch a plan covers and leaves the rest of
///   the book faint, so "from page 12 to 632" is a picture before it is a
///   sentence.
///
/// The strokes are drawn at a fixed pitch rather than one-per-page: a 900-page
/// book at one stroke each is a solid block, and the point of the shape is that
/// it reads as *pages* rather than as a bar.
class BookComb extends StatelessWidget {
  /// How far through the book the reader is, 0–1.
  const BookComb.progress({
    required double fraction,
    this.height = 64,
    super.key,
  }) : _fraction = fraction < 0 ? 0.0 : (fraction > 1 ? 1.0 : fraction),
       _from = null,
       _to = null;

  /// The stretch [from]–[to] of a book that is [of] pages long, 1-based and
  /// inclusive, as a plan covers it.
  const BookComb.span({
    required int from,
    required int to,
    required int of,
    this.height = 40,
    super.key,
  }) : _fraction = null,
       _from = of < 1 ? 0.0 : (from - 1) / of,
       _to = of < 1 ? 1.0 : to / of;

  final double height;

  final double? _fraction;
  final double? _from;
  final double? _to;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SizedBox(
      height: height,
      child: CustomPaint(
        size: Size.infinite,
        painter: _BookCombPainter(
          fraction: _fraction,
          from: _from?.clamp(0.0, 1.0),
          to: _to?.clamp(0.0, 1.0),
          read: theme.colorScheme.onSurface,
          unread: theme.colorScheme.surfaceContainerHighest,
          mark: theme.appColors.accentStroke,
          rightToLeft: Directionality.of(context) == TextDirection.rtl,
        ),
      ),
    );
  }
}

class _BookCombPainter extends CustomPainter {
  const _BookCombPainter({
    required this.fraction,
    required this.from,
    required this.to,
    required this.read,
    required this.unread,
    required this.mark,
    required this.rightToLeft,
  });

  /// Set for [BookComb.progress]; null for a span.
  final double? fraction;

  /// Set for [BookComb.span]; null for progress.
  final double? from;
  final double? to;

  final Color read;
  final Color unread;
  final Color mark;

  /// The book starts at the trailing edge in Arabic, so the whole comb is
  /// mirrored rather than merely right-aligned — page 1 has to sit where the
  /// reader's eye starts.
  final bool rightToLeft;

  static const _pitch = 4.0;
  static const _stroke = 2.0;

  /// The place-marker, in strokes. Wider than a page stroke because it is a
  /// different kind of statement: not a page, a position.
  static const _markerStrokes = 2;

  @override
  void paint(Canvas canvas, Size size) {
    final count = (size.width / _pitch).floor();
    if (count < 1) return;

    final marker = fraction == null
        ? -1
        : (fraction! * count).floor().clamp(0, count - 1);
    final firstInSpan = from == null ? -1 : (from! * count).floor();
    final lastInSpan = to == null ? -1 : (to! * count).ceil() - 1;

    final paint = Paint();
    for (var i = 0; i < count; i++) {
      paint.color = fraction != null
          ? switch (i) {
              _ when i < marker => read,
              _ when i < marker + _markerStrokes => mark,
              _ => unread,
            }
          : (i >= firstInSpan && i <= lastInSpan ? mark : unread);

      // Mirroring the index rather than the canvas keeps the strokes on whole
      // pixels in both directions; a canvas flip lands them on halves and the
      // comb comes out furry.
      final slot = rightToLeft ? count - 1 - i : i;
      canvas.drawRect(
        Rect.fromLTWH(slot * _pitch, 0, _stroke, size.height),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_BookCombPainter old) =>
      old.fraction != fraction ||
      old.from != from ||
      old.to != to ||
      old.read != read ||
      old.unread != unread ||
      old.mark != mark ||
      old.rightToLeft != rightToLeft;
}

/// Book scope: a 2px ink rule. The accompanying percentage is set by the
/// caller with `Figure`, because its size varies by screen.
class BookRule extends StatelessWidget {
  const BookRule({required this.fraction, this.height = 2, super.key});

  final double fraction;
  final double height;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      height: height,
      child: Stack(
        children: [
          Positioned.fill(child: ColoredBox(color: theme.appColors.hairline)),
          FractionallySizedBox(
            alignment: AlignmentDirectional.centerStart,
            widthFactor: fraction.clamp(0.0, 1.0),
            // See [SessionRule]: a loose height collapses a childless
            // `ColoredBox` to nothing.
            heightFactor: 1,
            child: ColoredBox(color: theme.colorScheme.onSurface),
          ),
        ],
      ),
    );
  }
}
