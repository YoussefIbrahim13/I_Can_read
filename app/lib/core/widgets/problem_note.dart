import 'package:flutter/material.dart';

import '../theme/app_tokens.dart';

/// What went wrong, on a rule rather than in a toast.
///
/// A snack bar would slide away while the reader is still reading it, and the
/// thing it is talking about — the fields above it — stays on screen. Every
/// account flow says its failures this way, so it is one widget rather than the
/// same twenty lines in each of them.
class ProblemNote extends StatelessWidget {
  /// Creates a [ProblemNote] saying [message].
  const ProblemNote(this.message, {super.key});

  /// The failure, in the reader's own language.
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
