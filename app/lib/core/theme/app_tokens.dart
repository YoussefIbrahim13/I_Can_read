import 'package:flutter/material.dart';

/// Literal values from the design system. Nothing here is derived — the
/// palette is hand-set rather than seeded, because a tonal ramp from one hue
/// is exactly what made the app read as generic Material.
abstract final class AppSpacing {
  /// 1.15× density scale. Screen gutter is [x4], card padding [x3] + 2.
  static const x1 = 5.0;
  static const x2 = 9.0;
  static const x3 = 14.0;
  static const x4 = 18.0;
  static const x6 = 28.0;
  static const x8 = 37.0;

  /// The horizontal inset every screen's content starts at.
  static const gutter = 20.0;

  /// Cards, buttons, fields, steppers — one radius, everywhere.
  static const radius = 4.0;

  /// The "page" panel sits a hair tighter than everything else.
  static const pageRadius = 3.0;

  /// Nothing taps smaller than this, even when the visible box is 36.
  static const minTapTarget = 44.0;
}

/// Roles Material's [ColorScheme] has no slot for.
///
/// [muted] is a third ink between `onSurfaceVariant` and the hairline; the
/// design leans on it for every "ص 42–48" style caption, so it cannot be
/// folded into an existing role.
///
/// [gutter], [stripe] and [press] exist because Redesign v2 stopped drawing
/// screens as cards and started drawing them as *pages*: a page has a shadowed
/// gutter down its spine, printed rules show through a paper stripe, and a row
/// that answers to a tap has to show it.
@immutable
class AppColors extends ThemeExtension<AppColors> {
  const AppColors({
    required this.muted,
    required this.done,
    required this.doneWash,
    required this.onDone,
    required this.hairline,
    required this.readerBackground,
    required this.accentStroke,
    required this.gutter,
    required this.stripe,
    required this.press,
  });

  /// Third-level text: captions, times, "of 8" counters.
  final Color muted;

  /// Completion, and nothing else. Never "good", never "on track".
  final Color done;

  /// [done] at wash strength, behind the "portion finished" flash only.
  final Color doneWash;

  /// Text and glyphs printed *on* a [done] fill.
  final Color onDone;

  /// Every 1px rule in the app.
  final Color hairline;

  /// The reader's own ground, a shade past `surface` in both modes.
  final Color readerBackground;

  /// Gold at stroke weight. Same value as `ColorScheme.outline`, named for the
  /// call sites that mean "the accent rule" rather than "a border".
  final Color accentStroke;

  /// The shadow that falls from a page's inner edge. Drawn as a gradient from
  /// this colour to transparent across the leading 16px, which is what makes
  /// the Today sheet read as a bound page rather than a floating card.
  final Color gutter;

  /// Laid over paper as repeating 1px rules, so a filled span reads as printed
  /// lines rather than as a solid slab of colour.
  final Color stripe;

  /// The pressed state of a tappable row. v2's rule is that almost everything
  /// answers to a tap, so rows need a press wash the ripple alone doesn't give.
  final Color press;

  /// The palette at [PaperWarmth.neutral]. Every other setting is this,
  /// tempered — see [PaperWarmth].
  static const light = AppColors(
    muted: Color(0xFF948A7D),
    done: Color(0xFF5E7F63),
    doneWash: Color(0x1A5E7F63),
    onDone: Color(0xFFFBF7ED),
    hairline: Color(0x262C2723),
    readerBackground: Color(0xFFFAF6EC),
    accentStroke: Color(0xFFB0803C),
    gutter: Color(0x212C2723),
    stripe: Color(0xB3FAF6EC),
    press: Color(0x0D2C2723),
  );

  static const dark = AppColors(
    muted: Color(0xFF7E7365),
    done: Color(0xFF7FA083),
    doneWash: Color(0x247FA083),
    onDone: Color(0xFF12140F),
    hairline: Color(0x26E8DFCE),
    readerBackground: Color(0xFF1F1B16),
    accentStroke: Color(0xFFD6A45F),
    gutter: Color(0x66000000),
    stripe: Color(0xB81B1815),
    press: Color(0x0FE8DFCE),
  );

  @override
  AppColors copyWith({
    Color? muted,
    Color? done,
    Color? doneWash,
    Color? onDone,
    Color? hairline,
    Color? readerBackground,
    Color? accentStroke,
    Color? gutter,
    Color? stripe,
    Color? press,
  }) {
    return AppColors(
      muted: muted ?? this.muted,
      done: done ?? this.done,
      doneWash: doneWash ?? this.doneWash,
      onDone: onDone ?? this.onDone,
      hairline: hairline ?? this.hairline,
      readerBackground: readerBackground ?? this.readerBackground,
      accentStroke: accentStroke ?? this.accentStroke,
      gutter: gutter ?? this.gutter,
      stripe: stripe ?? this.stripe,
      press: press ?? this.press,
    );
  }

  @override
  AppColors lerp(AppColors? other, double t) {
    if (other == null) return this;
    return AppColors(
      muted: Color.lerp(muted, other.muted, t)!,
      done: Color.lerp(done, other.done, t)!,
      doneWash: Color.lerp(doneWash, other.doneWash, t)!,
      onDone: Color.lerp(onDone, other.onDone, t)!,
      hairline: Color.lerp(hairline, other.hairline, t)!,
      readerBackground: Color.lerp(
        readerBackground,
        other.readerBackground,
        t,
      )!,
      accentStroke: Color.lerp(accentStroke, other.accentStroke, t)!,
      gutter: Color.lerp(gutter, other.gutter, t)!,
      stripe: Color.lerp(stripe, other.stripe, t)!,
      press: Color.lerp(press, other.press, t)!,
    );
  }

  /// This palette with every paper and ink role tempered to [warmth].
  ///
  /// The sage family and [accentStroke] are left alone: they are hue statements
  /// rather than paper, and running sage through a warmth boost turns it olive.
  /// [onDone] is held back with them rather than warmed with the paper it
  /// resembles — it is the ink printed *on* [done], and a pair where only one
  /// side moves is a pair whose contrast moves with it.
  AppColors tempered(int warmth) {
    if (warmth == PaperWarmth.neutral) return this;
    Color t(Color c) => PaperWarmth.temper(c, warmth);
    return copyWith(
      muted: t(muted),
      hairline: t(hairline),
      readerBackground: t(readerBackground),
      gutter: t(gutter),
      stripe: t(stripe),
      press: t(press),
    );
  }
}

/// `Theme.of(context).appColors` reads better at the call site than the
/// generic `extension<AppColors>()` lookup, and fails loudly if the extension
/// was never registered.
extension AppColorsAccess on ThemeData {
  AppColors get appColors => extension<AppColors>()!;
}

/// The paper-warmth slider, and the one rule that makes it safe.
///
/// Warmth is the **saturation of the paper hue**, never a lightness change.
/// Every paper and ink colour keeps its HSL lightness exactly as the palette
/// set it, so the contrast ratios the design committed to — brass at 4.5:1 on
/// paper, ink that never reaches black — hold at every setting of the slider
/// rather than only at the default.
///
/// That is also why this is a blend and not a swap of two themes: at [min] the
/// cream drains back toward the neutral grey v2 moved off, at [neutral] the app
/// is the palette exactly as specified, and at [max] the same paper deepens.
abstract final class PaperWarmth {
  static const min = 0;
  static const max = 100;

  /// The setting the palette's literal values already describe. The slider
  /// starts here, and at this value tempering is skipped entirely.
  static const neutral = 40;

  /// The slider moves in fives. The control carries a word rather than a
  /// number, so finer steps would be a precision the label cannot express.
  static const step = 5;

  /// Saturation multipliers at the two ends of the track.
  static const _drained = 0.18;
  static const _deepened = 1.75;

  /// Saturation below which a colour has no meaningful hue to scale — pure
  /// black shadow scrims, mostly, which must not acquire a tint.
  static const _achromatic = 0.01;

  static int clamped(int warmth) => warmth.clamp(min, max);

  /// The word under the slider's thumb. Five bands, because the reader is
  /// choosing a feel and "62" is not one.
  static PaperWarmthBand bandOf(int warmth) => switch (clamped(warmth)) {
    < 20 => PaperWarmthBand.cool,
    < 40 => PaperWarmthBand.light,
    < 60 => PaperWarmthBand.medium,
    < 80 => PaperWarmthBand.warm,
    _ => PaperWarmthBand.warmest,
  };

  /// [c] with its saturation scaled for [warmth], lightness and alpha intact.
  static Color temper(Color c, int warmth) {
    final scale = _scale(clamped(warmth));
    if (scale == 1) return c;

    final hsl = HSLColor.fromColor(c);
    if (hsl.saturation < _achromatic) return c;

    return hsl.withSaturation((hsl.saturation * scale).clamp(0.0, 1.0))
        .toColor();
  }

  /// Piecewise so that [neutral] lands on 1 exactly, in both directions.
  static double _scale(int warmth) {
    if (warmth == neutral) return 1;
    return warmth < neutral
        ? _drained + (1 - _drained) * (warmth / neutral)
        : 1 + (_deepened - 1) * ((warmth - neutral) / (max - neutral));
  }

  /// [scheme] with every paper and ink role tempered to [warmth].
  ///
  /// The accent roles are deliberately absent: brass and sage carry meaning by
  /// hue, and the whole point of the slider is that it moves the *paper*.
  static ColorScheme temperScheme(ColorScheme scheme, int warmth) {
    if (warmth == neutral) return scheme;
    Color t(Color c) => temper(c, warmth);
    return scheme.copyWith(
      surface: t(scheme.surface),
      onSurface: t(scheme.onSurface),
      onSurfaceVariant: t(scheme.onSurfaceVariant),
      surfaceContainerLowest: t(scheme.surfaceContainerLowest),
      surfaceContainerLow: t(scheme.surfaceContainerLow),
      surfaceContainer: t(scheme.surfaceContainer),
      surfaceContainerHigh: t(scheme.surfaceContainerHigh),
      surfaceContainerHighest: t(scheme.surfaceContainerHighest),
      inverseSurface: t(scheme.inverseSurface),
      onInverseSurface: t(scheme.onInverseSurface),
      outlineVariant: t(scheme.outlineVariant),
      onPrimary: t(scheme.onPrimary),
      onSecondary: t(scheme.onSecondary),
      onTertiary: t(scheme.onTertiary),
      onError: t(scheme.onError),
    );
  }
}

/// The five words the warmth slider can show. Named rather than numbered so
/// the l10n strings and the control agree on how many there are.
enum PaperWarmthBand { cool, light, medium, warm, warmest }

/// Redesign v2 moved every value off neutral grey and onto warm paper: cream
/// ground, walnut ink, muted brass, a sage tick. The point is long sessions —
/// grey at reading brightness glares, and the old `#F3F2F2` surface against
/// `#201F1D` ink was the single thing that made the app read as cold.
///
/// Ink never reaches black in either mode, and paper never reaches white.
///
/// `inverseSurface`/`onInverseSurface` carry the *ink slab*: v2's primary
/// action is a filled walnut button with cream text, so those two roles are
/// load-bearing rather than snackbar-only.
///
/// These are the values at [PaperWarmth.neutral]; the slider tempers them.
const lightColorScheme = ColorScheme(
  brightness: Brightness.light,
  primary: Color(0xFF8A6224), // brass at text size — passes 4.5:1 on paper
  onPrimary: Color(0xFFFBF7ED),
  primaryContainer: Color(0xFFF3E6CE),
  onPrimaryContainer: Color(0xFF5A3F14),
  secondary: Color(0xFF5E7F63), // "done", and only "done"
  onSecondary: Color(0xFFFBF7ED),
  secondaryContainer: Color(0xFFDDE6DC),
  onSecondaryContainer: Color(0xFF2E4433),
  tertiary: Color(0xFF8A6224),
  onTertiary: Color(0xFFFBF7ED),
  surface: Color(0xFFF5EFE3), // cream ground — nav and chrome
  onSurface: Color(0xFF2E2721), // walnut ink
  onSurfaceVariant: Color(0xFF6B6157),
  surfaceContainerLowest: Color(0xFFFEFBF3),
  surfaceContainerLow: Color(0xFFFBF7ED), // the page — hero sheet, cards
  surfaceContainer: Color(0xFFF1EBDD),
  surfaceContainerHigh: Color(0xFFEBE4D3),
  surfaceContainerHighest: Color(0xFFE5DCC8),
  outline: Color(0xFFB0803C), // the accent *stroke*
  outlineVariant: Color(0x262C2723), // 15% ink — every hairline
  // The only red in the product is a genuine system failure, such as a
  // corrupt PDF. It is never a state the reader caused.
  error: Color(0xFF7D2C1A),
  onError: Color(0xFFFBF7ED),
  errorContainer: Color(0xFFF2E0D7),
  onErrorContainer: Color(0xFF4A1A0F),
  inverseSurface: Color(0xFF2E2721), // the ink slab
  onInverseSurface: Color(0xFFFBF7ED),
  inversePrimary: Color(0xFFD6A45F),
  shadow: Color(0xFF000000),
  scrim: Color(0xFF000000),
);

const darkColorScheme = ColorScheme(
  brightness: Brightness.dark,
  primary: Color(0xFFDDB278), // brass lifted for warm near-black
  onPrimary: Color(0xFF1B1815),
  primaryContainer: Color(0xFF3A2D1A),
  onPrimaryContainer: Color(0xFFEBD3AC),
  secondary: Color(0xFF7FA083),
  onSecondary: Color(0xFF12140F),
  secondaryContainer: Color(0xFF2A3A2C),
  onSecondaryContainer: Color(0xFFB4CBB6),
  tertiary: Color(0xFFDDB278),
  onTertiary: Color(0xFF1B1815),
  surface: Color(0xFF1B1815), // warm near-black, not neutral grey
  onSurface: Color(0xFFEAE0CB), // never white — cream ink
  onSurfaceVariant: Color(0xFFA99C8A),
  surfaceContainerLowest: Color(0xFF151310),
  surfaceContainerLow: Color(0xFF221E18), // the page
  surfaceContainer: Color(0xFF262119),
  surfaceContainerHigh: Color(0xFF2C261E),
  surfaceContainerHighest: Color(0xFF342D24),
  outline: Color(0xFFD6A45F),
  outlineVariant: Color(0x26E8DFCE),
  error: Color(0xFFD98A73),
  onError: Color(0xFF1B1815),
  errorContainer: Color(0xFF4A1A0F),
  onErrorContainer: Color(0xFFF2E0D7),
  inverseSurface: Color(0xFFEAE0CB), // the ink slab, inverted
  onInverseSurface: Color(0xFF1B1815),
  inversePrimary: Color(0xFF8A6224),
  shadow: Color(0xFF000000),
  scrim: Color(0xFF000000),
);
