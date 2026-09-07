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
  const AppSettings({required this.locale, required this.themeMode});

  /// `null` means "follow the system locale".
  final Locale? locale;
  final ThemeMode themeMode;

  AppSettings copyWith({
    Locale? locale,
    bool clearLocale = false,
    ThemeMode? themeMode,
  }) {
    return AppSettings(
      locale: clearLocale ? null : (locale ?? this.locale),
      themeMode: themeMode ?? this.themeMode,
    );
  }
}

class AppSettingsNotifier extends Notifier<AppSettings> {
  static const _localeKey = 'settings.locale';
  static const _themeKey = 'settings.themeMode';

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
}

final appSettingsProvider = NotifierProvider<AppSettingsNotifier, AppSettings>(
  AppSettingsNotifier.new,
);
