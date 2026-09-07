import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/format/app_dates.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/screen_header.dart';
import '../../../l10n/app_localizations.dart';

class TodayScreen extends StatelessWidget {
  const TodayScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final locale = Localizations.localeOf(context);

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ScreenHeader(
              kicker: AppDates.weekdayAndDate(DateTime.now(), locale),
              title: l10n.navToday,
            ),
            Expanded(
              child: EmptyState(
                title: l10n.todayEmpty,
                message: l10n.todayEmptyHint,
                action: OutlinedButton(
                  onPressed: () => context.push('/books/add'),
                  child: Text(l10n.addBook),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
