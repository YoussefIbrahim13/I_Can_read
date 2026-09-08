import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
    required this.hasOnboarded,
  });

  /// `null` means "follow the system locale".
  final Locale? locale;
  final ThemeMode themeMode;

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
    bool? hasOnboarded,
  }) {
    return AppSettings(
      locale: clearLocale ? null : (locale ?? this.locale),
      themeMode: themeMode ?? this.themeMode,
      hasOnboarded: hasOnboarded ?? this.hasOnboarded,
    );
  }
}

class AppSettingsNotifier extends Notifier<AppSettings> {
  static const _localeKey = 'settings.locale';
  static const _themeKey = 'settings.themeMode';
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
