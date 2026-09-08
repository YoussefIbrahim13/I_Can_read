import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/branding/app_mark.dart';
import '../../../core/settings/app_settings.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/widgets/kicker.dart';
import '../../../core/widgets/segmented_control.dart';
import '../../../l10n/app_localizations.dart';

/// Sentinel for "follow the system language", matching the settings screen:
/// an explicit value keeps the control from reading as "nothing selected".
const _systemLanguage = 'system';

/// Screen 2 — the first thing a new reader sees.
///
/// It asks for the two things that change how every later screen is drawn, and
/// nothing else. Notification permission is deliberately not requested here:
/// the sessions screen asks for it right after the reader has set times to be
/// reminded at, where the prompt answers a question they just raised.
///
/// Both choices apply the moment they are made — the screen redraws itself in
/// the chosen language and theme — so the reader sees what they picked rather
/// than being told they will see it later.
class OnboardingScreen extends ConsumerWidget {
  const OnboardingScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final settings = ref.watch(appSettingsProvider);
    final notifier = ref.read(appSettingsProvider.notifier);

    Future<void> start() async {
      await notifier.completeOnboarding();
      if (context.mounted) context.go('/today');
    }

    return Scaffold(
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.gutter,
                  AppSpacing.x8,
                  AppSpacing.gutter,
                  AppSpacing.x6,
                ),
                children: [
                  const _Mark(),
                  const SizedBox(height: AppSpacing.x6),
                  Kicker(l10n.onboardingWelcome),
                  const SizedBox(height: AppSpacing.x2),
                  Text(
                    l10n.onboardingTitle,
                    style: theme.textTheme.headlineMedium,
                  ),
                  const SizedBox(height: AppSpacing.x3),
                  Text(
                    l10n.onboardingBody,
                    style: theme.textTheme.bodyMedium?.copyWith(height: 1.75),
                  ),
                  const SizedBox(height: AppSpacing.x3),
                  // The rule the whole app is built on, said once, up front —
                  // so that missing a day later is something the reader was
                  // told about rather than something they discover.
                  Text(
                    l10n.onboardingMissedDays,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      height: 1.75,
                      color: theme.appColors.muted,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.x6),
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
                        // segment opts out of the locale's type stack.
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
                  const SizedBox(height: AppSpacing.x4),
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
            // Pinned below the scroll, not at the end of it: the promise about
            // the file and the way forward should not need scrolling to on a
            // short screen.
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.gutter,
                AppSpacing.x3,
                AppSpacing.gutter,
                AppSpacing.x4,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    l10n.onboardingPrivacy,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontSize: 11.5,
                      height: 1.6,
                      color: theme.appColors.muted,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.x3),
                  OutlinedButton(
                    onPressed: start,
                    child: Text(l10n.onboardingStart),
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

/// The mark, on its own paper plate.
///
/// The mark is fixed ink and gold and does not follow the theme — that is the
/// point of it — so in dark mode it needs the paper it was drawn for, or the
/// ink outline disappears into the background.
class _Mark extends StatelessWidget {
  const _Mark();

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: AlignmentDirectional.centerStart,
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.x2),
        decoration: BoxDecoration(
          color: markPaper,
          borderRadius: BorderRadius.circular(AppSpacing.radius),
        ),
        child: const AppMark(size: 44),
      ),
    );
  }
}
