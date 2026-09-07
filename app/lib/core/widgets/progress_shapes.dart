/// Three scopes, three shapes — the rule this file exists to enforce.
///
/// A reader must never see the same shape mean two things, so progress is
/// drawn by three separate widgets rather than one parameterised bar:
///
/// * [SessionRule] — *this session*. A gold hairline filling from the inline
///   start.
/// * [TodayBar]    — *today*. One segment per session, so the split is visible.
/// * [BookRule]    — *the whole book*. A thicker ink rule, paired with a
///   percentage in Cormorant figures.
///
/// Keeping them as three named widgets is what stops the scopes being
/// conflated later. Do not add a `style` parameter that lets one become
/// another.
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
            child: ColoredBox(color: colors.accentStroke),
          ),
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
            child: ColoredBox(color: theme.colorScheme.onSurface),
          ),
        ],
      ),
    );
  }
}
