import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/auth/auth_state.dart';
import '../../../core/config/legal_links.dart';
import '../../../core/settings/app_settings.dart';
import '../../../core/sync/sync_engine.dart';
import '../../../core/sync/sync_status.dart';
import '../../account/application/account_controller.dart';
import '../../backup/application/backup_controller.dart';
import '../../backup/domain/backup_file.dart';
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
                  const SizedBox(height: AppSpacing.x6 - 4),
                  Kicker(l10n.settingsBackup),
                  const SizedBox(height: 11),
                  const _BackupSection(),
                  const _PrivacyPolicyLink(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The way to the published privacy policy.
///
/// Last on the screen, and absent entirely in a build that was not given a URL.
class _PrivacyPolicyLink extends ConsumerWidget {
  const _PrivacyPolicyLink();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final url = ref.watch(privacyPolicyUrlProvider);
    if (url == null) return const SizedBox.shrink();

    final l10n = AppLocalizations.of(context);

    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.x6 - 4),
      child: Align(
        alignment: AlignmentDirectional.centerStart,
        child: TextButton(
          // External on purpose: an in-app browser would put our chrome around
          // a document whose whole point is that the reader can check it for
          // themselves, and share it with anyone.
          onPressed: () =>
              launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication),
          style: TextButton.styleFrom(
            foregroundColor: Theme.of(context).appColors.muted,
          ),
          child: Text(l10n.settingsPrivacyPolicy),
        ),
      ),
    );
  }
}

/// Writing the library out to a file, and reading one back in.
///
/// Not the same thing as the account, and sits apart from it on purpose: a
/// reader with no account has no other way out of this app, and a reader with
/// one may still want a copy that does not depend on a server being up.
class _BackupSection extends ConsumerWidget {
  const _BackupSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final state = ref.watch(backupControllerProvider);
    final controller = ref.read(backupControllerProvider.notifier);
    final busy = state is BackupWorking;

    final note = switch (state) {
      BackupWorking() => l10n.settingsSyncing,
      BackupExported(:final items) => l10n.backupExported(items),
      BackupImported(:final items) => l10n.backupImported(items),
      BackupFailed(problem: BackupProblem.tooNew) => l10n.backupErrorTooNew,
      BackupFailed(problem: BackupProblem.notABackup) =>
        l10n.backupErrorNotABackup,
      BackupFailed() => l10n.backupErrorFailed,
      BackupIdle() => l10n.settingsBackupHint,
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          note,
          style: theme.textTheme.bodySmall?.copyWith(
            height: 1.6,
            color: state is BackupFailed
                ? theme.colorScheme.error
                : theme.appColors.muted,
          ),
        ),
        const SizedBox(height: AppSpacing.x3),
        OutlinedButton(
          onPressed: busy ? null : controller.export,
          child: Text(l10n.backupExport),
        ),
        const SizedBox(height: AppSpacing.x2),
        TextButton(
          onPressed: busy ? null : controller.import,
          child: Text(l10n.backupImport),
        ),
      ],
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
        // Last, and set apart from signing out: the two read as neighbours if
        // they sit together, and one of them cannot be undone.
        const SizedBox(height: AppSpacing.x2),
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: TextButton(
            onPressed: () => context.push('/account/delete'),
            style: TextButton.styleFrom(foregroundColor: theme.appColors.muted),
            child: Text(l10n.deleteAccount),
          ),
        ),
      ],
    );
  }
}
