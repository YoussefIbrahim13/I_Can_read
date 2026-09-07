import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:i_can_read/features/reader/domain/portion_layout.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path/path.dart' as p;
import 'package:pdfrx/pdfrx.dart';

import 'support/minimal_pdf.dart';

/// Puts the portion layout in front of the real PDF engine.
///
/// `test/portion_layout_test.dart` proves the geometry is right. This proves
/// pdfrx accepts it: that parking the pages outside the portion past the end of
/// the document does not upset the viewer's page detection or its scroll
/// bounds. Neither can be checked on the host VM, which has no PDF engine.
///
/// Run with: `flutter test integration_test/portion_reader_test.dart -d <device>`
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late Directory documents;
  late String path;

  setUp(() async {
    documents = await Directory.systemTemp.createTemp('i_can_read_portion');
    final file = File(p.join(documents.path, 'book.pdf'));
    await file.writeAsBytes(minimalPdf(pageCount: 20));
    path = file.path;
  });

  tearDown(() async {
    if (documents.existsSync()) await documents.delete(recursive: true);
  });

  /// Mounts a viewer restricted to [from]..[to] and returns its controller.
  Future<PdfViewerController> openPortion(
    WidgetTester tester, {
    required int from,
    required int to,
    int? initialPage,
  }) async {
    final controller = PdfViewerController();
    var ready = false;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PdfViewer.file(
            path,
            controller: controller,
            initialPageNumber: initialPage ?? from,
            params: PdfViewerParams(
              onViewerReady: (_, _) => ready = true,
              calculateCurrentPageNumber: (visible, rects, _) =>
                  currentPortionPage(
                    visible: visible,
                    rects: rects,
                    from: from,
                    to: to,
                  ),
              layoutPages: (pages, params) {
                final layout = portionLayout(
                  pages: [for (final page in pages) Size(page.width, page.height)],
                  from: from,
                  to: to,
                  margin: params.margin,
                );
                return PdfPageLayout(
                  pageLayouts: layout.rects,
                  documentSize: layout.size,
                );
              },
            ),
          ),
        ),
      ),
    );

    // The engine opens the file off the platform thread; settling alone is not
    // enough to guarantee it has finished.
    for (var i = 0; i < 40 && !ready; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(ready, isTrue, reason: 'the viewer never became ready');
    return controller;
  }

  testWidgets('the engine accepts a layout that hides most of the book', (
    tester,
  ) async {
    final controller = await openPortion(tester, from: 5, to: 8);

    // The document still has every page; only four are reachable.
    expect(controller.pageCount, 20);
    expect(controller.pageNumber, inInclusiveRange(5, 8));
  });

  testWidgets('it opens on the page it was told to, inside the portion', (
    tester,
  ) async {
    final controller = await openPortion(
      tester,
      from: 5,
      to: 8,
      initialPage: 7,
    );

    expect(controller.pageNumber, 7);
  });

  testWidgets('scrolling to the end cannot reach the hidden pages', (
    tester,
  ) async {
    final controller = await openPortion(tester, from: 5, to: 8);

    // A hard fling, twice: if the scroll bounds came from anything but the
    // portion's own document size, this would land among the parked pages.
    for (var i = 0; i < 2; i++) {
      await tester.fling(find.byType(PdfViewer), const Offset(0, -4000), 8000);
      await tester.pumpAndSettle(const Duration(milliseconds: 100));
    }

    // The decisive assertion. The reported page number is computed by our own
    // callback, so it would say "inside the portion" even if the view had
    // scrolled somewhere else entirely; where the viewport actually sits
    // cannot be talked round.
    expect(controller.visibleRect.bottom, lessThan(hiddenPageOffset));
    expect(controller.pageNumber, inInclusiveRange(5, 8));
  });

  testWidgets('widening the portion and invalidating really relayouts', (
    tester,
  ) async {
    // What "Keep reading" rests on. `layoutPages` is only consulted on a
    // relayout, so if `invalidate()` did not force one the button would widen
    // the range in Dart and change nothing on screen — silently.
    final range = ValueNotifier<(int, int)>((5, 8));
    final controller = PdfViewerController();
    var ready = false;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ValueListenableBuilder<(int, int)>(
            valueListenable: range,
            builder: (context, value, _) {
              final (from, to) = value;
              return PdfViewer.file(
                path,
                controller: controller,
                initialPageNumber: 5,
                params: PdfViewerParams(
                  onViewerReady: (_, _) => ready = true,
                  calculateCurrentPageNumber: (visible, rects, _) =>
                      currentPortionPage(
                        visible: visible,
                        rects: rects,
                        from: from,
                        to: to,
                      ),
                  layoutPages: (pages, params) {
                    final layout = portionLayout(
                      pages: [
                        for (final page in pages) Size(page.width, page.height),
                      ],
                      from: from,
                      to: to,
                      margin: params.margin,
                    );
                    return PdfPageLayout(
                      pageLayouts: layout.rects,
                      documentSize: layout.size,
                    );
                  },
                ),
              );
            },
          ),
        ),
      ),
    );
    for (var i = 0; i < 40 && !ready; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(ready, isTrue);

    // Locked: the bottom of the four-page portion is as far as it goes.
    await tester.fling(find.byType(PdfViewer), const Offset(0, -4000), 8000);
    await tester.pumpAndSettle(const Duration(milliseconds: 100));
    expect(controller.pageNumber, lessThanOrEqualTo(8));

    range.value = (5, 20);
    await tester.pump();
    controller.invalidate();
    await tester.pumpAndSettle(const Duration(milliseconds: 100));

    for (var i = 0; i < 3; i++) {
      await tester.fling(find.byType(PdfViewer), const Offset(0, -4000), 8000);
      await tester.pumpAndSettle(const Duration(milliseconds: 100));
    }
    expect(
      controller.pageNumber,
      greaterThan(8),
      reason: 'the widened range never reached the layout',
    );

    range.dispose();
  });

  testWidgets('a one-page portion is a one-page document', (tester) async {
    final controller = await openPortion(tester, from: 12, to: 12);

    expect(controller.pageNumber, 12);

    await tester.fling(find.byType(PdfViewer), const Offset(0, -4000), 8000);
    await tester.pumpAndSettle(const Duration(milliseconds: 100));

    expect(controller.pageNumber, 12);
  });
}
