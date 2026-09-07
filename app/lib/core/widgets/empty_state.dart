import 'package:flutter/material.dart';

import '../theme/app_tokens.dart';

/// The "nothing here yet" panel for the Today, Library and Stats tabs.
///
/// Editorial, not iconographic: a grey outline icon over two lines of grey
/// text is the generic shape this design replaces. An empty screen is a
/// sentence — a statement at hero size, a quieter line explaining the way out,
/// and the one action that takes it. Text is start-aligned, so it reads as
/// copy rather than as a placeholder.
class EmptyState extends StatelessWidget {
  const EmptyState({
    required this.title,
    required this.message,
    this.action,
    super.key,
  });

  final String title;
  final String message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.gutter,
        vertical: AppSpacing.x6,
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(title, style: theme.textTheme.titleLarge),
          const SizedBox(height: AppSpacing.x3),
          Text(
            message,
            style: theme.textTheme.bodySmall?.copyWith(
              fontSize: 13.5,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          if (action case final action?) ...[
            const SizedBox(height: AppSpacing.x6),
            action,
          ],
        ],
      ),
    );
  }
}
