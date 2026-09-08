/// The app's mark: a page with one band of it set in gold.
///
/// It draws the product rather than the name — the band is the day's portion
/// inside the book, which is the whole idea. Kept as a painter rather than an
/// image so the launcher icon, and anywhere the mark appears in the UI, are the
/// same drawing at every size instead of a set of files that drift apart.
library;

import 'package:flutter/widgets.dart';

/// Ink and gold, fixed. The mark does not follow the theme: a launcher icon
/// has no theme, and a mark that changed colour between the two would stop
/// being one mark.
const markInk = Color(0xFF201F1D);
const markGold = Color(0xFFB68235);
const markPaper = Color(0xFFF8F4F4);

/// The mark, drawn to fill [size] on a square canvas.
///
/// Everything is proportional to the canvas so the same code produces a 1024px
/// launcher icon and a 20px mark in a header. Stroke weight is *not* linear:
/// below about 48px a hairline disappears, so it thickens as the mark shrinks.
class AppMarkPainter extends CustomPainter {
  const AppMarkPainter({this.showRuledLines = true});

  /// The faint lines standing for the rest of the page. Dropped at small
  /// sizes, where they turn into grey mud.
  final bool showRuledLines;

  @override
  void paint(Canvas canvas, Size size) {
    final side = size.shortestSide;
    final unit = side / 64;

    // Thicker relative stroke as the mark gets smaller, so the page outline
    // survives at launcher-badge sizes.
    final strokeUnits = side < 32
        ? 4.5
        : side < 64
        ? 3.2
        : 2.2;
    final stroke = strokeUnits * unit;

    final page = Rect.fromLTWH(13 * unit, 5 * unit, 38 * unit, 54 * unit);
    final radius = Radius.circular(2 * unit);

    if (showRuledLines && side >= 64) {
      final ruled = Paint()
        ..color = markInk.withValues(alpha: .16)
        ..strokeWidth = 2 * unit
        ..strokeCap = StrokeCap.square;
      for (final y in const [14.0, 39.0, 46.0]) {
        canvas.drawLine(
          Offset(20 * unit, y * unit),
          Offset(44 * unit, y * unit),
          ruled,
        );
      }
    }

    // The portion, clipped to the page so it can never overhang the outline —
    // at 1024px a stray half-pixel of gold along the spine is visible.
    canvas.save();
    canvas.clipRRect(RRect.fromRectAndRadius(page, radius));
    canvas.drawRect(
      Rect.fromLTWH(page.left, 23 * unit, page.width, 7.5 * unit),
      Paint()..color = markGold,
    );
    canvas.restore();

    canvas.drawRRect(
      RRect.fromRectAndRadius(page.deflate(stroke / 2), radius),
      Paint()
        ..color = markInk
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke,
    );
  }

  @override
  bool shouldRepaint(AppMarkPainter oldDelegate) =>
      oldDelegate.showRuledLines != showRuledLines;
}

/// The mark as a widget, for use inside the app.
class AppMark extends StatelessWidget {
  const AppMark({this.size = 24, super.key});

  final double size;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size.square(size),
      painter: const AppMarkPainter(),
    );
  }
}
