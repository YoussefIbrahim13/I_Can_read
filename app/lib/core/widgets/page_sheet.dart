/// The page furniture Redesign v2 introduced.
///
/// v2's central move was to stop drawing Today as a *card* and start drawing it
/// as a *page*: a sheet with a shadowed gutter down its spine, a running head
/// across the top, a folio line at the foot, and a brass ribbon falling from
/// the top edge. None of it is decoration for its own sake — every piece is
/// borrowed from a physical book, and together they say "you are reading" in a
/// way a rounded rectangle with a border never did.
library;

import 'package:flutter/material.dart';

import '../theme/app_tokens.dart';

/// A bound page: paper ground, hairline edge, and a gutter shadow falling from
/// the inline-start edge.
///
/// The gutter is the whole trick. A card is lit evenly and therefore reads as a
/// floating tile; a page is bound on one side, so the paper darkens as it turns
/// into the spine. 16px of gradient is enough to suggest it without the sheet
/// looking dirty.
class PageSheet extends StatelessWidget {
  const PageSheet({
    required this.child,
    this.padding = const EdgeInsetsDirectional.fromSTEB(26, 14, 18, 16),
    super.key,
  });

  final Widget child;

  /// Asymmetric by default: the inline-start inset clears the gutter shadow, so
  /// text starts on lit paper rather than in the spine.
  final EdgeInsetsGeometry padding;

  /// The width of the gutter gradient, and the inline-start padding that has to
  /// clear it.
  static const gutterWidth = 16.0;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.appColors;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        border: Border.all(color: colors.hairline),
        borderRadius: BorderRadius.circular(AppSpacing.radius),
      ),
      // Clips the gutter gradient to the rounded corners.
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppSpacing.radius),
        child: Stack(
          children: [
            PositionedDirectional(
              start: 0,
              top: 0,
              bottom: 0,
              width: gutterWidth,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: AlignmentDirectional.centerStart,
                    end: AlignmentDirectional.centerEnd,
                    colors: [colors.gutter, colors.gutter.withValues(alpha: 0)],
                  ),
                ),
              ),
            ),
            Padding(padding: padding, child: child),
          ],
        ),
      ),
    );
  }
}

/// The brass ribbon that falls from the top edge of the screen.
///
/// The oldest signal in reading: a ribbon marks the place you are at. It hangs
/// from above the content rather than starting inside it, which is why callers
/// put it in a [Stack] with `clipBehavior: Clip.none` and let it overlap the
/// header.
class PageRibbon extends StatelessWidget {
  const PageRibbon({this.height = 118, this.width = 11, super.key});

  final double height;
  final double width;

  /// How far the ribbon sits from the inline-end edge of the screen.
  static const inset = 38.0;

  @override
  Widget build(BuildContext context) {
    return ClipPath(
      clipper: const _RibbonClipper(),
      child: SizedBox(
        width: width,
        height: height,
        child: ColoredBox(color: Theme.of(context).appColors.accentStroke),
      ),
    );
  }
}

/// The swallowtail foot: bottom corners at full drop, the middle notched up.
class _RibbonClipper extends CustomClipper<Path> {
  const _RibbonClipper();

  /// Where the notch bites to, as a fraction of the ribbon's height.
  static const _notch = 0.78;

  @override
  Path getClip(Size size) => Path()
    ..lineTo(size.width, 0)
    ..lineTo(size.width, size.height)
    ..lineTo(size.width / 2, size.height * _notch)
    ..lineTo(0, size.height)
    ..close();

  @override
  bool shouldReclip(_RibbonClipper oldClipper) => false;
}

/// The line of small type across the top of a page: the book you are in on the
/// inline-start side, the scope of the page on the other.
///
/// Set in the gold text colour rather than the stroke gold, because at 9.5px a
/// stroke-weight gold on paper falls under 4.5:1.
class RunningHead extends StatelessWidget {
  const RunningHead({required this.title, this.scope, super.key});

  /// The book, and its author when there is one. Never case-folded — it is a
  /// title, and "THE MUQADDIMAH" is a different thing from a running head.
  final String title;

  /// What the page covers: "this session". Follows `Kicker`'s rule — capitals
  /// in English, left alone in Arabic, which has no capital height to use.
  final String? scope;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isArabic = Localizations.localeOf(context).languageCode == 'ar';
    final style = theme.textTheme.labelSmall?.copyWith(
      fontSize: 9.5,
      letterSpacing: 1.3,
    );

    return Row(
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        Expanded(
          child: Text(
            title,
            style: style?.copyWith(color: theme.colorScheme.primary),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        if (scope case final scope?) ...[
          const SizedBox(width: AppSpacing.x2),
          Text(
            isArabic ? scope : scope.toUpperCase(),
            style: style?.copyWith(color: theme.appColors.muted),
          ),
        ],
      ],
    );
  }
}
