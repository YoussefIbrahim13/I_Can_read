import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/auth/auth_state.dart';
import '../../../core/auth/google_identity.dart';
import '../../../core/sync/sync_engine.dart';
import '../../../core/sync/sync_status.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/widgets/kicker.dart';
import '../../../core/widgets/problem_note.dart';
import '../../../l10n/app_localizations.dart';
import '../application/account_controller.dart';
import '../application/account_profile_controller.dart';

/// The signed-in half of the account screen: who is signed in, whether
/// anything is still waiting to be sent, and everything the reader can do to
/// the account itself.
///
/// Redesign v2 moved this off Settings. It used to sit inline under a kicker,
/// which put a sync status and a "delete my account" between the theme switch
/// and the backup buttons — three unrelated weights of decision in one list.
/// Settings now carries a row that states the account in one line and leads
/// here.
class AccountStatus extends ConsumerStatefulWidget {
  const AccountStatus({super.key});

  @override
  ConsumerState<AccountStatus> createState() => _AccountStatusState();
}

class _AccountStatusState extends ConsumerState<AccountStatus> {
  TextEditingController? _name;

  @override
  void dispose() {
    _name?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final session = ref.watch(authStateProvider);
    if (session == null) return const SizedBox.shrink();

    // Built against the stored name the first time, and then left alone: it is
    // rebuilt on every keystroke from here on, and re-seeding it would move the
    // caret back to the start of whatever the reader is typing.
    final name = _name ??= TextEditingController(text: session.displayName ?? '');

    final status = ref.watch(syncControllerProvider);
    final pending = ref.watch(pendingSyncCountProvider).value ?? 0;
    final profile = ref.watch(accountProfileControllerProvider);
    final busy = profile is AccountProfileWorking;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          l10n.accountWelcome(session.email),
          style: theme.textTheme.titleMedium?.copyWith(fontSize: 16.5),
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

        // Before everything else, because it is the one thing here the reader
        // has not already decided to do — and because what it unlocks (a
        // password reset that can reach them, and Google on this account) is
        // further down this very list.
        if (!session.emailVerified) ...[
          const SizedBox(height: AppSpacing.x4),
          _VerifyEmailPrompt(),
        ],

        const SizedBox(height: AppSpacing.x4),
        FilledButton(
          onPressed: status is SyncInProgress
              ? null
              : () => ref.read(syncControllerProvider.notifier).syncNow(),
          child: Text(l10n.settingsSyncNow),
        ),
        const SizedBox(height: AppSpacing.x2),
        OutlinedButton(
          onPressed: () =>
              ref.read(accountControllerProvider.notifier).signOut(),
          child: Text(l10n.settingsSignOut),
        ),

        // No kicker above this one: the field's own label already says "your
        // name", and a section heading repeating it word for word would be the
        // same two words twice.
        const SizedBox(height: AppSpacing.x6),
        TextField(
          controller: name,
          enabled: !busy,
          textInputAction: TextInputAction.done,
          decoration: InputDecoration(
            labelText: l10n.manageName,
            helperText: l10n.manageNameHint,
          ),
          onSubmitted: (value) =>
              ref.read(accountProfileControllerProvider.notifier).saveName(value),
        ),
        const SizedBox(height: AppSpacing.x2),
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: TextButton(
            onPressed: busy
                ? null
                : () => ref
                      .read(accountProfileControllerProvider.notifier)
                      .saveName(name.text),
            child: Text(l10n.manageSaveName),
          ),
        ),
        ..._note(l10n, theme, profile, AccountSubject.name),

        const SizedBox(height: AppSpacing.x4),
        Kicker(l10n.manageSecurity),
        const SizedBox(height: AppSpacing.x2),
        OutlinedButton(
          onPressed: busy ? null : () => context.push('/account/password'),
          child: Text(
            session.hasPassword
                ? l10n.manageChangePassword
                : l10n.manageSetPassword,
          ),
        ),
        if (!session.hasPassword) ...[
          const SizedBox(height: AppSpacing.x2),
          Text(
            l10n.manageSetPasswordHint,
            style: theme.textTheme.bodySmall?.copyWith(
              height: 1.7,
              color: theme.appColors.muted,
            ),
          ),
        ],

        // Only offered where Google is actually available. On a device without
        // Play services the button would lead nowhere every time.
        if (ref.read(googleIdentityProvider).isAvailable) ...[
          const SizedBox(height: AppSpacing.x2),
          if (session.googleLinked)
            OutlinedButton(
              onPressed: busy ? null : () => _confirmUnlink(context, l10n),
              child: Text(l10n.manageDisconnectGoogle),
            )
          else
            OutlinedButton(
              onPressed: busy
                  ? null
                  : () => ref
                        .read(accountProfileControllerProvider.notifier)
                        .linkGoogle(),
              child: Text(l10n.manageConnectGoogle),
            ),
        ],
        ..._note(l10n, theme, profile, AccountSubject.google),

        const SizedBox(height: AppSpacing.x2),
        OutlinedButton(
          onPressed: () => context.push('/account/sessions'),
          child: Text(l10n.manageDevices),
        ),

        // Last, and set apart from signing out: the two read as neighbours if
        // they sit together, and one of them cannot be undone.
        const SizedBox(height: AppSpacing.x6 - 4),
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

  /// How the last change to [subject] went, under the control that made it.
  ///
  /// Empty for any other subject, so a failure to link Google does not appear
  /// under the name field and vice versa.
  List<Widget> _note(
    AppLocalizations l10n,
    ThemeData theme,
    AccountProfileState profile,
    AccountSubject subject,
  ) {
    return switch (profile) {
      AccountProfileFailed(:final error, subject: final of) when of == subject =>
        [
          const SizedBox(height: AppSpacing.x3),
          ProblemNote(_message(l10n, error)),
        ],
      AccountProfileSaved(subject: final of) when of == subject => [
        const SizedBox(height: AppSpacing.x3),
        Text(
          l10n.manageNameSaved,
          style: theme.textTheme.bodySmall?.copyWith(
            height: 1.6,
            color: theme.appColors.muted,
          ),
        ),
      ],
      _ => const [],
    };
  }

  /// Asks for the password before taking Google off.
  ///
  /// A dialog rather than a screen: it is one field, and the thing it is about
  /// — the button that was just pressed — should still be visible behind it.
  Future<void> _confirmUnlink(BuildContext context, AppLocalizations l10n) async {
    final password = TextEditingController();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.manageUnlinkTitle),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(l10n.manageUnlinkBody),
            const SizedBox(height: AppSpacing.x3),
            TextField(
              controller: password,
              autofocus: true,
              obscureText: true,
              autofillHints: const [AutofillHints.password],
              decoration: InputDecoration(labelText: l10n.accountPassword),
              onSubmitted: (_) => Navigator.of(dialogContext).pop(true),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(l10n.commonCancel),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(l10n.manageUnlinkConfirm),
          ),
        ],
      ),
    );

    if (confirmed ?? false) {
      await ref
          .read(accountProfileControllerProvider.notifier)
          .unlinkGoogle(password.text);
    }

    password.dispose();
  }

  String _message(AppLocalizations l10n, AccountProfileError error) {
    return switch (error) {
      AccountProfileError.emailNotVerified => l10n.manageErrorEmailNotVerified,
      AccountProfileError.googleEmailMismatch =>
        l10n.manageErrorGoogleEmailMismatch,
      AccountProfileError.googleAlreadyInUse =>
        l10n.manageErrorGoogleAlreadyInUse,
      AccountProfileError.wouldLockOut => l10n.manageErrorWouldLockOut,
      AccountProfileError.notConfirmed => l10n.manageErrorNotConfirmed,
      AccountProfileError.google => l10n.manageErrorGoogle,
      AccountProfileError.tooManyRequests => l10n.manageErrorTooMany,
      AccountProfileError.offline => l10n.manageErrorOffline,
    };
  }
}

/// The nudge to confirm an address that has not been confirmed.
class _VerifyEmailPrompt extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsetsDirectional.fromSTEB(
        AppSpacing.x3,
        AppSpacing.x3,
        AppSpacing.x3,
        AppSpacing.x2,
      ),
      decoration: BoxDecoration(
        border: BorderDirectional(
          start: BorderSide(color: theme.appColors.hairline, width: 2),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l10n.verifyEmailPrompt, style: theme.textTheme.titleSmall),
          const SizedBox(height: AppSpacing.x1),
          Text(
            l10n.verifyEmailPromptBody,
            style: theme.textTheme.bodySmall?.copyWith(
              height: 1.7,
              color: theme.appColors.muted,
            ),
          ),
          const SizedBox(height: AppSpacing.x1),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: TextButton(
              onPressed: () => context.push('/account/verify-email'),
              child: Text(l10n.verifyEmailAction),
            ),
          ),
        ],
      ),
    );
  }
}
