import 'package:flutter/material.dart';

import '../planning/reading_calendar.dart';
import '../theme/app_tokens.dart';

/// The grid of days, one square each.
///
/// One widget for both calendars in the app — a book's own and the whole
/// library's — because they are the same drawing with a different reference for
/// what a full day is, and two copies would drift apart on the day somebody
/// changes the ramp.
class ReadingCalendarGrid extends StatelessWidget {
  const ReadingCalendarGrid({required this.columns, this.cell = 11, super.key});

  final List<List<HeatCell>> columns;

  /// Square size. The stats screen has the width to go a little larger.
  final double cell;

  static const _gap = 3.0;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).appColors;

    Color fill(HeatCell day) {
      if (day.isEmpty) return colors.hairline;
      // One ramp, gold. A day that met the portion is full strength; a day
      // that fell short is the same colour, thinner — so the grid reads as
      // "how much", never as pass and fail.
      return colors.accentStroke.withValues(alpha: 0.3 + 0.7 * day.intensity);
    }

    // Always left-to-right, in both locales: the axis is time, and the grid's
    // newest column has to stay under the reader's thumb rather than flip with
    // the script.
    return Directionality(
      textDirection: TextDirection.ltr,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.start,
        children: [
          for (final (index, column) in columns.indexed) ...[
            if (index > 0) const SizedBox(width: _gap),
            Column(
              children: [
                for (final (row, day) in column.indexed) ...[
                  if (row > 0) const SizedBox(height: _gap),
                  Container(
                    width: cell,
                    height: cell,
                    decoration: BoxDecoration(
                      color: fill(day),
                      borderRadius: BorderRadius.circular(1),
                    ),
                  ),
                ],
              ],
            ),
          ],
        ],
      ),
    );
  }
}
