import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/google_identity.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/widgets/kicker.dart';
import '../../../core/widgets/screen_header.dart';
import '../../../core/widgets/segmented_control.dart';
import '../../../l10n/app_localizations.dart';
import '../application/account_controller.dart';

/// Signing in and creating an account, on one screen.
///
/// Two screens would be the same two fields twice, and the reader who guesses
/// wrong — an account they already have, or one they do not — would have to go
/// back and find the other door. Here the wrong guess costs a tap on a control
/// that is already in front of them, and the fields keep what was typed.
class AccountScreen extends ConsumerStatefulWidget {
  const AccountScreen({super.key});

  @override
  ConsumerState<AccountScreen> createState() => _AccountScreenState();
}

class _AccountScreenState extends ConsumerState<AccountScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _name = TextEditingController();
  var _mode = AccountMode.signIn;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _name.dispose();
    super.dispose();
  }

  void _submit() {
    ref
        .read(accountControllerProvider.notifier)
        .submit(
          mode: _mode,
          email: _email.text,
          password: _password.text,
          displayName: _mode == AccountMode.register ? _name.text : null,
        );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final state = ref.watch(accountControllerProvider);

    // The way out is the reader arriving where they were going, so it is the
    // state change that closes the screen rather than the button that started
    // it — a sign-in that lands while the app is backgrounded still finishes.
    ref.listen<AccountState>(accountControllerProvider, (previous, next) {
      if (next is AccountSignedIn && context.mounted) Navigator.of(context).pop();
    });

    final busy = state is AccountWorking || state is AccountAdopting;

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
                    l10n.accountTitle,
                    style: theme.textTheme.headlineMedium,
                  ),
                  const SizedBox(height: AppSpacing.x3),
                  Text(
                    l10n.accountIntro,
                    style: theme.textTheme.bodyMedium?.copyWith(height: 1.75),
                  ),
                  const SizedBox(height: AppSpacing.x6),
                  AppSegmentedControl<AccountMode>(
                    value: _mode,
                    // Guarded rather than disabled: the control has no greyed
                    // state, and going flat mid-request would read as broken.
                    onChanged: (mode) {
                      if (!busy) setState(() => _mode = mode);
                    },
                    segments: [
                      AppSegment(
                        value: AccountMode.signIn,
                        label: l10n.accountModeSignIn,
                      ),
                      AppSegment(
                        value: AccountMode.register,
                        label: l10n.accountModeRegister,
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.x4),
                  // Above the fields, because it is the shorter road: a reader
                  // who has a Google account never has to read past it, and one
                  // who does not loses only the height of a button.
                  if (ref.read(googleIdentityProvider).isAvailable) ...[
                    OutlinedButton(
                      onPressed: busy
                          ? null
                          : () => ref
                                .read(accountControllerProvider.notifier)
                                .signInWithGoogle(),
                      child: Text(l10n.accountGoogle),
                    ),
                    const SizedBox(height: AppSpacing.x3),
                    _Or(l10n.accountOr),
                    const SizedBox(height: AppSpacing.x3),
                  ],
                  TextField(
                    controller: _email,
                    enabled: !busy,
                    autofillHints: const [AutofillHints.email],
                    keyboardType: TextInputType.emailAddress,
                    textInputAction: TextInputAction.next,
                    autocorrect: false,
                    decoration: InputDecoration(labelText: l10n.accountEmail),
                  ),
                  const SizedBox(height: AppSpacing.x3),
                  TextField(
                    controller: _password,
                    enabled: !busy,
                    obscureText: true,
                    autofillHints: const [AutofillHints.password],
                    textInputAction: _mode == AccountMode.register
                        ? TextInputAction.next
                        : TextInputAction.done,
                    decoration: InputDecoration(
                      labelText: l10n.accountPassword,
                      // Shown while creating an account, where it is a rule the
                      // reader is about to be held to; on the way back in it
                      // would only be advice about a password they already have.
                      helperText: _mode == AccountMode.register
                          ? l10n.accountPasswordRule
                          : null,
                    ),
                    onSubmitted: (_) {
                      if (_mode == AccountMode.signIn) _submit();
                    },
                  ),
                  if (_mode == AccountMode.register) ...[
                    const SizedBox(height: AppSpacing.x3),
                    TextField(
                      controller: _name,
                      enabled: !busy,
                      textInputAction: TextInputAction.done,
                      decoration: InputDecoration(labelText: l10n.accountName),
                      onSubmitted: (_) => _submit(),
                    ),
                  ],
                  if (state is AccountFailed) ...[
                    const SizedBox(height: AppSpacing.x3),
                    _Problem(_message(l10n, state.error)),
                  ],
                  const SizedBox(height: AppSpacing.x6),
                  // The promise is repeated here rather than assumed from the
                  // welcome screen: this is the one screen where the reader is
                  // being asked to send something, so it is the one screen
                  // where "not the file" has to be said again.
                  Kicker(l10n.onboardingPrivacy),
                  const SizedBox(height: AppSpacing.x2),
                  Text(
                    l10n.accountPrivacy,
                    style: theme.textTheme.bodySmall?.copyWith(
                      height: 1.7,
                      color: theme.appColors.muted,
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              // Generous above, because the list scrolls right up to this edge
              // and the button is pinned below it. With the keyboard open the
              // last field ends flush against the button, and at the old x2 the
              // two read as one clipped control rather than two separate ones.
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.gutter,
                AppSpacing.x4,
                AppSpacing.gutter,
                AppSpacing.x4,
              ),
              child: OutlinedButton(
                onPressed: busy ? null : _submit,
                child: Text(
                  switch (state) {
                    AccountAdopting() => l10n.accountAdopting,
                    AccountWorking() => l10n.settingsSyncing,
                    _ => switch (_mode) {
                      AccountMode.signIn => l10n.accountSubmitSignIn,
                      AccountMode.register => l10n.accountSubmitRegister,
                    },
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _message(AppLocalizations l10n, AccountError error) {
    return switch (error) {
      AccountError.email => l10n.accountErrorEmail,
      AccountError.passwordTooShort => l10n.accountErrorPasswordShort,
      AccountError.emailTaken => l10n.accountErrorEmailTaken,
      AccountError.credentials => l10n.accountErrorCredentials,
      AccountError.offline => l10n.accountErrorOffline,
      AccountError.google => l10n.accountErrorGoogle,
      AccountError.googleEmailIsPasswordAccount =>
        l10n.accountErrorGoogleEmailTaken,
    };
  }
}

/// A hairline with a word sitting in it, separating the two ways in.
///
/// A plain gap would read as "and also", which is wrong — these are two doors
/// to the same room, and the reader only needs one.
class _Or extends StatelessWidget {
  const _Or(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final rule = Expanded(child: Divider(color: theme.appColors.hairline));

    return Row(
      children: [
        rule,
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.x3),
          child: Text(
            label,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.appColors.muted,
            ),
          ),
        ),
        rule,
      ],
    );
  }
}

/// What went wrong, on a rule rather than in a toast.
///
/// A snack bar would slide away while the reader is still reading it, and the
/// thing it is talking about — the two fields above — stays on screen.
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
