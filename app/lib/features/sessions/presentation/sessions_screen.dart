import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/db/app_database.dart';
import '../../../core/notifications/reminder_channel.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/widgets/figure.dart';
import '../../../core/widgets/progress_shapes.dart';
import '../../../core/widgets/screen_header.dart';
import '../../../core/widgets/stepper_field.dart';
import '../../../l10n/app_localizations.dart';
import '../../plan/application/plan_providers.dart';
import '../application/sessions_providers.dart';
import '../domain/session_plan.dart';

/// Screen 7 — split the daily portion across times of day.
///
/// The split is drawn before it is stated: the bar at the top is weighted by
/// each session's share, so two very different sessions look different before
/// the reader reads a single number.
class SessionsScreen extends ConsumerWidget {
  const SessionsScreen({required this.bookId, super.key});

  final String bookId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final plan = ref.watch(activePlanProvider(bookId)).value;
    final sessions = plan == null
        ? null
        : ref.watch(planSessionsProvider(plan.id)).value;

    return Scaffold(
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ScreenBackBar(title: l10n.sessionsTitle),
            const Divider(),
            Expanded(
              child: plan == null || sessions == null
                  ? const SizedBox.shrink()
                  : _SessionsForm(plan: plan, stored: sessions),
            ),
          ],
        ),
      ),
    );
  }
}

class _SessionsForm extends ConsumerStatefulWidget {
  const _SessionsForm({required this.plan, required this.stored});

  final ReadingPlan plan;
  final List<ReadingSession> stored;

  @override
  ConsumerState<_SessionsForm> createState() => _SessionsFormState();
}

class _SessionsFormState extends ConsumerState<_SessionsForm> {
  late SessionPlan _split = SessionPlan.restore(
    pagesPerDay: widget.plan.pagesPerDay,
    slots: [
      for (final session in widget.stored)
        SessionSlot(
          minutes: session.timeOfDayMinutes,
          pages: session.pagesShare,
        ),
    ],
  );
  var _saving = false;

  void _edit(SessionPlan next) => setState(() => _split = next);

  Future<void> _pickTime(int index) async {
    final slot = _split.slots[index];
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: slot.hour, minute: slot.minute),
    );
    if (picked != null) {
      _edit(_split.withTimeAt(index, picked.hour * 60 + picked.minute));
    }
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      await ref
          .read(sessionWriterProvider)
          .save(planId: widget.plan.id, plan: _split);
      // Asked here and nowhere else: the reader has just set times to be
      // reminded at, so the system prompt answers a question they raised
      // rather than interrupting their first launch.
      await ref.read(reminderChannelProvider).requestPermission();
    } finally {
      if (mounted) setState(() => _saving = false);
    }

    if (!mounted) return;
    final navigator = Navigator.of(context);
    if (navigator.canPop()) navigator.pop();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.gutter,
            0,
            AppSpacing.gutter,
            AppSpacing.x4,
          ),
          child: Text(
            l10n.sessionsHintWithPages(_split.pagesPerDay),
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        _SplitPreview(split: _split),
        const Divider(),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.gutter,
              AppSpacing.x1,
              AppSpacing.gutter,
              AppSpacing.x6,
            ),
            children: [
              for (final (index, slot) in _split.slots.indexed)
                _SessionRow(
                  slot: slot,
                  // A single session holds the whole quota by definition, so
                  // its stepper has nothing to trade against.
                  canEditPages: _split.canRemove,
                  maxPages: _split.pagesPerDay,
                  onPages: (pages) => _edit(_split.withPagesAt(index, pages)),
                  onTime: () => _pickTime(index),
                  onRemove: _split.canRemove
                      ? () => _edit(_split.removedAt(index))
                      : null,
                ),
              if (_split.canAdd)
                _AddSession(onTap: () => _edit(_split.added())),
              const SizedBox(height: AppSpacing.x4),
              if (_split.hasEmptySession) ...[
                _Note(l10n.sessionsMorePagesThanSessions),
                const SizedBox(height: AppSpacing.x3),
              ],
              _Note(l10n.sessionsNote(_split.pagesPerDay)),
            ],
          ),
        ),
        const Divider(),
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.gutter,
            AppSpacing.x3 - 2,
            AppSpacing.gutter,
            AppSpacing.x4,
          ),
          child: OutlinedButton(
            onPressed: _saving ? null : _save,
            child: Text(l10n.planStart),
          ),
        ),
      ],
    );
  }
}

/// The day as one bar, one segment per session, weighted by its share.
class _SplitPreview extends StatelessWidget {
  const _SplitPreview({required this.split});

  final SessionPlan split;

  static String _period(AppLocalizations l10n, SessionPeriod period) =>
      switch (period) {
        SessionPeriod.morning => l10n.sessionPeriodMorning,
        SessionPeriod.afternoon => l10n.sessionPeriodAfternoon,
        SessionPeriod.evening => l10n.sessionPeriodEvening,
        SessionPeriod.night => l10n.sessionPeriodNight,
      };

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.gutter,
        0,
        AppSpacing.gutter,
        AppSpacing.x4,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Today's scope, drawn by the widget that owns it. Nothing is done
          // yet — this is the shape of the day, not progress through it.
          TodayBar(
            height: 6,
            segments: [
              for (final slot in split.slots)
                TodaySegment(pages: slot.pages, done: false),
            ],
          ),
          const SizedBox(height: AppSpacing.x2 - 1),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              // Only the ends are labelled: a caption per segment turns into a
              // wall of text at four sessions, and the bar already carries the
              // middle.
              for (final slot in [
                split.slots.first,
                if (split.slots.length > 1) split.slots.last,
              ])
                Flexible(
                  child: Text(
                    l10n.sessionsSplitLabel(
                      slot.pages,
                      _period(l10n, slot.period),
                    ),
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontSize: 11,
                      color: theme.appColors.muted,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SessionRow extends StatelessWidget {
  const _SessionRow({
    required this.slot,
    required this.canEditPages,
    required this.maxPages,
    required this.onPages,
    required this.onTime,
    required this.onRemove,
  });

  final SessionSlot slot;
  final bool canEditPages;

  /// The day's whole portion: one session may hold all of it, never more.
  final int maxPages;
  final ValueChanged<int> onPages;
  final VoidCallback onTime;
  final VoidCallback? onRemove;

  static String _clock(SessionSlot slot) =>
      '${slot.hour.toString().padLeft(2, '0')}:'
      '${slot.minute.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);

    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: theme.appColors.hairline)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.x4 - 3),
        child: Row(
          children: [
            Expanded(
              child: Semantics(
                button: true,
                label: l10n.sessionChangeTime,
                child: InkWell(
                  onTap: onTime,
                  borderRadius: BorderRadius.circular(AppSpacing.radius),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // The time is the row's subject, so it is the only
                        // thing here set as a standing figure.
                        Figure(_clock(slot), size: 26),
                        const SizedBox(height: 5),
                        Text(
                          _SplitPreview._period(l10n, slot.period),
                          style: theme.textTheme.bodySmall?.copyWith(
                            fontSize: 11.5,
                            color: theme.appColors.muted,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.x3),
            StepperField(
              value: slot.pages,
              onChanged: canEditPages ? onPages : (_) {},
              min: canEditPages ? 0 : slot.pages,
              max: canEditPages ? maxPages : slot.pages,
              decreaseLabel: l10n.sessionPagesFewer,
              increaseLabel: l10n.sessionPagesMore,
            ),
            IconButton(
              onPressed: onRemove,
              icon: const Icon(Icons.close, size: 16),
              color: theme.appColors.muted,
              tooltip: l10n.sessionRemove,
              constraints: const BoxConstraints.tightFor(
                width: AppSpacing.minTapTarget,
                height: AppSpacing.minTapTarget,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AddSession extends StatelessWidget {
  const _AddSession({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);

    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: theme.appColors.hairline)),
      ),
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.x4),
          child: Row(
            children: [
              Icon(Icons.add, size: 16, color: theme.colorScheme.primary),
              const SizedBox(width: AppSpacing.x2 + 1),
              Text(
                l10n.sessionAdd,
                style: theme.textTheme.labelMedium?.copyWith(
                  fontSize: 14,
                  color: theme.colorScheme.primary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A paragraph set off by a gold rule on its leading edge — the screen's
/// standing explanation, not a warning.
class _Note extends StatelessWidget {
  const _Note(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsetsDirectional.only(start: AppSpacing.x3 - 2),
      decoration: BoxDecoration(
        border: BorderDirectional(
          start: BorderSide(color: theme.appColors.accentStroke),
        ),
      ),
      child: Text(
        text,
        style: theme.textTheme.bodySmall?.copyWith(
          fontSize: 12.5,
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}
