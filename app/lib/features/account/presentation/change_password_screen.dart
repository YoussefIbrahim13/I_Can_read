import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/auth_state.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/widgets/problem_note.dart';
import '../../../core/widgets/screen_header.dart';
import '../../../l10n/app_localizations.dart';
import '../application/change_password_controller.dart';

/// Setting a password — the first one, or a new one.
///
/// One screen for both. The only visible difference is the current-password
/// field, which an account that signs in with Google has nothing to put in:
/// there, Google itself is the proof and comes up when the button is pressed.
class ChangePasswordScreen extends ConsumerStatefulWidget {
  const ChangePasswordScreen({super.key});

  @override
  ConsumerState<ChangePasswordScreen> createState() =>
      _ChangePasswordScreenState();
}

class _ChangePasswordScreenState extends ConsumerState<ChangePasswordScreen> {
  final _current = TextEditingController();
  final _fresh = TextEditingController();

  @override
  void dispose() {
    _current.dispose();
    _fresh.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final session = ref.watch(authStateProvider);
    final state = ref.watch(changePasswordControllerProvider);
    final controller = ref.read(changePasswordControllerProvider.notifier);

    if (session == null) return const Scaffold();

    // Which of the two this is. Taken from the account rather than from a route
    // argument, so a reader who sets their first password on another device
    // finds this screen asking the right question when they come back to it.
    final setting = !session.hasPassword;
    final busy = state is ChangePasswordWorking;
    final done = state is ChangePasswordDone;

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
                    done
                        ? l10n.changePasswordDone
                        : setting
                        ? l10n.setPasswordTitle
                        : l10n.changePasswordTitle,
                    style: theme.textTheme.headlineMedium,
                  ),
                  const SizedBox(height: AppSpacing.x3),
                  Text(
                    done
                        ? l10n.changePasswordDoneBody
                        : setting
                        ? l10n.setPasswordIntro
                        : l10n.changePasswordIntro,
                    style: theme.textTheme.bodyMedium?.copyWith(height: 1.75),
                  ),
                  if (!done) ...[
                    const SizedBox(height: AppSpacing.x6),
                    if (!setting) ...[
                      TextField(
                        controller: _current,
                        enabled: !busy,
                        autofocus: true,
                        obscureText: true,
                        autofillHints: const [AutofillHints.password],
                        textInputAction: TextInputAction.next,
                        decoration: InputDecoration(
                          labelText: l10n.changePasswordCurrent,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.x3),
                    ],
                    TextField(
                      controller: _fresh,
                      enabled: !busy,
                      autofocus: setting,
                      obscureText: true,
                      autofillHints: const [AutofillHints.newPassword],
                      textInputAction: TextInputAction.done,
                      decoration: InputDecoration(
                        labelText: l10n.changePasswordNew,
                        helperText: l10n.accountPasswordRule,
                      ),
                      onSubmitted: (_) => _submit(controller),
                    ),
                    if (state is ChangePasswordFailed) ...[
                      const SizedBox(height: AppSpacing.x3),
                      ProblemNote(_message(l10n, state.error)),
                    ],
                    if (setting) ...[
                      const SizedBox(height: AppSpacing.x4),
                      Text(
                        l10n.changePasswordGoogleHint,
                        style: theme.textTheme.bodySmall?.copyWith(
                          height: 1.7,
                          color: theme.appColors.muted,
                        ),
                      ),
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
              child: OutlinedButton(
                onPressed: busy
                    ? null
                    : done
                    ? () {
                        controller.reset();
                        Navigator.of(context).pop();
                      }
                    : () => _submit(controller),
                child: Text(
                  busy
                      ? l10n.settingsSyncing
                      : done
                      ? l10n.resetBackToSignIn
                      : setting
                      ? l10n.setPasswordSubmit
                      : l10n.changePasswordSubmit,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _submit(ChangePasswordController controller) {
    controller.submit(
      currentPassword: _current.text,
      newPassword: _fresh.text,
    );
  }

  String _message(AppLocalizations l10n, ChangePasswordError error) {
    return switch (error) {
      ChangePasswordError.notConfirmed => l10n.manageErrorNotConfirmed,
      ChangePasswordError.passwordTooShort => l10n.accountErrorPasswordShort,
      ChangePasswordError.unchanged => l10n.changePasswordErrorUnchanged,
      ChangePasswordError.google => l10n.manageErrorGoogle,
      ChangePasswordError.tooManyRequests => l10n.manageErrorTooMany,
      ChangePasswordError.offline => l10n.manageErrorOffline,
    };
  }
}
