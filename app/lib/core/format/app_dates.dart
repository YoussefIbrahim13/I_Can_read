import 'package:flutter/widgets.dart';
import 'package:intl/intl.dart';

import '../widgets/figure.dart';

/// Dates as the design writes them: a western-digit day, a localised month.
///
/// Assembled from parts rather than from one `DateFormat` pattern, because a
/// pattern under `ar` renders ٣ نوفمبر ٢٠٢٦ — and every figure in this app is
/// western and tabular, so a lone Arabic-Indic numeral in a date reads as a
/// different app. The day-then-month order is fixed across both locales for the
/// same reason: it is the one the design draws.
abstract final class AppDates {
  /// "3 November" / "3 نوفمبر".
  static String dayAndMonth(DateTime date, Locale locale) {
    final month = DateFormat.MMMM(locale.toLanguageTag()).format(date);
    return '${AppNumbers.format(date.day)} $month';
  }

  /// "3 November 2026" / "3 نوفمبر 2026" — for a date far enough away that the
  /// year is not obvious.
  static String full(DateTime date, Locale locale) =>
      '${dayAndMonth(date, locale)} ${AppNumbers.format(date.year)}';

  /// "Wednesday · 3 November" / "الأربعاء · 3 نوفمبر".
  static String weekdayAndDate(DateTime date, Locale locale) {
    final weekday = DateFormat.EEEE(locale.toLanguageTag()).format(date);
    return '$weekday · ${dayAndMonth(date, locale)}';
  }
}
