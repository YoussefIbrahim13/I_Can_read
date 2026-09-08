/// Renders the launcher icons from [AppMarkPainter].
///
/// Run with `flutter test tool/make_icon.dart`, not `dart run`: painting to a
/// PNG needs `dart:ui`, which only exists inside the Flutter engine. It is a
/// test only in the sense that `flutter test` is the shortest way to get an
/// engine on the host.
///
/// The icons are generated rather than drawn once and committed as opaque
/// binaries, so a change to the mark cannot leave the launcher showing last
/// month's logo.
library;

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:i_can_read/core/branding/app_mark.dart';

/// Play Store and the App Store both want 1024.
const _side = 1024.0;

/// The mark's own art already carries padding — the page is 84% of the
/// painter's height — so these are chosen by the fraction of the icon the
/// *page* should end up occupying, not the fraction the painter gets.
const _pageHeightInPainter = 54 / 64;

/// A square icon wants the page at roughly two thirds of its height.
const _fullBleedScale = 0.62 / _pageHeightInPainter;

/// `flutter_launcher_icons` wraps the foreground in an `<inset>` of its own
/// before Android ever sees it. Without allowing for that the mark is scaled
/// down twice and ends up a postage stamp in the middle of the launcher shape.
/// Check `res/mipmap-anydpi-v26/ic_launcher.xml` if this ever looks wrong.
const _adaptiveInset = 0.16;

/// An adaptive icon is cropped to whatever shape the launcher likes; only the
/// inner 66% of the layer is guaranteed to survive, so the page sits well
/// inside that — after the inset above has been taken off.
const _adaptiveScale =
    0.55 / _pageHeightInPainter / (1 - _adaptiveInset * 2);

Future<void> _writePng(String path, ui.Image image) async {
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  final file = File(path);
  await file.parent.create(recursive: true);
  await file.writeAsBytes(data!.buffer.asUint8List());
}

ui.Image _render(void Function(ui.Canvas canvas) draw) {
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  draw(canvas);
  return recorder
      .endRecording()
      .toImageSync(_side.round(), _side.round());
}

void main() {
  // No ruled lines on the icon. They are legible at 1024 and grey mud at 48,
  // and a launcher icon is only ever judged at 48.
  const painter = AppMarkPainter(showRuledLines: false);

  void drawCentred(ui.Canvas canvas, double scale) {
    final markSide = _side * scale;
    final offset = (_side - markSide) / 2;
    canvas.save();
    canvas.translate(offset, offset);
    painter.paint(canvas, ui.Size.square(markSide));
    canvas.restore();
  }

  test('writes the full-bleed icon', () async {
    final image = _render((canvas) {
      canvas.drawRect(
        const ui.Rect.fromLTWH(0, 0, _side, _side),
        ui.Paint()..color = markPaper,
      );
      drawCentred(canvas, _fullBleedScale);
    });

    await _writePng('assets/branding/icon.png', image);
    expect(File('assets/branding/icon.png').existsSync(), isTrue);
  });

  test('writes the adaptive foreground, on transparency', () async {
    final image = _render((canvas) => drawCentred(canvas, _adaptiveScale));

    await _writePng('assets/branding/icon_foreground.png', image);
    expect(File('assets/branding/icon_foreground.png').existsSync(), isTrue);
  });
}
