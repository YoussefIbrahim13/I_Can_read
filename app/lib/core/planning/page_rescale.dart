/// Moving page numbers from one copy of a book to another.
///
/// A reader who relinks a different scan or edition keeps the same plan, but
/// the pages underneath it moved: page 120 of a 300-page copy is not page 120
/// of a 450-page one. This maps a physical page to the same *position* in the
/// new file, which is the closest thing to "where I was" that page counts alone
/// can tell us.
///
/// Deliberately pure and dependency-free, like the rest of the plan arithmetic,
/// because it silently rewrites a reader's progress and has to be tested rather
/// than trusted.
library;

/// Where [page] lands in a copy with [toCount] pages, given it was recorded
/// against a copy with [fromCount].
///
/// Zero passes through: it is the "nothing read yet" sentinel on a plan, not a
/// page. Everything else is clamped into `1..toCount`, so a shorter copy cannot
/// leave a plan pointing past its own last page.
int rescalePage(int page, {required int fromCount, required int toCount}) {
  if (page <= 0) return 0;
  if (toCount <= 0) return 0;
  // Nothing to scale by, so the only safe move is to clamp.
  if (fromCount <= 0) return page > toCount ? toCount : page;

  // Rounded rather than truncated: truncation drags every page backwards, and
  // over a long book that reads as losing progress on every relink.
  final scaled = (page * toCount / fromCount).round();
  if (scaled < 1) return 1;
  if (scaled > toCount) return toCount;
  return scaled;
}

/// [page] made safe for a copy with [toCount] pages, without moving it.
///
/// The other half of the choice the reader is offered: their page numbers stay
/// exactly as they are, and only a number that no longer exists in the file is
/// pulled back to the last page that does.
int clampPage(int page, {required int toCount}) {
  if (page <= 0) return 0;
  if (toCount <= 0) return 0;
  return page > toCount ? toCount : page;
}
