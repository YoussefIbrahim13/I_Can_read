import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_tokens.dart';
import '../../../core/widgets/screen_header.dart';
import '../../../l10n/app_localizations.dart';
import '../application/backup_controller.dart';
import '../domain/backup_file.dart';

/// Writing the library out to a file, and reading one back in.
///
/// Its own screen as of Redesign v2. It used to be a block on Settings, which
/// put two buttons and a paragraph of explanation in the middle of a list of
/// switches — and the explanation is the important part. A reader with no
/// account has no other way out of this app, and a reader with one may still
/// want a copy that does not depend on a server being up. That deserves a
/// screen rather than a footnote.
class BackupScreen extends ConsumerWidget {
  const BackupScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final state = ref.watch(backupControllerProvider);
    final controller = ref.read(backupControllerProvider.notifier);
    final busy = state is BackupWorking;

    // What just happened, or — before anything has — what this is for.
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

    return Scaffold(
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ScreenBackBar(title: l10n.settingsBackup),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.gutter,
                  AppSpacing.x4,
                  AppSpacing.gutter,
                  AppSpacing.x6,
                ),
                children: [
                  Text(
                    note,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      height: 1.75,
                      color: state is BackupFailed
                          ? theme.colorScheme.error
                          : theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.x6 - 4),
                  FilledButton(
                    onPressed: busy ? null : controller.export,
                    child: Text(l10n.backupExport),
                  ),
                  const SizedBox(height: AppSpacing.x2),
                  // Second, and outlined: restoring writes over what is here,
                  // and it is not the reason anyone opens this screen.
                  OutlinedButton(
                    onPressed: busy ? null : controller.import,
                    child: Text(l10n.backupImport),
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
