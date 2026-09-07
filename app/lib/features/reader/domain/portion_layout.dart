/// Where each page of a PDF sits when the reader may only see one portion.
///
/// Pure geometry, so the awkward part — hiding pages the viewer still insists
/// on being given a rectangle for — can be tested without a PDF engine.
library;

import 'dart:math';
import 'dart:ui';

/// A laid-out document: one rectangle per page, and the scrollable size.
typedef PortionLayout = ({List<Rect> rects, Size size});

/// How far past the document the hidden pages are parked.
///
/// They have to go somewhere — the viewer indexes rectangles by page number,
/// so there is no way to simply leave them out. Parking them a long way below
/// the document keeps them clear of the scroll bounds even when the reader has
/// zoomed all the way out. Zero-sized rectangles at the origin were the other
/// option, and they break the viewer's current-page arithmetic, which divides
/// by a page's height.
const hiddenPageOffset = 100000.0;

/// Stacks pages [from]..[to] (1-based, inclusive) into a document of their own.
///
/// The reader asked for their portion, not the book. Showing everything and
/// merely opening on the right page would turn a bounded, finishable task back
/// into an eight-hundred-page object, which is the thing this app exists to fix.
///
/// If the range selects no page at all — a plan whose pages run past the end of
/// a relinked file, say — every page is laid out instead. A reader looking at a
/// blank screen has no way to understand what went wrong.
PortionLayout portionLayout({
  required List<Size> pages,
  required int from,
  required int to,
  required double margin,
}) {
  bool visible(int index) {
    final number = index + 1;
    return number >= from && number <= to;
  }

  final anyVisible = [for (var i = 0; i < pages.length; i++) i].any(visible);
  bool shown(int index) => anyVisible ? visible(index) : true;

  var width = 0.0;
  for (var i = 0; i < pages.length; i++) {
    if (shown(i)) width = max(width, pages[i].width);
  }
  final documentWidth = width + margin * 2;

  final rects = List<Rect?>.filled(pages.length, null);
  var y = margin;
  for (var i = 0; i < pages.length; i++) {
    if (!shown(i)) continue;
    rects[i] = Rect.fromLTWH(
      (documentWidth - pages[i].width) / 2,
      y,
      pages[i].width,
      pages[i].height,
    );
    y += pages[i].height + margin;
  }

  var parked = y + hiddenPageOffset;
  for (var i = 0; i < pages.length; i++) {
    if (rects[i] != null) continue;
    rects[i] = Rect.fromLTWH(0, parked, pages[i].width, pages[i].height);
    parked += pages[i].height + margin;
  }

  return (
    rects: [for (final rect in rects) rect!],
    size: Size(documentWidth, y),
  );
}

/// Which page the reader is actually looking at, chosen from the portion.
///
/// The viewer's own answer cannot be used. Once a layout stops looking uniform
/// — and parking most of the book a long way below it is about as non-uniform
/// as a layout gets — it switches to guessing the page from the scroll
/// percentage across the whole document, and reports page 20 of 20 while page
/// 8 is the one on screen.
///
/// Overlap is measured vertically because the portion is a vertical stack.
int currentPortionPage({
  required Rect visible,
  required List<Rect> rects,
  required int from,
  required int to,
}) {
  var best = from.clamp(1, rects.isEmpty ? 1 : rects.length);
  var mostVisible = 0.0;

  for (var page = from; page <= to && page <= rects.length; page++) {
    if (page < 1) continue;
    final overlap = rects[page - 1].intersect(visible);
    if (overlap.height > mostVisible) {
      mostVisible = overlap.height;
      best = page;
    }
  }
  return best;
}
