import 'package:flutter/material.dart';

import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/screen_header.dart';
import '../../../l10n/app_localizations.dart';

class StatsScreen extends StatelessWidget {
  const StatsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ScreenHeader(
              kicker: l10n.statsWindowLast30Days,
              title: l10n.navStats,
            ),
            Expanded(
              child: EmptyState(
                title: l10n.statsEmpty,
                message: l10n.statsEmptyHint,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
