import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_tokens.dart';
import '../../../core/widgets/screen_header.dart';
import '../../../l10n/app_localizations.dart';
import '../application/account_rules.dart';
import '../application/password_reset_controller.dart';

/// Getting back into an account whose password is gone.
///
/// Two steps on one screen, in the order they happen: the address, then the
/// code and the new password. The second step never asks for the address again
/// — it is already known, and retyping it is exactly the sort of friction a
/// locked-out reader does not need.
class PasswordResetScreen extends ConsumerStatefulWidget {
  const PasswordResetScreen({this.initialEmail, super.key});

  /// Carried over from the sign-in screen, so a reader who already typed their
  /// address does not type it twice.
  final String? initialEmail;

  @override
  ConsumerState<PasswordResetScreen> createState() =>
      _PasswordResetScreenState();
}

class _PasswordResetScreenState extends ConsumerState<PasswordResetScreen> {
  late final _email = TextEditingController(text: widget.initialEmail ?? '');
  final _code = TextEditingController();
  final _password = TextEditingController();

  @override
  void dispose() {
    _email.dispose();
    _code.dispose();
    _password.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final state = ref.watch(passwordResetControllerProvider);
    final controller = ref.read(passwordResetControllerProvider.notifier);

    final busy = state is PasswordResetWorking;
    // Which step is on screen. A failure on the code step keeps the reader
    // there rather than dropping them back to the address they already gave.
    final onCodeStep =
        state is PasswordResetCodeSent ||
        (state is PasswordResetFailed && state.email != null);
    final done = state is PasswordResetDone;

    final sentTo = switch (state) {
      PasswordResetCodeSent(:final email) => email,
      PasswordResetFailed(email: final email?) => email,
      _ => null,
    };

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
                    done ? l10n.resetDone : l10n.resetTitle,
                    style: theme.textTheme.headlineMedium,
                  ),
                  const SizedBox(height: AppSpacing.x3),
                  Text(
                    done
                        ? l10n.resetDoneBody
                        : onCodeStep
                        ? l10n.resetCodeSent(sentTo!)
                        : l10n.resetIntro,
                    style: theme.textTheme.bodyMedium?.copyWith(height: 1.75),
                  ),
                  if (!done) ...[
                    const SizedBox(height: AppSpacing.x6),
                    if (!onCodeStep)
                      TextField(
                        controller: _email,
                        enabled: !busy,
                        autofocus: widget.initialEmail == null,
                        autofillHints: const [AutofillHints.email],
                        keyboardType: TextInputType.emailAddress,
                        textInputAction: TextInputAction.done,
                        autocorrect: false,
                        decoration: InputDecoration(
                          labelText: l10n.accountEmail,
                        ),
                        onSubmitted: (value) => controller.requestCode(value),
                      )
                    else ...[
                      TextField(
                        controller: _code,
                        enabled: !busy,
                        autofocus: true,
                        keyboardType: TextInputType.number,
                        textInputAction: TextInputAction.next,
                        maxLength: passwordResetCodeLength,
                        // Digits only: the code is numeric, and a keyboard that
                        // can produce anything else only produces mistakes.
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                        ],
                        decoration: InputDecoration(
                          labelText: l10n.resetCode,
                          counterText: '',
                        ),
                      ),
                      const SizedBox(height: AppSpacing.x3),
                      TextField(
                        controller: _password,
                        enabled: !busy,
                        obscureText: true,
                        autofillHints: const [AutofillHints.newPassword],
                        textInputAction: TextInputAction.done,
                        decoration: InputDecoration(
                          labelText: l10n.resetNewPassword,
                          helperText: l10n.accountPasswordRule,
                        ),
                        onSubmitted: (_) => _submit(controller),
                      ),
                    ],
                    if (state is PasswordResetFailed) ...[
                      const SizedBox(height: AppSpacing.x3),
                      _Problem(_message(l10n, state.error)),
                    ],
                    if (onCodeStep) ...[
                      const SizedBox(height: AppSpacing.x4),
                      Text(
                        l10n.resetSpamHint,
                        style: theme.textTheme.bodySmall?.copyWith(
                          height: 1.7,
                          color: theme.appColors.muted,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.x2),
                      Align(
                        alignment: AlignmentDirectional.centerStart,
                        child: TextButton(
                          onPressed: busy
                              ? null
                              : () {
                                  _code.clear();
                                  controller.requestCode(sentTo!);
                                },
                          child: Text(l10n.resetResend),
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
                        // The screen is left behind entirely: the reader now
                        // has a password and the sign-in screen is where it is
                        // used. Coming back here would have nothing to offer.
                        controller.reset();
                        Navigator.of(context).pop();
                      }
                    : onCodeStep
                    ? () => _submit(controller)
                    : () => controller.requestCode(_email.text),
                child: Text(
                  busy
                      ? l10n.settingsSyncing
                      : done
                      ? l10n.resetBackToSignIn
                      : onCodeStep
                      ? l10n.resetSubmit
                      : l10n.resetSendCode,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _submit(PasswordResetController controller) {
    controller.submitNewPassword(code: _code.text, newPassword: _password.text);
  }

  String _message(AppLocalizations l10n, PasswordResetError error) {
    return switch (error) {
      PasswordResetError.email => l10n.accountErrorEmail,
      PasswordResetError.code => l10n.resetErrorCode,
      PasswordResetError.passwordTooShort => l10n.accountErrorPasswordShort,
      PasswordResetError.tooManyRequests => l10n.resetErrorTooMany,
      PasswordResetError.offline => l10n.accountErrorOffline,
    };
  }
}

/// What went wrong, on a rule rather than in a toast — the same treatment the
/// account screen gives it, for the same reason: the fields it is about are
/// still on screen.
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
