import 'package:flutter_test/flutter_test.dart';
import 'package:i_can_read/core/planning/page_rescale.dart';

void main() {
  group('rescalePage', () {
    test('keeps the same position in a longer copy', () {
      expect(rescalePage(150, fromCount: 300, toCount: 600), 300);
      expect(rescalePage(100, fromCount: 300, toCount: 450), 150);
    });

    test('keeps the same position in a shorter copy', () {
      expect(rescalePage(300, fromCount: 600, toCount: 300), 150);
    });

    test('the last page of one copy is the last page of the other', () {
      expect(rescalePage(300, fromCount: 300, toCount: 412), 412);
      expect(rescalePage(412, fromCount: 412, toCount: 300), 300);
    });

    test('rounds rather than truncating', () {
      // 7/10 of a 15-page copy is 10.5 — truncating would report a page less
      // read on every relink.
      expect(rescalePage(7, fromCount: 10, toCount: 15), 11);
    });

    test('an early page never rounds away to nothing', () {
      expect(rescalePage(1, fromCount: 1000, toCount: 10), 1);
    });

    test('zero stays zero, because it means "nothing read yet"', () {
      expect(rescalePage(0, fromCount: 300, toCount: 450), 0);
    });

    test('never lands outside the new copy', () {
      expect(rescalePage(9999, fromCount: 300, toCount: 450), 450);
    });

    test('survives a copy with no pages, and an unknown original', () {
      expect(rescalePage(50, fromCount: 300, toCount: 0), 0);
      expect(rescalePage(50, fromCount: 0, toCount: 300), 50);
      expect(rescalePage(500, fromCount: 0, toCount: 300), 300);
    });
  });

  group('clampPage', () {
    test('leaves a page that still exists exactly where it was', () {
      expect(clampPage(120, toCount: 300), 120);
      expect(clampPage(300, toCount: 300), 300);
    });

    test('pulls a page past the end back to the last one', () {
      expect(clampPage(400, toCount: 300), 300);
    });

    test('zero stays zero', () => expect(clampPage(0, toCount: 300), 0));
  });
}
