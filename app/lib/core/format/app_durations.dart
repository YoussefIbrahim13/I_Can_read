import '../../l10n/app_localizations.dart';

/// Spans of time as the design says them: one unit, or two, never three.
///
/// Assembled from localised parts rather than from a pattern, for the same
/// reason `AppDates` is — and because Arabic counts in duals and needs
/// «ساعتين», not «2 ساعة». Seconds only ever appear alone, under a minute:
/// «1 hour 12 minutes 40 seconds» is a stopwatch reading, and nothing here is
/// precise enough to earn that third unit.
abstract final class AppDurations {
  /// "45 seconds" · "18 minutes" · "2 hours 5 minutes".
  ///
  /// Rounds to the nearest minute above an hour, so a total does not tick a
  /// digit while the reader is looking at it.
  static String compact(Duration span, AppLocalizations l10n) {
    final seconds = span.inSeconds;
    if (seconds < 60) return l10n.durationSeconds(seconds);

    final minutes = span.inMinutes;
    if (minutes < 60) return l10n.durationMinutes(minutes);

    final hours = minutes ~/ 60;
    final rest = minutes % 60;
    if (rest == 0) return l10n.durationHours(hours);
    return l10n.durationHoursAndMinutes(
      l10n.durationHours(hours),
      l10n.durationMinutes(rest),
    );
  }

  /// The same, but never smaller than a minute.
  ///
  /// For estimates. "about 40 seconds" invites the reader to time the app, and
  /// a portion the app thinks takes under a minute is a portion whose estimate
  /// is wrong anyway — rounding up is the honest way to be vague.
  static String estimate(Duration span, AppLocalizations l10n) =>
      compact(span < const Duration(minutes: 1) ? _oneMinute : span, l10n);

  static const _oneMinute = Duration(minutes: 1);
}
