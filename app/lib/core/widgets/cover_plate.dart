import 'package:flutter/material.dart';

import '../theme/app_tokens.dart';

/// The stand-in for a book cover: a hairline rectangle filled with a 45°
/// hatch.
///
/// PDFs rarely carry usable cover art and the app never fetches any, so this
/// is the permanent treatment rather than a loading placeholder. The hatch
/// keeps it reading as "a book-shaped thing" instead of as a broken image.
///
/// Used where the app has a *file* and nothing else yet — importing, relinking.
/// Once a book has a plan behind it, [SpinePlate] says more in the same space.
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

/// A book's text block seen edge-on: lines of type, inked as far as the reader
/// has got and faint beyond it, with a brass rule at the place they stopped.
///
/// Redesign v2 put this where the hatched cover used to be on the shelf. The
/// hatch said "this is a book"; the plate says *which* book — how long it is,
/// how far in you are, and whether you are near the end — in 46×64 points,
/// without a number. A percentage answers the same question, but you have to
/// read a percentage; you only have to glance at this.
///
/// [ribbon] marks the book the day's plan is on, matching the ribbon that
/// hangs over the Today page. One book in the library wears it at a time.
class SpinePlate extends StatelessWidget {
  const SpinePlate({
    required this.fraction,
    this.ribbon = false,
    this.width = 46,
    this.height = 64,
    super.key,
  });

  /// How far through the book the reader is, 0–1. Clamped when drawn.
  final double fraction;

  /// Whether to hang the brass ribbon over the inked lines.
  final bool ribbon;

  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SizedBox(
      width: width,
      height: height,
      child: CustomPaint(
        painter: _SpinePainter(
          fraction: fraction.clamp(0.0, 1.0),
          read: theme.colorScheme.onSurface,
          unread: theme.colorScheme.surfaceContainerHighest,
          mark: theme.appColors.accentStroke,
          ribbon: ribbon,
        ),
      ),
    );
  }
}

class _SpinePainter extends CustomPainter {
  const _SpinePainter({
    required this.fraction,
    required this.read,
    required this.unread,
    required this.mark,
    required this.ribbon,
  });

  final double fraction;
  final Color read;
  final Color unread;
  final Color mark;
  final bool ribbon;

  /// Lines of "type". Enough that one line is a small step — moving the
  /// marker has to look like progress rather than like a jump — and few
  /// enough that each still draws as a rule rather than as a smudge.
  static const _lines = 16;

  /// How much of each line's pitch is inked; the rest is the leading.
  static const _inked = 0.62;

  /// The ribbon, as fractions of the plate.
  static const _ribbonStart = 0.16;
  static const _ribbonWidth = 0.20;
  static const _ribbonLength = 0.55;

  /// Where the ribbon's swallowtail bites to, as a fraction of its length.
  static const _notch = 0.82;

  @override
  void paint(Canvas canvas, Size size) {
    final pitch = size.height / _lines;
    final thickness = pitch * _inked;

    // The line the reader is on. Rounded down so the marker only reaches the
    // last line once the book is actually finished.
    final marker = (fraction * _lines).floor().clamp(0, _lines - 1);

    final paint = Paint();
    for (var i = 0; i < _lines; i++) {
      paint.color = switch (i) {
        _ when i < marker => read,
        _ when i == marker => mark,
        _ => unread,
      };
      canvas.drawRect(
        Rect.fromLTWH(0, i * pitch, size.width, thickness),
        paint,
      );
    }

    if (ribbon) _paintRibbon(canvas, size);
  }

  void _paintRibbon(Canvas canvas, Size size) {
    final start = size.width * _ribbonStart;
    final width = size.width * _ribbonWidth;
    final length = size.height * _ribbonLength;

    final path = Path()
      ..moveTo(start, 0)
      ..lineTo(start + width, 0)
      ..lineTo(start + width, length)
      ..lineTo(start + width / 2, length * _notch)
      ..lineTo(start, length)
      ..close();

    canvas.drawPath(path, Paint()..color = mark);
  }

  @override
  bool shouldRepaint(_SpinePainter old) =>
      old.fraction != fraction ||
      old.read != read ||
      old.unread != unread ||
      old.mark != mark ||
      old.ribbon != ribbon;
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
