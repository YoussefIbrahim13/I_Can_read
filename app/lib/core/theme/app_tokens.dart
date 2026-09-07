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
@immutable
class AppColors extends ThemeExtension<AppColors> {
  const AppColors({
    required this.muted,
    required this.done,
    required this.hairline,
    required this.readerBackground,
    required this.accentStroke,
  });

  /// Third-level text: captions, times, "of 8" counters.
  final Color muted;

  /// Completion, and nothing else. Never "good", never "on track".
  final Color done;

  /// Every 1px rule in the app.
  final Color hairline;

  /// The reader's own ground, a shade past `surface` in both modes.
  final Color readerBackground;

  /// Gold at stroke weight. Same value as `ColorScheme.outline`, named for the
  /// call sites that mean "the accent rule" rather than "a border".
  final Color accentStroke;

  static const light = AppColors(
    muted: Color(0xFF7D7979),
    done: Color(0xFF2E6F5E),
    hairline: Color(0x29201F1D),
    readerBackground: Color(0xFFF8F4F4),
    accentStroke: Color(0xFFB68235),
  );

  static const dark = AppColors(
    muted: Color(0xFF8B857E),
    done: Color(0xFF7FB8A4),
    hairline: Color(0x24EEEAE4),
    readerBackground: Color(0xFF141312),
    accentStroke: Color(0xFFE1AD66),
  );

  @override
  AppColors copyWith({
    Color? muted,
    Color? done,
    Color? hairline,
    Color? readerBackground,
    Color? accentStroke,
  }) {
    return AppColors(
      muted: muted ?? this.muted,
      done: done ?? this.done,
      hairline: hairline ?? this.hairline,
      readerBackground: readerBackground ?? this.readerBackground,
      accentStroke: accentStroke ?? this.accentStroke,
    );
  }

  @override
  AppColors lerp(AppColors? other, double t) {
    if (other == null) return this;
    return AppColors(
      muted: Color.lerp(muted, other.muted, t)!,
      done: Color.lerp(done, other.done, t)!,
      hairline: Color.lerp(hairline, other.hairline, t)!,
      readerBackground: Color.lerp(
        readerBackground,
        other.readerBackground,
        t,
      )!,
      accentStroke: Color.lerp(accentStroke, other.accentStroke, t)!,
    );
  }
}

/// `Theme.of(context).appColors` reads better at the call site than the
/// generic `extension<AppColors>()` lookup, and fails loudly if the extension
/// was never registered.
extension AppColorsAccess on ThemeData {
  AppColors get appColors => extension<AppColors>()!;
}

const lightColorScheme = ColorScheme(
  brightness: Brightness.light,
  primary: Color(0xFF7D5411), // gold-700 — the accent at text size
  onPrimary: Color(0xFFF8F4F4),
  primaryContainer: Color(0xFFFFF3E4),
  onPrimaryContainer: Color(0xFF5A3B0A),
  secondary: Color(0xFF2E6F5E), // "done", and only "done"
  onSecondary: Color(0xFFF8F4F4),
  secondaryContainer: Color(0xFFDCEAE4),
  onSecondaryContainer: Color(0xFF1B4237),
  tertiary: Color(0xFF7D5411),
  onTertiary: Color(0xFFF8F4F4),
  surface: Color(0xFFF3F2F2),
  onSurface: Color(0xFF201F1D),
  onSurfaceVariant: Color(0xFF605D5D),
  surfaceContainerLowest: Color(0xFFFFFFFF),
  surfaceContainerLow: Color(0xFFF8F4F4), // hero card, reader paper
  surfaceContainer: Color(0xFFF0EEEE),
  surfaceContainerHigh: Color(0xFFEAE9E9),
  surfaceContainerHighest: Color(0xFFE3E1E1),
  outline: Color(0xFFB68235), // the accent *stroke*
  outlineVariant: Color(0x29201F1D), // 16% ink — every hairline
  // The only red in the product is a genuine system failure, such as a
  // corrupt PDF. It is never a state the reader caused.
  error: Color(0xFF7D2C1A),
  onError: Color(0xFFF8F4F4),
  errorContainer: Color(0xFFF3E2DC),
  onErrorContainer: Color(0xFF4A1A0F),
  inverseSurface: Color(0xFF201F1D),
  onInverseSurface: Color(0xFFF3F2F2),
  inversePrimary: Color(0xFFE1AD66),
  shadow: Color(0xFF000000),
  scrim: Color(0xFF000000),
);

const darkColorScheme = ColorScheme(
  brightness: Brightness.dark,
  primary: Color(0xFFE1AD66), // gold-400 — legible on warm near-black
  onPrimary: Color(0xFF1A1918),
  primaryContainer: Color(0xFF3A2E1B),
  onPrimaryContainer: Color(0xFFF0D9B4),
  secondary: Color(0xFF7FB8A4),
  onSecondary: Color(0xFF12261F),
  secondaryContainer: Color(0xFF23372F),
  onSecondaryContainer: Color(0xFFB6D9CC),
  tertiary: Color(0xFFE1AD66),
  onTertiary: Color(0xFF1A1918),
  surface: Color(0xFF1A1918), // warm near-black, not neutral grey
  onSurface: Color(0xFFEEEAE4),
  onSurfaceVariant: Color(0xFFB0AAA2),
  surfaceContainerLowest: Color(0xFF141312),
  surfaceContainerLow: Color(0xFF232221), // hero card, notification
  surfaceContainer: Color(0xFF272524),
  surfaceContainerHigh: Color(0xFF2A2827),
  surfaceContainerHighest: Color(0xFF322F2E),
  outline: Color(0xFFE1AD66),
  outlineVariant: Color(0x24EEEAE4),
  error: Color(0xFFD98A73),
  onError: Color(0xFF1A1918),
  errorContainer: Color(0xFF4A1A0F),
  onErrorContainer: Color(0xFFF3E2DC),
  inverseSurface: Color(0xFFEEEAE4),
  onInverseSurface: Color(0xFF1A1918),
  inversePrimary: Color(0xFF7D5411),
  shadow: Color(0xFF000000),
  scrim: Color(0xFF000000),
);
