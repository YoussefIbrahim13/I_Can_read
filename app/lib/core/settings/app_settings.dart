import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../theme/app_tokens.dart';

/// Overridden in `main()` once [SharedPreferences] has loaded, so the rest of
/// the app can read settings synchronously.
final sharedPreferencesProvider = Provider<SharedPreferences>(
  (ref) => throw StateError('sharedPreferencesProvider was not overridden'),
);

/// The locales this app ships translations for.
const supportedLocales = <Locale>[Locale('ar'), Locale('en')];

@immutable
class AppSettings {
  const AppSettings({
    required this.locale,
    required this.themeMode,
    required this.paperWarmth,
    required this.hasOnboarded,
  });

  /// `null` means "follow the system locale".
  final Locale? locale;
  final ThemeMode themeMode;

  /// How cream the paper is, 0–100. See `PaperWarmth`.
  ///
  /// Kept here rather than beside the theme because it is a reader's choice
  /// that has to outlive the process, and it applies to light and dark alike —
  /// the same reader wants the same paper in both.
  final int paperWarmth;

  /// False until the reader has been through the welcome screen once.
  ///
  /// Deliberately not inferred from "has no books": a reader who finishes and
  /// deletes everything would be walked through the introduction again, and
  /// an empty library already has its own empty state saying the same thing.
  final bool hasOnboarded;

  AppSettings copyWith({
    Locale? locale,
    bool clearLocale = false,
    ThemeMode? themeMode,
    int? paperWarmth,
    bool? hasOnboarded,
  }) {
    return AppSettings(
      locale: clearLocale ? null : (locale ?? this.locale),
      themeMode: themeMode ?? this.themeMode,
      paperWarmth: paperWarmth ?? this.paperWarmth,
      hasOnboarded: hasOnboarded ?? this.hasOnboarded,
    );
  }
}

class AppSettingsNotifier extends Notifier<AppSettings> {
  static const _localeKey = 'settings.locale';
  static const _themeKey = 'settings.themeMode';
  static const _warmthKey = 'settings.paperWarmth';
  static const _onboardedKey = 'settings.hasOnboarded';

  @override
  AppSettings build() {
    final prefs = ref.watch(sharedPreferencesProvider);
    final languageCode = prefs.getString(_localeKey);
    return AppSettings(
      locale: languageCode == null ? null : Locale(languageCode),
      themeMode: ThemeMode.values.firstWhere(
        (mode) => mode.name == prefs.getString(_themeKey),
        orElse: () => ThemeMode.system,
      ),
      // Clamped on read as well as on write: the value reaches the palette on
      // every frame, and a hand-edited or half-written preference should land
      // the reader on a usable theme rather than on an unpainted one.
      paperWarmth: PaperWarmth.clamped(
        prefs.getInt(_warmthKey) ?? PaperWarmth.neutral,
      ),
      hasOnboarded: prefs.getBool(_onboardedKey) ?? false,
    );
  }

  /// Pass `null` to follow the system locale.
  Future<void> setLocale(Locale? locale) async {
    state = state.copyWith(locale: locale, clearLocale: locale == null);
    final prefs = ref.read(sharedPreferencesProvider);
    if (locale == null) {
      await prefs.remove(_localeKey);
    } else {
      await prefs.setString(_localeKey, locale.languageCode);
    }
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    state = state.copyWith(themeMode: mode);
    await ref.read(sharedPreferencesProvider).setString(_themeKey, mode.name);
  }

  /// Sets the paper warmth, 0–100.
  ///
  /// The state moves first and the write is awaited after, so the palette
  /// follows the reader's thumb: this is called on every drag tick, and a
  /// theme that waited on the disk would lag behind the slider.
  Future<void> setPaperWarmth(int warmth) async {
    final value = PaperWarmth.clamped(warmth);
    if (value == state.paperWarmth) return;
    state = state.copyWith(paperWarmth: value);
    await ref.read(sharedPreferencesProvider).setInt(_warmthKey, value);
  }

  /// Remembers that the welcome screen has been seen.
  ///
  /// Written before navigating away, so a reader who kills the app on the very
  /// next frame still does not meet the introduction twice.
  Future<void> completeOnboarding() async {
    state = state.copyWith(hasOnboarded: true);
    await ref.read(sharedPreferencesProvider).setBool(_onboardedKey, true);
  }
}

final appSettingsProvider = NotifierProvider<AppSettingsNotifier, AppSettings>(
  AppSettingsNotifier.new,
);
