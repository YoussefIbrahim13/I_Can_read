import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/account_api.dart';
import '../../../core/format/app_dates.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/widgets/kicker.dart';
import '../../../core/widgets/problem_note.dart';
import '../../../core/widgets/screen_header.dart';
import '../../../l10n/app_localizations.dart';
import '../application/sessions_controller.dart';

/// Every device signed in to the account, and the way to throw one out.
///
/// Named for devices rather than for sessions, which is what the server calls
/// them: the reader recognises a phone, not a refresh token. The app already
/// has a `SessionsScreen` — the one that splits a daily portion across times of
/// day — and two screens by that name would be a trap for whoever edits the
/// wrong one.
class DevicesScreen extends ConsumerWidget {
  const DevicesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final sessions = ref.watch(sessionsControllerProvider);
    final controller = ref.read(sessionsControllerProvider.notifier);

    return Scaffold(
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ScreenBackBar(title: l10n.sessionsTitle),
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
                    l10n.sessionsIntro,
                    style: theme.textTheme.bodyMedium?.copyWith(height: 1.75),
                  ),
                  const SizedBox(height: AppSpacing.x6),
                  ...switch (sessions) {
                    AsyncData(:final value) => _list(
                      context,
                      l10n,
                      theme,
                      value,
                      controller,
                      // Only while the list is settled. Acting on a stale list
                      // would sign out whichever device happens to hold the id
                      // now, which is not the one the reader tapped.
                      busy: sessions.isLoading,
                    ),
                    AsyncError() => [
                      ProblemNote(l10n.sessionsFailed),
                      const SizedBox(height: AppSpacing.x3),
                      OutlinedButton(
                        onPressed: controller.reload,
                        child: Text(l10n.sessionsRetry),
                      ),
                    ],
                    _ => [
                      Text(
                        l10n.settingsSyncing,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.appColors.muted,
                        ),
                      ),
                    ],
                  },
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _list(
    BuildContext context,
    AppLocalizations l10n,
    ThemeData theme,
    List<AccountSession> sessions,
    SessionsController controller, {
    required bool busy,
  }) {
    final others = sessions.where((session) => !session.isCurrent).toList();

    return [
      for (final session in sessions) ...[
        _SessionRow(
          session: session,
          onSignOut: busy || session.isCurrent
              ? null
              // Signing this device out is what the Sign out button on the
              // account screen is for, and it has the rest of the tidying to do
              // — the outbox, the Google account, the stored tokens. Offering
              // it here too would be a second way to do it that does less.
              : () => controller.revoke(session.id),
        ),
        const SizedBox(height: AppSpacing.x4),
      ],
      if (others.isEmpty)
        Text(
          l10n.sessionsOnlyThisOne,
          style: theme.textTheme.bodySmall?.copyWith(
            height: 1.7,
            color: theme.appColors.muted,
          ),
        )
      else
        OutlinedButton(
          onPressed: busy ? null : controller.revokeOthers,
          child: Text(l10n.sessionsSignOutOthers),
        ),
    ];
  }
}

/// One device: when it signed in, where from, and whether it is this one.
class _SessionRow extends StatelessWidget {
  const _SessionRow({required this.session, this.onSignOut});

  final AccountSession session;
  final VoidCallback? onSignOut;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);

    // The user agent, verbatim and long. Trimmed to something a person can take
    // in at a glance rather than parsed into a device name: parsing it would be
    // guessing at a header the caller chose, and guessing wrong in a list whose
    // whole job is "do you recognise this?" is worse than saying less.
    final device = session.device;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (session.isCurrent) ...[
                Kicker(l10n.sessionsCurrent),
                const SizedBox(height: AppSpacing.x1),
              ],
              Text(
                l10n.sessionsSignedInOn(
                  AppDates.full(session.createdAt.toLocal(), Localizations.localeOf(context)),
                ),
                style: theme.textTheme.bodyMedium,
              ),
              if (device != null || session.ipAddress != null) ...[
                const SizedBox(height: AppSpacing.x1),
                Text(
                  [?device, ?session.ipAddress].join(' · '),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    height: 1.6,
                    color: theme.appColors.muted,
                  ),
                ),
              ],
            ],
          ),
        ),
        if (!session.isCurrent)
          TextButton(
            onPressed: onSignOut,
            style: TextButton.styleFrom(foregroundColor: theme.appColors.muted),
            child: Text(l10n.sessionsSignOutOne),
          ),
      ],
    );
  }
}
