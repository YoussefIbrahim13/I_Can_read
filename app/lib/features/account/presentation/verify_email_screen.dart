import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/auth_state.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/widgets/problem_note.dart';
import '../../../core/widgets/screen_header.dart';
import '../../../l10n/app_localizations.dart';
import '../application/account_rules.dart';
import '../application/email_verification_controller.dart';

/// Proving the address on an account the reader is already signed in to.
///
/// One step rather than the reset screen's two: there is no address to type,
/// because the account already has one and the code has already gone to it.
class VerifyEmailScreen extends ConsumerStatefulWidget {
  const VerifyEmailScreen({super.key});

  @override
  ConsumerState<VerifyEmailScreen> createState() => _VerifyEmailScreenState();
}

class _VerifyEmailScreenState extends ConsumerState<VerifyEmailScreen> {
  final _code = TextEditingController();

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final session = ref.watch(authStateProvider);
    final state = ref.watch(emailVerificationControllerProvider);
    final controller = ref.read(emailVerificationControllerProvider.notifier);

    // Signed out from under the screen, or already confirmed elsewhere. Either
    // way there is nothing here to do.
    if (session == null) return const Scaffold();

    final busy = state is EmailVerificationWorking;
    final done = state is EmailVerificationDone;

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
                    done ? l10n.verifyEmailDone : l10n.verifyEmailTitle,
                    style: theme.textTheme.headlineMedium,
                  ),
                  const SizedBox(height: AppSpacing.x3),
                  Text(
                    done
                        ? l10n.verifyEmailDoneBody
                        : l10n.verifyEmailIntro(session.email),
                    style: theme.textTheme.bodyMedium?.copyWith(height: 1.75),
                  ),
                  if (!done) ...[
                    const SizedBox(height: AppSpacing.x6),
                    TextField(
                      controller: _code,
                      enabled: !busy,
                      autofocus: true,
                      keyboardType: TextInputType.number,
                      textInputAction: TextInputAction.done,
                      maxLength: passwordResetCodeLength,
                      // Digits only: the code is numeric, and a keyboard that
                      // can produce anything else only produces mistakes.
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      decoration: InputDecoration(
                        labelText: l10n.verifyEmailCode,
                        counterText: '',
                      ),
                      onSubmitted: (value) => controller.submit(value),
                    ),
                    if (state is EmailVerificationFailed) ...[
                      const SizedBox(height: AppSpacing.x3),
                      ProblemNote(_message(l10n, state.error)),
                    ],
                    if (state is EmailVerificationCodeSent) ...[
                      const SizedBox(height: AppSpacing.x3),
                      Text(
                        l10n.verifyEmailResent,
                        style: theme.textTheme.bodySmall?.copyWith(
                          height: 1.7,
                          color: theme.appColors.muted,
                        ),
                      ),
                    ],
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
                                // Cleared first: whatever is in the box was
                                // typed from the code that is about to stop
                                // working.
                                _code.clear();
                                controller.sendCode();
                              },
                        child: Text(l10n.verifyEmailResend),
                      ),
                    ),
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
                        // Left behind entirely. The prompt that led here is
                        // gone from the account screen now, so coming back
                        // would have nothing to offer.
                        controller.reset();
                        Navigator.of(context).pop();
                      }
                    : () => controller.submit(_code.text),
                child: Text(
                  busy
                      ? l10n.settingsSyncing
                      : done
                      ? l10n.resetBackToSignIn
                      : l10n.verifyEmailSubmit,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _message(AppLocalizations l10n, EmailVerificationError error) {
    return switch (error) {
      EmailVerificationError.code => l10n.verifyEmailErrorCode,
      EmailVerificationError.tooManyRequests => l10n.resetErrorTooMany,
      EmailVerificationError.offline => l10n.accountErrorOffline,
    };
  }
}
