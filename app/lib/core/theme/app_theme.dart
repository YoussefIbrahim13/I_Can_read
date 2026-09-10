import 'package:flutter/material.dart';

import 'app_tokens.dart';
import 'app_typography.dart';

/// The app's theme, built from literal values rather than [ColorScheme.fromSeed].
///
/// Two things drive almost every override below:
///
/// * **Elevation is a hairline, not a shadow.** Nothing casts a shadow except
///   the modal sheet, so every component gets `surfaceTintColor: transparent`
///   — otherwise M3 tints surfaces with `primary` as they "elevate".
/// * **The primary action is an ink slab.** Redesign v2 reversed the original
///   outline-only rule: the one committing action on a screen is a filled
///   walnut-ink button with cream text ([FilledButton]), and [OutlinedButton]
///   is the step down from it. The fill is *ink*, never gold — gold stays a
///   stroke colour, so the accent never becomes a field.
///
/// Screens are being moved onto the v2 slab one at a time. Until a screen is
/// converted its primary stays an [OutlinedButton] in gold, which still reads
/// as primary on its own screen; what must not happen is a screen showing two
/// competing primaries.
abstract final class AppTheme {
  /// Both brightness and locale change the theme, and the locale is only known
  /// below `MaterialApp`, so themes are built on demand and cached. There are
  /// at most four.
  static final _cache = <String, ThemeData>{};

  static ThemeData of({
    required Brightness brightness,
    required Locale locale,
  }) {
    final key = '${brightness.name}.${locale.languageCode}';
    return _cache[key] ??= _build(brightness, locale);
  }

  /// The theme `MaterialApp` starts with, before [of] refines it for the
  /// resolved locale. Arabic is the default because it is the app's first
  /// language, not a translation of the English one.
  static ThemeData light() =>
      of(brightness: Brightness.light, locale: const Locale('ar'));

  static ThemeData dark() =>
      of(brightness: Brightness.dark, locale: const Locale('ar'));

  static ThemeData _build(Brightness brightness, Locale locale) {
    final isLight = brightness == Brightness.light;
    final colors = isLight ? lightColorScheme : darkColorScheme;
    final extras = isLight ? AppColors.light : AppColors.dark;
    final text = AppTypography.forLocale(locale);

    const shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.all(Radius.circular(AppSpacing.radius)),
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: colors,
      brightness: brightness,
      scaffoldBackgroundColor: colors.surface,
      canvasColor: colors.surface,
      textTheme: text,
      extensions: [extras],
      // The gold is a stroke colour; letting it wash over ripples and
      // selection fills is exactly the "colour as field" the design forbids.
      splashFactory: InkSparkle.splashFactory,
      appBarTheme: AppBarTheme(
        backgroundColor: colors.surface,
        foregroundColor: colors.onSurface,
        surfaceTintColor: Colors.transparent,
        shadowColor: Colors.transparent,
        scrolledUnderElevation: 0,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: text.titleSmall,
        iconTheme: IconThemeData(color: colors.onSurfaceVariant, size: 22),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        margin: EdgeInsets.zero,
        color: colors.surfaceContainerLow,
        surfaceTintColor: Colors.transparent,
        shadowColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppSpacing.radius),
          side: BorderSide(color: extras.hairline),
        ),
      ),
      dividerTheme: DividerThemeData(
        color: extras.hairline,
        thickness: 1,
        space: 0,
      ),
      // The app's primary action.
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: ButtonStyle(
          minimumSize: const WidgetStatePropertyAll(Size.fromHeight(48)),
          shape: const WidgetStatePropertyAll(shape),
          backgroundColor: const WidgetStatePropertyAll(Colors.transparent),
          overlayColor: WidgetStatePropertyAll(
            colors.primary.withValues(alpha: 0.06),
          ),
          textStyle: WidgetStatePropertyAll(text.labelLarge),
          // M3 greys out a disabled button; here it only loses opacity, so a
          // temporarily unavailable action still reads as the same control.
          foregroundColor: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.disabled)
                ? colors.primary.withValues(alpha: 0.45)
                : colors.primary,
          ),
          side: WidgetStateProperty.resolveWith(
            (states) => BorderSide(
              color: states.contains(WidgetState.disabled)
                  ? extras.accentStroke.withValues(alpha: 0.45)
                  : extras.accentStroke,
            ),
          ),
        ),
      ),
      // The v2 primary: a slab of walnut ink with cream text. 50 tall rather
      // than 48 because it is the one control on the screen that should look
      // committed to.
      filledButtonTheme: FilledButtonThemeData(
        style: ButtonStyle(
          minimumSize: const WidgetStatePropertyAll(Size.fromHeight(50)),
          shape: const WidgetStatePropertyAll(shape),
          elevation: const WidgetStatePropertyAll(0),
          textStyle: WidgetStatePropertyAll(text.labelLarge),
          // Disabled loses opacity rather than turning grey — grey is exactly
          // what v2 removed from the palette.
          backgroundColor: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.disabled)
                ? colors.inverseSurface.withValues(alpha: 0.38)
                : colors.inverseSurface,
          ),
          foregroundColor: WidgetStatePropertyAll(colors.onInverseSurface),
          overlayColor: WidgetStatePropertyAll(
            colors.onInverseSurface.withValues(alpha: 0.10),
          ),
          side: const WidgetStatePropertyAll(BorderSide.none),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: ButtonStyle(
          shape: const WidgetStatePropertyAll(shape),
          textStyle: WidgetStatePropertyAll(text.labelMedium),
          foregroundColor: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.disabled)
                ? colors.onSurfaceVariant.withValues(alpha: 0.45)
                : colors.onSurfaceVariant,
          ),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: ButtonStyle(
          shape: const WidgetStatePropertyAll(shape),
          foregroundColor: WidgetStatePropertyAll(colors.onSurfaceVariant),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: false,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 11,
          vertical: 12,
        ),
        labelStyle: text.bodyMedium?.copyWith(color: colors.onSurfaceVariant),
        floatingLabelStyle: text.bodySmall?.copyWith(color: colors.primary),
        hintStyle: text.bodyLarge?.copyWith(color: extras.muted),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppSpacing.radius),
          borderSide: BorderSide(color: extras.hairline),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppSpacing.radius),
          borderSide: BorderSide(color: extras.hairline),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppSpacing.radius),
          borderSide: BorderSide(color: extras.accentStroke),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppSpacing.radius),
          borderSide: BorderSide(color: colors.error),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppSpacing.radius),
          borderSide: BorderSide(color: colors.error),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: colors.surface,
        surfaceTintColor: Colors.transparent,
        shadowColor: Colors.transparent,
        elevation: 0,
        height: 62,
        // The selected item is marked by an 18×1 rule drawn under its label
        // (see `AppNavigationBar`), not by M3's pill.
        indicatorColor: Colors.transparent,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
      ),
      tabBarTheme: TabBarThemeData(
        labelColor: colors.primary,
        unselectedLabelColor: extras.muted,
        labelStyle: text.labelLarge?.copyWith(fontSize: 13.5),
        unselectedLabelStyle: text.labelMedium?.copyWith(fontSize: 13.5),
        indicatorSize: TabBarIndicatorSize.label,
        indicator: UnderlineTabIndicator(
          borderSide: BorderSide(color: extras.accentStroke),
        ),
        dividerColor: extras.hairline,
        dividerHeight: 1,
        overlayColor: const WidgetStatePropertyAll(Colors.transparent),
      ),
      listTileTheme: ListTileThemeData(
        contentPadding: EdgeInsets.zero,
        minVerticalPadding: 13,
        titleTextStyle: text.bodyLarge,
        subtitleTextStyle: text.bodySmall?.copyWith(color: extras.muted),
        iconColor: extras.muted,
      ),
      // The one component allowed a shadow.
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: colors.surfaceContainerLow,
        surfaceTintColor: Colors.transparent,
        elevation: 12,
        shadowColor: Colors.black.withValues(alpha: 0.22),
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(AppSpacing.radius),
          ),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: colors.surfaceContainerLow,
        surfaceTintColor: Colors.transparent,
        elevation: 12,
        shape: shape,
        titleTextStyle: text.titleMedium,
        contentTextStyle: text.bodyLarge?.copyWith(
          color: colors.onSurfaceVariant,
        ),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          backgroundColor: const WidgetStatePropertyAll(Colors.transparent),
          shape: const WidgetStatePropertyAll(shape),
          textStyle: WidgetStatePropertyAll(text.labelMedium),
          foregroundColor: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.selected)
                ? colors.primary
                : colors.onSurfaceVariant,
          ),
          side: WidgetStateProperty.resolveWith(
            (states) => BorderSide(
              color: states.contains(WidgetState.selected)
                  ? extras.accentStroke
                  : extras.hairline,
            ),
          ),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: Colors.transparent,
        side: BorderSide(color: extras.hairline),
        shape: shape,
        labelStyle: text.bodySmall?.copyWith(color: colors.onSurfaceVariant),
        showCheckmark: false,
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: colors.inverseSurface,
        contentTextStyle: text.bodyMedium?.copyWith(
          color: colors.onInverseSurface,
        ),
        shape: shape,
        behavior: SnackBarBehavior.floating,
        elevation: 0,
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: extras.accentStroke,
        linearTrackColor: extras.hairline,
        circularTrackColor: Colors.transparent,
        linearMinHeight: 1,
      ),
      radioTheme: RadioThemeData(
        fillColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? extras.accentStroke
              : extras.muted,
        ),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? colors.primary
              : extras.muted,
        ),
        trackColor: const WidgetStatePropertyAll(Colors.transparent),
        trackOutlineColor: WidgetStatePropertyAll(extras.hairline),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: colors.surfaceContainerLow,
        foregroundColor: colors.primary,
        elevation: 0,
        focusElevation: 0,
        hoverElevation: 0,
        highlightElevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppSpacing.radius),
          side: BorderSide(color: extras.accentStroke),
        ),
      ),
    );
  }
}
