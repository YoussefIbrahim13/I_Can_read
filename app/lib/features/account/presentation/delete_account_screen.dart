import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/google_identity.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/widgets/kicker.dart';
import '../../../core/widgets/screen_header.dart';
import '../../../l10n/app_localizations.dart';
import '../application/delete_account_controller.dart';

/// Closing an account for good.
///
/// A screen rather than a dialog, and not because the app has no dialogs: this
/// is the one irreversible thing in it, and it deserves the room to say plainly
/// what goes, what stays, and that there is no undo — none of which fits in a
/// box with two buttons.
class DeleteAccountScreen extends ConsumerStatefulWidget {
  const DeleteAccountScreen({super.key});

  @override
  ConsumerState<DeleteAccountScreen> createState() =>
      _DeleteAccountScreenState();
}

class _DeleteAccountScreenState extends ConsumerState<DeleteAccountScreen> {
  final _password = TextEditingController();

  @override
  void initState() {
    super.initState();
    // The controller outlives this screen, so a reader who deleted nothing last
    // time must not open on last time's error.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(deleteAccountControllerProvider.notifier).reset();
    });
  }

  @override
  void dispose() {
    _password.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final state = ref.watch(deleteAccountControllerProvider);
    final controller = ref.read(deleteAccountControllerProvider.notifier);

    final busy = state is DeleteAccountWorking;
    final done = state is DeleteAccountDone;

    return Scaffold(
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const ScreenBackBar(),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.gutter,
                  0,
                  AppSpacing.gutter,
                  AppSpacing.x6,
                ),
                children: [
                  Text(
                    done ? l10n.deleteAccountDone : l10n.deleteAccountTitle,
                    style: theme.textTheme.headlineMedium,
                  ),
                  const SizedBox(height: AppSpacing.x3),
                  if (done)
                    Text(
                      l10n.deleteAccountDoneBody,
                      style: theme.textTheme.bodyMedium?.copyWith(height: 1.75),
                    )
                  else ...[
                    // What goes first, in body type, because it is the part the
                    // reader has to have read. What stays is reassurance, and
                    // reassurance that arrives first stops the warning landing.
                    Text(
                      l10n.deleteAccountWhatGoes,
                      style: theme.textTheme.bodyMedium?.copyWith(height: 1.75),
                    ),
                    const SizedBox(height: AppSpacing.x4),
                    Kicker(l10n.onboardingPrivacy),
                    const SizedBox(height: AppSpacing.x2),
                    Text(
                      l10n.deleteAccountWhatStays,
                      style: theme.textTheme.bodySmall?.copyWith(
                        height: 1.7,
                        color: theme.appColors.muted,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.x6),
                    TextField(
                      controller: _password,
                      enabled: !busy,
                      obscureText: true,
                      textInputAction: TextInputAction.done,
                      decoration: InputDecoration(
                        labelText: l10n.deleteAccountConfirmPassword,
                      ),
                      onSubmitted: (value) =>
                          controller.deleteWithPassword(value),
                    ),
                    if (ref.read(googleIdentityProvider).isAvailable) ...[
                      const SizedBox(height: AppSpacing.x3),
                      Text(
                        l10n.deleteAccountGoogleHint,
                        style: theme.textTheme.bodySmall?.copyWith(
                          height: 1.7,
                          color: theme.appColors.muted,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.x2),
                      Align(
                        alignment: AlignmentDirectional.centerStart,
                        child: TextButton(
                          onPressed: busy ? null : controller.deleteWithGoogle,
                          child: Text(l10n.deleteAccountConfirmGoogle),
                        ),
                      ),
                    ],
                    if (state is DeleteAccountFailed) ...[
                      const SizedBox(height: AppSpacing.x3),
                      _Problem(_message(l10n, state.error)),
                    ],
                  ],
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.gutter,
                AppSpacing.x4,
                AppSpacing.gutter,
                AppSpacing.x4,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  OutlinedButton(
                    onPressed: busy
                        ? null
                        : done
                        ? () => Navigator.of(context).pop()
                        : () => controller.deleteWithPassword(_password.text),
                    style: done
                        ? null
                        // The one destructive button in the app, and the only
                        // place the error colour is used for an action rather
                        // than for something that already went wrong.
                        : OutlinedButton.styleFrom(
                            foregroundColor: theme.colorScheme.error,
                            side: BorderSide(color: theme.colorScheme.error),
                          ),
                    child: Text(
                      busy
                          ? l10n.deleteAccountWorking
                          : done
                          ? l10n.actionDone
                          : l10n.deleteAccountSubmit,
                    ),
                  ),
                  if (!done) ...[
                    const SizedBox(height: 4),
                    // The way out, given the same weight as the way through.
                    // A reader who opened this screen to read it should not
                    // have to hunt for the back arrow.
                    TextButton(
                      onPressed: busy
                          ? null
                          : () => Navigator.of(context).pop(),
                      child: Text(l10n.deleteAccountKeepMine),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _message(AppLocalizations l10n, DeleteAccountError error) {
    return switch (error) {
      DeleteAccountError.notConfirmed => l10n.deleteAccountErrorNotConfirmed,
      DeleteAccountError.google => l10n.deleteAccountErrorGoogle,
      DeleteAccountError.offline => l10n.accountErrorOffline,
    };
  }
}

/// What went wrong, on a rule rather than in a toast — the same treatment the
/// other account screens give it.
class _Problem extends StatelessWidget {
  const _Problem(this.message);

  final String message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsetsDirectional.fromSTEB(
        AppSpacing.x3,
        AppSpacing.x2,
        AppSpacing.x3,
        AppSpacing.x2,
      ),
      decoration: BoxDecoration(
        border: BorderDirectional(
          start: BorderSide(color: theme.colorScheme.error, width: 2),
        ),
      ),
      child: Text(
        message,
        style: theme.textTheme.bodySmall?.copyWith(
          height: 1.6,
          color: theme.colorScheme.error,
        ),
      ),
    );
  }
}
