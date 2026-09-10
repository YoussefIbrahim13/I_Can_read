/// The record: every day this book was read, and what that day cost.
///
/// A day, not a sitting. The reader thinks in أوراد — one portion a day — so a
/// morning and an evening spent in the same book are one line here, with the
/// sittings counted rather than listed. The log keeps the finer grain if it is
/// ever wanted; this is the shape the reader asked the question in.
///
/// Nothing here compares a day against the quota. A short day is not a failure
/// to report — the plan already answered that by moving the finish date — so
/// the list says what was read and stops.
library;

import '../../../core/planning/reading_pace.dart';

/// One day's reading, as it actually happened.
class ReadPortion {
  const ReadPortion({
    required this.day,
    required this.fromPage,
    required this.toPage,
    required this.pages,
    required this.time,
    required this.sittings,
  });

  /// The reading day, which rolls over at 04:00 rather than midnight.
  final DateTime day;

  /// The lowest and highest pages touched that day, inclusive.
  ///
  /// A range, not a stretch: a reader who went back over an earlier chapter
  /// before carrying on has a range wider than [pages], and saying so is more
  /// honest than pretending the day was contiguous.
  final int fromPage;
  final int toPage;

  /// Pages credited that day, summed across sittings.
  final int pages;

  /// Measured time. Zero for a day read before the app kept a clock.
  final Duration time;

  /// How many separate sittings the day took.
  final int sittings;

  /// Whether this day has a time worth printing.
  bool get isTimed => time > Duration.zero;

  /// True when the pages read are more than the range implies is possible —
  /// which means a page was read twice.
  bool get hasRereading => pages > toPage - fromPage + 1;

  @override
  String toString() =>
      'ReadPortion($day, $fromPage-$toPage, $pages pages, '
      '${time.inSeconds}s, $sittings sittings)';
}

/// The whole record for one book.
class ReadingRecord {
  const ReadingRecord(this.portions);

  /// Newest day first: the reader opens this to see what they just did.
  final List<ReadPortion> portions;

  bool get isEmpty => portions.isEmpty;

  /// Days that have a line here at all. Days with no reading are absent
  /// rather than listed as zero — the calendar is where gaps are visible.
  int get daysRead => portions.length;

  int get totalPages => portions.fold(0, (sum, portion) => sum + portion.pages);

  /// Time across every day that was measured.
  Duration get totalTime =>
      portions.fold(Duration.zero, (sum, portion) => sum + portion.time);

  /// True once any day carries a time, so the screen knows whether to have a
  /// time column at all.
  bool get hasAnyTime => portions.any((portion) => portion.isTimed);

  /// The pace this record implies, over the days that were measured.
  ///
  /// Built the same way the app builds it everywhere: untimed days are left
  /// out of both totals, not just out of the time.
  ReadingPace get pace {
    var pages = 0;
    var time = Duration.zero;
    for (final portion in portions) {
      if (!portion.isTimed) continue;
      pages += portion.pages;
      time += portion.time;
    }
    return ReadingPace(pages: pages, time: time);
  }
}
