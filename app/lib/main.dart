import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'core/files/book_file_store.dart';
import 'core/notifications/local_reminder_channel.dart';
import 'core/notifications/reminder_channel.dart';
import 'core/notifications/reminder_sync.dart';
import 'core/router/app_router.dart';
import 'core/settings/app_settings.dart';
import 'core/theme/app_theme.dart';
import 'l10n/app_localizations.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Both need a platform round-trip, so they are resolved once here and
  // injected, rather than making every reader of them async.
  final prefs = await SharedPreferences.getInstance();
  final fileStore = await BookFileStore.open();
  final reminders = await LocalReminderChannel.open();

  runApp(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        bookFileStoreProvider.overrideWithValue(fileStore),
        reminderChannelProvider.overrideWithValue(reminders),
      ],
      child: const ICanReadApp(),
    ),
  );
}

class ICanReadApp extends ConsumerWidget {
  const ICanReadApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(appSettingsProvider);
    final router = ref.watch(appRouterProvider);
    // Watched, not used: this is what keeps the scheduled reminders in step
    // with the database for as long as the app is alive.
    ref.watch(reminderSyncProvider);

    return MaterialApp.router(
      onGenerateTitle: (context) => AppLocalizations.of(context).appTitle,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: settings.themeMode,
      // `null` lets Flutter resolve the system locale against supportedLocales,
      // which also drives the text direction.
      locale: settings.locale,
      supportedLocales: supportedLocales,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      // Typography is per-locale, not one theme with a font fallback: Arabic
      // needs taller line heights than Lora is set at. `locale` above may be
      // null (follow the system), and the resolved locale only exists below
      // `MaterialApp`, so the final theme is swapped in here.
      builder: (context, child) => Theme(
        data: AppTheme.of(
          brightness: Theme.of(context).brightness,
          locale: Localizations.localeOf(context),
        ),
        child: child!,
      ),
      routerConfig: router,
    );
  }
}
