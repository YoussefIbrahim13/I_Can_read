import 'package:flutter/material.dart';

import '../theme/app_tokens.dart';
import 'kicker.dart';

/// The masthead every top-level tab opens with: a gold kicker, a large title
/// in the screen's own type, and a full-bleed hairline under both.
///
/// This replaces `AppBar` on the tab screens. An `AppBar` centres a small
/// title in a bar of its own height, which is the wrong emphasis — the title
/// here is editorial, part of the page rather than chrome above it.
class ScreenHeader extends StatelessWidget {
  const ScreenHeader({
    required this.title,
    this.kicker,
    this.trailing,
    this.divider = true,
    super.key,
  });

  final String title;

  /// The date on Today, the book count on Library, the window on Stats.
  final String? kicker;

  /// Baseline-aligned with the title — the "add a book" action, typically.
  final Widget? trailing;

  /// Off when the screen puts its own rule lower down, such as a tab bar.
  final bool divider;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsetsDirectional.fromSTEB(
            AppSpacing.gutter,
            AppSpacing.x3,
            AppSpacing.gutter,
            13,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (kicker case final kicker?) ...[
                      Kicker(kicker),
                      const SizedBox(height: AppSpacing.x2),
                    ],
                    Text(title, style: theme.textTheme.headlineMedium),
                  ],
                ),
              ),
              if (trailing case final trailing?) ...[
                const SizedBox(width: AppSpacing.x3),
                trailing,
              ],
            ],
          ),
        ),
        if (divider) const Divider(),
      ],
    );
  }
}

/// A back arrow and a modest title, for the pushed screens (add a book, plan,
/// sessions) where the subject is the content below rather than the title.
class ScreenBackBar extends StatelessWidget {
  const ScreenBackBar({this.title, this.onBack, super.key});

  /// Omitted on book detail, where the book's own title sets two lines below
  /// in display type — naming it twice would make the arrow read as chrome
  /// belonging to a different screen.
  final String? title;
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(
        AppSpacing.x2,
        AppSpacing.x2,
        AppSpacing.gutter,
        AppSpacing.x3,
      ),
      child: Row(
        children: [
          IconButton(
            onPressed: onBack ?? () => Navigator.of(context).maybePop(),
            // `arrow_back` carries `matchTextDirection`, so it points the
            // right way under RTL without a manual flip.
            icon: const Icon(Icons.arrow_back, size: 19),
            color: theme.colorScheme.onSurfaceVariant,
            constraints: const BoxConstraints.tightFor(
              width: AppSpacing.minTapTarget,
              height: AppSpacing.minTapTarget,
            ),
          ),
          const SizedBox(width: AppSpacing.x1),
          if (title case final title?)
            Expanded(
              child: Text(
                title,
                style: theme.textTheme.titleSmall,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
        ],
      ),
    );
  }
}
