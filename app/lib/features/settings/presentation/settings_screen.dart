import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/auth/auth_state.dart';
import '../../../core/settings/app_settings.dart';
import '../../../core/sync/sync_engine.dart';
import '../../../core/sync/sync_status.dart';
import '../../account/application/account_controller.dart';
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
                  const SizedBox(height: AppSpacing.x6 - 4),
                  Kicker(l10n.settingsAccount),
                  const SizedBox(height: 11),
                  const AccountSection(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The account block on the settings screen: who is signed in, whether
/// anything is still waiting to be sent, and the way in or out.
class AccountSection extends ConsumerWidget {
  const AccountSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final session = ref.watch(authStateProvider);

    if (session == null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(l10n.settingsSignedOut, style: theme.textTheme.bodyMedium),
          const SizedBox(height: AppSpacing.x1),
          Text(
            l10n.settingsSignedOutHint,
            style: theme.textTheme.bodySmall?.copyWith(
              height: 1.6,
              color: theme.appColors.muted,
            ),
          ),
          const SizedBox(height: AppSpacing.x3),
          OutlinedButton(
            onPressed: () => context.push('/account'),
            child: Text(l10n.settingsSignIn),
          ),
        ],
      );
    }

    final status = ref.watch(syncControllerProvider);
    final pending = ref.watch(pendingSyncCountProvider).value ?? 0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          l10n.accountWelcome(session.email),
          style: theme.textTheme.bodyMedium,
        ),
        const SizedBox(height: AppSpacing.x1),
        Text(
          // What is actually true right now, in this order: a sync in flight
          // outranks a queue, and a queue outranks "up to date" — saying
          // everything is saved while rows are still waiting would be a lie
          // the reader only discovers by losing them.
          switch (status) {
            SyncInProgress() => l10n.settingsSyncing,
            SyncFailed() => l10n.settingsSyncFailed,
            _ when pending > 0 => l10n.settingsSyncPending(pending),
            _ => l10n.settingsSyncDone,
          },
          style: theme.textTheme.bodySmall?.copyWith(
            height: 1.6,
            color: status is SyncFailed
                ? theme.colorScheme.error
                : theme.appColors.muted,
          ),
        ),
        const SizedBox(height: AppSpacing.x3),
        OutlinedButton(
          onPressed: status is SyncInProgress
              ? null
              : () => ref.read(syncControllerProvider.notifier).syncNow(),
          child: Text(l10n.settingsSyncNow),
        ),
        const SizedBox(height: AppSpacing.x2),
        TextButton(
          onPressed: () =>
              ref.read(accountControllerProvider.notifier).signOut(),
          child: Text(l10n.settingsSignOut),
        ),
      ],
    );
  }
}
