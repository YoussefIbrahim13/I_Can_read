import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:i_can_read/features/reader/domain/portion_layout.dart';

const _margin = 8.0;

/// Ten uniform pages, so any rectangle can be reasoned about by hand.
List<Size> pages([int count = 10]) => List.filled(count, const Size(100, 200));

PortionLayout layout({int from = 3, int to = 5, int count = 10}) =>
    portionLayout(pages: pages(count), from: from, to: to, margin: _margin);

/// The pages a reader can actually reach: inside the scrollable document.
List<int> visiblePages(PortionLayout result) => [
  for (final (index, rect) in result.rects.indexed)
    if (rect.top < result.size.height) index + 1,
];

void main() {
  test('every page still gets a rectangle', () {
    // The viewer indexes this list by page number; a short list is a crash.
    expect(layout().rects, hasLength(10));
  });

  test('only the portion is inside the document', () {
    expect(visiblePages(layout(from: 3, to: 5)), [3, 4, 5]);
  });

  test('the document is only as tall as the portion', () {
    // Three pages and their margins, not ten.
    expect(layout(from: 3, to: 5).size.height, _margin * 4 + 200 * 3);
  });

  test('the portion is stacked in order, from the top', () {
    final rects = layout(from: 3, to: 5).rects;

    expect(rects[2].top, _margin);
    expect(rects[3].top, _margin * 2 + 200);
    expect(rects[4].top, _margin * 3 + 400);
  });

  test('hidden pages are parked far past the scroll bounds', () {
    final result = layout(from: 3, to: 5);

    for (final page in [1, 2, 6, 7, 8, 9, 10]) {
      expect(
        result.rects[page - 1].top,
        greaterThanOrEqualTo(result.size.height + hiddenPageOffset),
        reason: 'page $page must be out of reach',
      );
    }
  });

  test('hidden pages keep a real size', () {
    // Zero-sized rectangles at the origin break the viewer's current-page
    // arithmetic, which divides by a page height.
    final rects = layout(from: 3, to: 5).rects;

    expect(rects[0].width, 100);
    expect(rects[0].height, 200);
  });

  test('a single-page portion works', () {
    final result = layout(from: 7, to: 7);

    expect(visiblePages(result), [7]);
    expect(result.size.height, _margin * 2 + 200);
  });

  test('the whole book as a portion shows everything', () {
    expect(visiblePages(layout(from: 1, to: 10)), [
      1,
      2,
      3,
      4,
      5,
      6,
      7,
      8,
      9,
      10,
    ]);
  });

  test('a portion running past the end shows what exists', () {
    // A plan can outrun a relinked file that has fewer pages.
    expect(visiblePages(layout(from: 9, to: 15)), [9, 10]);
  });

  test('a portion entirely past the end falls back to the whole book', () {
    // Better a confusing book than a blank screen the reader cannot explain.
    expect(visiblePages(layout(from: 40, to: 45)), [
      1,
      2,
      3,
      4,
      5,
      6,
      7,
      8,
      9,
      10,
    ]);
  });

  test('pages are centred on the widest page in the portion', () {
    final result = portionLayout(
      pages: const [Size(100, 200), Size(300, 200), Size(100, 200)],
      from: 1,
      to: 3,
      margin: _margin,
    );

    expect(result.size.width, 300 + _margin * 2);
    expect(result.rects[0].left, (300 + _margin * 2 - 100) / 2);
    expect(result.rects[1].left, _margin);
  });

  group('currentPortionPage', () {
    late PortionLayout result;

    setUp(() => result = layout(from: 3, to: 5));

    int pageFor(Rect visible) => currentPortionPage(
      visible: visible,
      rects: result.rects,
      from: 3,
      to: 5,
    );

    test('picks the page filling most of the view', () {
      // Page 3 sits at y = 8..208, page 4 at 216..416.
      expect(pageFor(const Rect.fromLTRB(0, 0, 100, 200)), 3);
      expect(pageFor(const Rect.fromLTRB(0, 220, 100, 410)), 4);
    });

    test('never answers with a page outside the portion', () {
      // The whole document, plus everything below it where the rest of the
      // book is parked: the answer still has to be one of 3, 4, 5.
      expect(pageFor(const Rect.fromLTRB(0, 0, 100, 999999)), isIn([3, 4, 5]));
    });

    test(
      'falls back to the first page of the portion when nothing is shown',
      () {
        expect(pageFor(Rect.zero), 3);
      },
    );

    test('straddling two pages picks the more visible one', () {
      // 60px of page 3 against 140px of page 4.
      expect(pageFor(const Rect.fromLTRB(0, 148, 100, 356)), 4);
    });
  });

  test('the document is measured on the portion, not the book', () {
    // A giant page outside the portion must not widen the document.
    final result = portionLayout(
      pages: const [Size(1000, 200), Size(100, 200)],
      from: 2,
      to: 2,
      margin: _margin,
    );

    expect(result.size.width, 100 + _margin * 2);
  });
}
