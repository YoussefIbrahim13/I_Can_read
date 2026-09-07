import 'package:flutter/material.dart';

import '../theme/app_tokens.dart';

/// The small tracked label that opens most sections — "جلستك دي",
/// "THIS SESSION".
///
/// English kickers set in caps; Arabic ones do not, because Arabic has no
/// capital height and faking one with tracking alone reads as a defect. The
/// tracking itself is safe in both scripts.
class Kicker extends StatelessWidget {
  const Kicker(this.text, {this.color, super.key});

  /// Defaults to the gold stroke. Pass [AppColors.muted] for the quieter
  /// kickers that head a secondary list rather than the screen's subject.
  final Color? color;
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isArabic = Localizations.localeOf(context).languageCode == 'ar';

    return Text(
      isArabic ? text : text.toUpperCase(),
      style: theme.textTheme.labelSmall?.copyWith(
        color: color ?? theme.appColors.accentStroke,
      ),
    );
  }
}
