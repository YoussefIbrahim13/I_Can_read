import 'package:flutter/material.dart';

/// The two type stacks, chosen by locale rather than by fallback.
///
/// Passing one [TextTheme] with `fontFamilyFallback` gives Arabic text Latin
/// leading, which is visibly wrong: Plex Arabic's ascenders and dots need
/// 1.7–1.85 where Lora is comfortable at 1.5–1.65. So there are two themes and
/// [AppTypography.forLocale] picks one.
abstract final class AppFonts {
  static const arabic = 'IBM Plex Sans Arabic';

  /// English headings — and, in *both* locales, every standing figure.
  static const display = 'Cormorant Garamond';

  /// English body.
  static const serif = 'Lora';
}

/// Shipped as a variable font, so the weight has to be set on the `wght` axis
/// as well as on [TextStyle.fontWeight]; the latter alone only picks between
/// declared assets and would leave Skia synthesising the bold.
List<FontVariation> _wght(FontWeight weight) => [
  FontVariation('wght', weight.value.toDouble()),
];

/// Figures are tabular everywhere. A page counter that reflows as it counts up
/// is the kind of small jitter that makes a reading app feel cheap.
const _tabular = [FontFeature.tabularFigures()];

abstract final class AppTypography {
  static TextTheme forLocale(Locale locale) =>
      locale.languageCode == 'ar' ? arabic : english;

  /// The figure style, used inside both locales. Always pair it with
  /// `Directionality(textDirection: TextDirection.ltr, ...)` or the digits
  /// will reorder against surrounding Arabic — see `Figure`.
  static TextStyle figure({
    required double size,
    double height = 1,
    FontWeight weight = FontWeight.w400,
  }) {
    return TextStyle(
      fontFamily: AppFonts.display,
      fontSize: size,
      height: height,
      fontWeight: weight,
      fontVariations: _wght(weight),
      fontFeatures: _tabular,
    );
  }

  /// Arabic: one family at 300/400/500, hierarchy from size and colour only.
  /// There is no capital height to lean on, so nothing here uses caps.
  static const arabic = TextTheme(
    // Standing numerals — the big "7", the "34%".
    displayLarge: TextStyle(
      fontFamily: AppFonts.display,
      fontSize: 54,
      height: 0.85,
      fontWeight: FontWeight.w400,
      fontVariations: [FontVariation('wght', 400)],
      fontFeatures: _tabular,
    ),
    displayMedium: TextStyle(
      fontFamily: AppFonts.display,
      fontSize: 44,
      height: 0.9,
      fontWeight: FontWeight.w400,
      fontVariations: [FontVariation('wght', 400)],
      fontFeatures: _tabular,
    ),
    // Screen title.
    headlineMedium: TextStyle(
      fontFamily: AppFonts.arabic,
      fontSize: 27,
      height: 1.35,
      fontWeight: FontWeight.w400,
    ),
    // Hero sentence — the plan preview, the empty state's one line.
    titleLarge: TextStyle(
      fontFamily: AppFonts.arabic,
      fontSize: 21,
      height: 1.85,
      fontWeight: FontWeight.w300,
    ),
    // Card title.
    titleMedium: TextStyle(
      fontFamily: AppFonts.arabic,
      fontSize: 19,
      height: 1.5,
      fontWeight: FontWeight.w400,
    ),
    titleSmall: TextStyle(
      fontFamily: AppFonts.arabic,
      fontSize: 16,
      height: 1.5,
      fontWeight: FontWeight.w400,
    ),
    bodyLarge: TextStyle(
      fontFamily: AppFonts.arabic,
      fontSize: 14.5,
      height: 1.7,
      fontWeight: FontWeight.w400,
    ),
    bodyMedium: TextStyle(
      fontFamily: AppFonts.arabic,
      fontSize: 13,
      height: 1.75,
      fontWeight: FontWeight.w300,
    ),
    bodySmall: TextStyle(
      fontFamily: AppFonts.arabic,
      fontSize: 12.5,
      height: 1.85,
      fontWeight: FontWeight.w300,
    ),
    labelLarge: TextStyle(
      fontFamily: AppFonts.arabic,
      fontSize: 15,
      height: 1.4,
      fontWeight: FontWeight.w500,
    ),
    labelMedium: TextStyle(
      fontFamily: AppFonts.arabic,
      fontSize: 13,
      height: 1.5,
      fontWeight: FontWeight.w400,
    ),
    // Kicker. The 0.14em tracking is safe on Arabic because the letters are
    // already joined and the eye reads the run as a label, not as a word.
    labelSmall: TextStyle(
      fontFamily: AppFonts.arabic,
      fontSize: 10,
      height: 1.6,
      fontWeight: FontWeight.w500,
      letterSpacing: 1.4,
    ),
  );

  /// English: Lora for body, Cormorant Garamond for headings and figures.
  static const english = TextTheme(
    displayLarge: TextStyle(
      fontFamily: AppFonts.display,
      fontSize: 54,
      height: 0.85,
      fontWeight: FontWeight.w400,
      fontVariations: [FontVariation('wght', 400)],
      fontFeatures: _tabular,
    ),
    displayMedium: TextStyle(
      fontFamily: AppFonts.display,
      fontSize: 44,
      height: 0.9,
      fontWeight: FontWeight.w400,
      fontVariations: [FontVariation('wght', 400)],
      fontFeatures: _tabular,
    ),
    headlineMedium: TextStyle(
      fontFamily: AppFonts.display,
      fontSize: 30,
      height: 1.15,
      fontWeight: FontWeight.w400,
      fontVariations: [FontVariation('wght', 400)],
      letterSpacing: -0.45,
    ),
    titleLarge: TextStyle(
      fontFamily: AppFonts.serif,
      fontSize: 21,
      height: 1.5,
      fontWeight: FontWeight.w400,
      fontVariations: [FontVariation('wght', 400)],
    ),
    titleMedium: TextStyle(
      fontFamily: AppFonts.display,
      fontSize: 21,
      height: 1.25,
      fontWeight: FontWeight.w400,
      fontVariations: [FontVariation('wght', 400)],
    ),
    titleSmall: TextStyle(
      fontFamily: AppFonts.display,
      fontSize: 17,
      height: 1.35,
      fontWeight: FontWeight.w400,
      fontVariations: [FontVariation('wght', 400)],
    ),
    bodyLarge: TextStyle(
      fontFamily: AppFonts.serif,
      fontSize: 14.5,
      height: 1.6,
      fontWeight: FontWeight.w400,
      fontVariations: [FontVariation('wght', 400)],
    ),
    bodyMedium: TextStyle(
      fontFamily: AppFonts.serif,
      fontSize: 13,
      height: 1.65,
      fontWeight: FontWeight.w400,
      fontVariations: [FontVariation('wght', 400)],
    ),
    bodySmall: TextStyle(
      fontFamily: AppFonts.serif,
      fontSize: 12.5,
      height: 1.65,
      fontWeight: FontWeight.w400,
      fontVariations: [FontVariation('wght', 400)],
    ),
    labelLarge: TextStyle(
      fontFamily: AppFonts.display,
      fontSize: 15,
      height: 1.3,
      fontWeight: FontWeight.w600,
      fontVariations: [FontVariation('wght', 600)],
    ),
    labelMedium: TextStyle(
      fontFamily: AppFonts.serif,
      fontSize: 13,
      height: 1.45,
      fontWeight: FontWeight.w400,
      fontVariations: [FontVariation('wght', 400)],
    ),
    labelSmall: TextStyle(
      fontFamily: AppFonts.serif,
      fontSize: 10,
      height: 1.4,
      fontWeight: FontWeight.w600,
      fontVariations: [FontVariation('wght', 600)],
      letterSpacing: 1.4,
    ),
  );
}
