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
  const ReadingCalendarGrid({required this.columns, this.cell, super.key});

  final List<List<HeatCell>> columns;

  /// Square size, or null to divide the available width between the columns.
  ///
  /// Redesign v2 wants this grid full-bleed to the text margin on both screens
  /// that carry it, and the column count comes from the data rather than from
  /// the layout — so the default is to measure rather than to guess a number
  /// that only happens to fit the current window.
  final double? cell;

  static const _gap = 3.0;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).appColors;
    if (columns.isEmpty) return const SizedBox.shrink();

    final ink = Theme.of(context).colorScheme.onSurface;

    Color fill(HeatCell day) {
      if (day.isEmpty) return colors.hairline;
      // One ramp, in ink. A day that met the portion is full strength; a day
      // that fell short is the same colour, thinner — so the grid reads as
      // "how much", never as pass and fail.
      //
      // Ink rather than the accent, which is what v2 draws and what the rest
      // of the system already required: gold is a *stroke* colour here, and a
      // hundred gold squares is precisely the accent-as-field the design
      // forbids. Ink also gives the ramp somewhere to go — brass at 30% and
      // brass at 100% are two tints of one warm hue, while ink runs from a
      // hairline to the darkest thing on the page.
      return ink.withValues(alpha: 0.12 + 0.78 * day.intensity);
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final side =
            cell ??
            (constraints.maxWidth - _gap * (columns.length - 1)) /
                columns.length;

        // Always left-to-right, in both locales: the axis is time, and the
        // grid's newest column has to stay under the reader's thumb rather
        // than flip with the script.
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
                        width: side,
                        height: side,
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
      },
    );
  }
}
