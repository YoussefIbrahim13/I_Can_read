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
  final Color stripe;

  /// Laid over a progress bar as 1px repeating rules, so a filled bar reads as
  /// printed lines rather than as a solid slab of colour.
  final Color gutter;

  /// The pressed state of a tappable row. v2's rule is that almost everything
  /// answers to a tap, so rows need a press wash the ripple alone doesn't give.
  final Color press;

  static const light = AppColors(
    muted: Color(0xFF948A7D),
    done: Color(0xFF5E7F63),
    doneWash: Color(0x1A5E7F63),
    onDone: Color(0xFFFBF6EC),
    hairline: Color(0x262C2723),
    readerBackground: Color(0xFFFAF8F2),
    accentStroke: Color(0xFFB0803C),
    gutter: Color(0x212C2723),
    stripe: Color(0xB3FAF8F2),
    press: Color(0x0D2C2723),
  );

  static const dark = AppColors(
    muted: Color(0xFF7E7365),
    done: Color(0xFF7FA083),
    doneWash: Color(0x247FA083),
    onDone: Color(0xFF12140F),
    hairline: Color(0x26E8DFCE),
    readerBackground: Color(0xFF1C1916),
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
}

/// `Theme.of(context).appColors` reads better at the call site than the
/// generic `extension<AppColors>()` lookup, and fails loudly if the extension
/// was never registered.
extension AppColorsAccess on ThemeData {
  AppColors get appColors => extension<AppColors>()!;
}

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
const lightColorScheme = ColorScheme(
  brightness: Brightness.light,
  primary: Color(0xFF8A6224), // brass at text size — passes 4.5:1 on paper
  onPrimary: Color(0xFFFBF6EC),
  primaryContainer: Color(0xFFF3E6CE),
  onPrimaryContainer: Color(0xFF5A3F14),
  secondary: Color(0xFF5E7F63), // "done", and only "done"
  onSecondary: Color(0xFFFBF6EC),
  secondaryContainer: Color(0xFFDDE6DC),
  onSecondaryContainer: Color(0xFF2E4433),
  tertiary: Color(0xFF8A6224),
  onTertiary: Color(0xFFFBF6EC),
  surface: Color(0xFFF3F0E8), // cream ground
  onSurface: Color(0xFF2C2723), // walnut ink
  onSurfaceVariant: Color(0xFF6B6157),
  surfaceContainerLowest: Color(0xFFFDFCF7),
  surfaceContainerLow: Color(0xFFFAF8F2), // the page — hero sheet, reader paper
  surfaceContainer: Color(0xFFF0ECE1),
  surfaceContainerHigh: Color(0xFFEAE5D8),
  surfaceContainerHighest: Color(0xFFE4DECF),
  outline: Color(0xFFB0803C), // the accent *stroke*
  outlineVariant: Color(0x262C2723), // 15% ink — every hairline
  // The only red in the product is a genuine system failure, such as a
  // corrupt PDF. It is never a state the reader caused.
  error: Color(0xFF7D2C1A),
  onError: Color(0xFFFBF6EC),
  errorContainer: Color(0xFFF2E0D7),
  onErrorContainer: Color(0xFF4A1A0F),
  inverseSurface: Color(0xFF2C2723), // the ink slab
  onInverseSurface: Color(0xFFFBF6EC),
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
  onSurface: Color(0xFFE8DFCE), // never white — cream ink
  onSurfaceVariant: Color(0xFFA99C8A),
  surfaceContainerLowest: Color(0xFF151310),
  surfaceContainerLow: Color(0xFF201D19), // the page
  surfaceContainer: Color(0xFF242019),
  surfaceContainerHigh: Color(0xFF2A251E),
  surfaceContainerHighest: Color(0xFF322C24),
  outline: Color(0xFFD6A45F),
  outlineVariant: Color(0x26E8DFCE),
  error: Color(0xFFD98A73),
  onError: Color(0xFF1B1815),
  errorContainer: Color(0xFF4A1A0F),
  onErrorContainer: Color(0xFFF2E0D7),
  inverseSurface: Color(0xFFE8DFCE), // the ink slab, inverted
  onInverseSurface: Color(0xFF1B1815),
  inversePrimary: Color(0xFF8A6224),
  shadow: Color(0xFF000000),
  scrim: Color(0xFF000000),
);
