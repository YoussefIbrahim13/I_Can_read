/// How fast the reader actually reads, and what that says about a portion.
///
/// Built only from sittings the app measured. A log row written before the
/// clock existed carries a zero duration, and counting its pages against no
/// time at all would halve every estimate the app makes — so those rows are
/// left out of both sides of the ratio, upstream in the query.
///
/// No Flutter, no I/O: this is arithmetic over two totals.
library;

/// The reader's measured pace, and the sample it rests on.
class ReadingPace {
  const ReadingPace({required this.pages, required this.time});

  /// Nothing measured yet.
  static const unknown = ReadingPace(pages: 0, time: Duration.zero);

  /// Pages read during measured sittings.
  final int pages;

  /// Time those sittings took.
  final Duration time;

  /// Pages the app wants to have seen before it will predict anything.
  ///
  /// A single sitting is a bad witness: a reader who opened the app, read one
  /// page and went to make tea would be told their portion takes four hours.
  /// Ten pages is roughly one portion — enough that one distracted page is
  /// diluted rather than definitive, and few enough that a new reader gets a
  /// number on their first or second day.
  static const minimumPages = 10;

  /// Whether there is enough measured reading to say anything.
  bool get isKnown => pages >= minimumPages && time > Duration.zero;

  /// Seconds one page takes, or null while the pace is unknown.
  Duration? get perPage => isKnown ? _spread(1) : null;

  /// How long [pages] pages should take, or null while the pace is unknown.
  ///
  /// Zero or fewer pages is [Duration.zero] rather than null: a finished
  /// portion has nothing left to take, which is an answer, not an absence.
  Duration? estimateFor(int pages) {
    if (!isKnown) return null;
    if (pages <= 0) return Duration.zero;
    return _spread(pages);
  }

  /// The measured ratio applied to [count] pages.
  ///
  /// Multiplies before dividing so a pace under a second a page — plausible on
  /// a book of plates — does not round away to nothing.
  Duration _spread(int count) =>
      Duration(seconds: (time.inSeconds * count / pages).round());

  @override
  bool operator ==(Object other) =>
      other is ReadingPace && other.pages == pages && other.time == time;

  @override
  int get hashCode => Object.hash(pages, time);

  @override
  String toString() => 'ReadingPace($pages pages in ${time.inSeconds}s)';
}
