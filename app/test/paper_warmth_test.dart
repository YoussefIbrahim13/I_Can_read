import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:i_can_read/core/theme/app_theme.dart';
import 'package:i_can_read/core/theme/app_tokens.dart';

/// Every warmth the slider can actually produce.
Iterable<int> get _stops sync* {
  for (var w = PaperWarmth.min; w <= PaperWarmth.max; w += PaperWarmth.step) {
    yield w;
  }
}

void main() {
  group('the warmth slider', () {
    test('starts where the palette was written, and calls it medium', () {
      // The literal values in `lightColorScheme` describe this setting, which
      // is why tempering is skipped entirely at it.
      expect(PaperWarmth.neutral, 40);
      expect(PaperWarmth.bandOf(PaperWarmth.neutral), PaperWarmthBand.medium);
    });

    test('is the palette untouched at the default', () {
      expect(
        PaperWarmth.temperScheme(lightColorScheme, PaperWarmth.neutral),
        same(lightColorScheme),
      );
      expect(
        PaperWarmth.temper(const Color(0xFFF5EFE3), PaperWarmth.neutral),
        const Color(0xFFF5EFE3),
      );
    });

    test('names every stop, and the names run cool to warm in order', () {
      final bands = [for (final w in _stops) PaperWarmth.bandOf(w)];
      expect(bands.first, PaperWarmthBand.cool);
      expect(bands.last, PaperWarmthBand.warmest);
      // Monotonic: dragging warmer must never hand back a cooler word.
      for (var i = 1; i < bands.length; i++) {
        expect(bands[i].index, greaterThanOrEqualTo(bands[i - 1].index));
      }
    });

    test('holds every paper and ink colour at its own lightness', () {
      // The load-bearing property. Warmth is saturation of the paper hue and
      // nothing else, which is what lets the palette's contrast commitments —
      // brass at 4.5:1 on paper, ink that never reaches black — survive all
      // 21 stops instead of only the default. If this ever fails, the slider
      // has started changing how legible the app is.
      const samples = [
        Color(0xFFF5EFE3), // light paper
        Color(0xFF2E2721), // light ink
        Color(0xFF6B6157), // light second ink
        Color(0xFF1B1815), // dark ground
        Color(0xFFEAE0CB), // dark ink
      ];

      for (final colour in samples) {
        final before = HSLColor.fromColor(colour).lightness;
        for (final warmth in _stops) {
          final after = HSLColor.fromColor(
            PaperWarmth.temper(colour, warmth),
          ).lightness;
          expect(
            after,
            closeTo(before, 0.005),
            reason: '$colour shifted lightness at warmth $warmth',
          );
        }
      }
    });

    test('leaves a colour with no hue alone rather than tinting it', () {
      // The dark gutter shadow is pure black at 40%. Scaling the saturation of
      // something achromatic would invent a hue for it.
      const shadow = Color(0x66000000);
      for (final warmth in _stops) {
        expect(PaperWarmth.temper(shadow, warmth), shadow);
      }
    });

    test('keeps alpha, so hairlines and washes stay at their weight', () {
      const hairline = Color(0x262C2723);
      for (final warmth in _stops) {
        expect(PaperWarmth.temper(hairline, warmth).a, closeTo(0x26 / 255, 0.01));
      }
    });

    test('drains toward grey going down and deepens going up', () {
      const paper = Color(0xFFF5EFE3);
      double sat(int w) => HSLColor.fromColor(PaperWarmth.temper(paper, w)).saturation;

      expect(sat(PaperWarmth.min), lessThan(sat(PaperWarmth.neutral)));
      expect(sat(PaperWarmth.max), greaterThan(sat(PaperWarmth.neutral)));
      // And monotonically, so the track has no flat or reversing stretch.
      for (final w in _stops.skip(1).toList().asMap().entries) {
        final previous = PaperWarmth.min + w.key * PaperWarmth.step;
        expect(sat(w.value), greaterThan(sat(previous) - 0.0001));
      }
    });

    test('refuses a value off the end of the track', () {
      expect(PaperWarmth.clamped(-40), PaperWarmth.min);
      expect(PaperWarmth.clamped(400), PaperWarmth.max);
      expect(PaperWarmth.bandOf(-40), PaperWarmthBand.cool);
      expect(PaperWarmth.bandOf(400), PaperWarmthBand.warmest);
    });

    test('leaves the accents alone, so sage and brass keep their meaning', () {
      final warmed = PaperWarmth.temperScheme(lightColorScheme, PaperWarmth.max);
      // Gold is a stroke colour and green means "done"; neither is paper.
      expect(warmed.outline, lightColorScheme.outline);
      expect(warmed.primary, lightColorScheme.primary);
      expect(warmed.secondary, lightColorScheme.secondary);

      final extras = AppColors.light.tempered(PaperWarmth.max);
      expect(extras.done, AppColors.light.done);
      expect(extras.accentStroke, AppColors.light.accentStroke);
      // The ink printed *on* sage is held back with it: a pair where only one
      // side moves is a pair whose contrast moves with it.
      expect(extras.onDone, AppColors.light.onDone);
      // Paper roles did move.
      expect(extras.readerBackground, isNot(AppColors.light.readerBackground));
    });

    test('builds a distinct theme per stop without rebuilding per frame', () {
      // Cached by value, so dragging the slider does not construct a new
      // ThemeData for every frame at the same stop.
      final first = AppTheme.of(
        brightness: Brightness.light,
        locale: const Locale('ar'),
        warmth: 80,
      );
      final again = AppTheme.of(
        brightness: Brightness.light,
        locale: const Locale('ar'),
        warmth: 80,
      );
      expect(identical(first, again), isTrue);

      final cooler = AppTheme.of(
        brightness: Brightness.light,
        locale: const Locale('ar'),
        warmth: 20,
      );
      expect(cooler.colorScheme.surface, isNot(first.colorScheme.surface));
    });
  });
}
