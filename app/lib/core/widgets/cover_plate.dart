import 'package:flutter/material.dart';

import '../theme/app_tokens.dart';

/// The stand-in for a book cover: a hairline rectangle filled with a 45°
/// hatch.
///
/// PDFs rarely carry usable cover art and the app never fetches any, so this
/// is the permanent treatment rather than a loading placeholder. The hatch
/// keeps it reading as "a book-shaped thing" instead of as a broken image.
class CoverPlate extends StatelessWidget {
  const CoverPlate({this.width = 46, this.height = 64, super.key});

  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.appColors;

    return SizedBox(
      width: width,
      height: height,
      child: CustomPaint(
        painter: _HatchPainter(
          line: colors.hairline,
          background: theme.colorScheme.surfaceContainerHigh,
        ),
      ),
    );
  }
}

class _HatchPainter extends CustomPainter {
  const _HatchPainter({required this.line, required this.background});

  final Color line;
  final Color background;

  static const _spacing = 6.0;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawRect(rect, Paint()..color = background);

    final stroke = Paint()
      ..color = line
      ..strokeWidth = 1;

    canvas.save();
    canvas.clipRect(rect);
    // Start far enough to the left that the 45° lines still cover the top-right
    // corner once they have travelled the full height.
    for (var x = -size.height; x < size.width; x += _spacing) {
      canvas.drawLine(
        Offset(x, 0),
        Offset(x + size.height, size.height),
        stroke,
      );
    }
    canvas.restore();

    canvas.drawRect(
      rect.deflate(0.5),
      Paint()
        ..color = line
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
  }

  @override
  bool shouldRepaint(_HatchPainter oldDelegate) =>
      oldDelegate.line != line || oldDelegate.background != background;
}
