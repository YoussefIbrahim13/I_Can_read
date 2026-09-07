import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/settings/app_settings.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/widgets/kicker.dart';
import '../../../core/widgets/screen_header.dart';
import '../../../core/widgets/segmented_control.dart';
import '../../../l10n/app_localizations.dart';

/// Sentinel for "follow the system language". Using an explicit value rather
/// than `null` keeps the control from reading the choice as "nothing selected".
const _systemLanguage = 'system';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final settings = ref.watch(appSettingsProvider);
    final notifier = ref.read(appSettingsProvider.notifier);

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ScreenHeader(title: l10n.navSettings),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.gutter,
                  AppSpacing.x4,
                  AppSpacing.gutter,
                  AppSpacing.x6,
                ),
                children: [
                  Kicker(l10n.settingsLanguage),
                  const SizedBox(height: 11),
                  AppSegmentedControl<String>(
                    value: settings.locale?.languageCode ?? _systemLanguage,
                    onChanged: (value) => notifier.setLocale(
                      value == _systemLanguage ? null : Locale(value),
                    ),
                    segments: [
                      AppSegment(
                        value: 'ar',
                        label: l10n.settingsLanguageArabic,
                        // Each language names itself in its own script, so the
                        // segment has to opt out of the locale's type stack.
                        textStyle: const TextStyle(fontFamily: AppFonts.arabic),
                      ),
                      AppSegment(
                        value: 'en',
                        label: l10n.settingsLanguageEnglish,
                        textStyle: const TextStyle(fontFamily: AppFonts.serif),
                      ),
                      AppSegment(
                        value: _systemLanguage,
                        label: l10n.settingsLanguageSystem,
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.x6 - 4),
                  Kicker(l10n.settingsTheme),
                  const SizedBox(height: 11),
                  AppSegmentedControl<ThemeMode>(
                    value: settings.themeMode,
                    onChanged: notifier.setThemeMode,
                    segments: [
                      AppSegment(
                        value: ThemeMode.dark,
                        label: l10n.settingsThemeDark,
                      ),
                      AppSegment(
                        value: ThemeMode.light,
                        label: l10n.settingsThemeLight,
                      ),
                      AppSegment(
                        value: ThemeMode.system,
                        label: l10n.settingsThemeSystem,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
