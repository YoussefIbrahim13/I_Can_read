import 'package:flutter/material.dart';
// `intl` exports its own `TextDirection` (the Bidi one), which would shadow
// `dart:ui`'s and break the `Directionality` below.
import 'package:intl/intl.dart' hide TextDirection;

import '../theme/app_typography.dart';

/// Western digits, always — `intl` formats per locale, so a plain
/// `NumberFormat` under `ar` would render ٢٤٠.
abstract final class AppNumbers {
  static final _decimal = NumberFormat.decimalPattern('en');

  static String format(num value) => _decimal.format(value);

  /// An inclusive page span, e.g. `42–48`. Uses an en dash, not a hyphen.
  static String range(int from, int to) => '${format(from)}–${format(to)}';

  static String percent(double fraction) =>
      '${format((fraction * 100).round())}%';
}

/// A standing number, set in Cormorant with tabular figures and isolated from
/// the surrounding text direction.
///
/// The isolation is the point: without it «ص 42–48» reorders under RTL and the
/// range comes out backwards. Every figure in the app goes through here.
class Figure extends StatelessWidget {
  const Figure(
    this.text, {
    this.style,
    this.size,
    this.height = 1,
    this.weight = FontWeight.w400,
    this.color,
    super.key,
  });

  /// Convenience for the common case of a bare integer.
  Figure.number(
    num value, {
    this.style,
    this.size,
    this.height = 1,
    this.weight = FontWeight.w400,
    this.color,
    super.key,
  }) : text = AppNumbers.format(value);

  final String text;

  /// Takes precedence over [size]/[height]/[weight]; use it to pick a slot
  /// from the text theme, such as `textTheme.displayLarge`.
  final TextStyle? style;
  final double? size;
  final double height;
  final FontWeight weight;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final resolved =
        style ??
        AppTypography.figure(size: size ?? 15, height: height, weight: weight);

    return Directionality(
      textDirection: TextDirection.ltr,
      child: Text(
        text,
        style: color == null ? resolved : resolved.copyWith(color: color),
      ),
    );
  }
}

/// [Figure] as an inline span, for figures embedded in a sentence such as
/// "‎7‎ صفحات فاضلة".
///
/// A [WidgetSpan] wrapping [Figure] is what gives the digits their own
/// direction run inside an RTL paragraph.
InlineSpan figureSpan(
  String text, {
  double size = 15,
  FontWeight weight = FontWeight.w400,
  Color? color,
  PlaceholderAlignment alignment = PlaceholderAlignment.baseline,
}) {
  return WidgetSpan(
    alignment: alignment,
    baseline: TextBaseline.alphabetic,
    child: Figure(text, size: size, weight: weight, color: color),
  );
}
