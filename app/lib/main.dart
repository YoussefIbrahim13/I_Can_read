import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'core/auth/auth_state.dart';
import 'core/config/api_config.dart';
import 'core/files/book_file_store.dart';
import 'core/notifications/local_reminder_channel.dart';
import 'core/notifications/reminder_channel.dart';
import 'core/notifications/reminder_sync.dart';
import 'core/router/app_router.dart';
import 'core/sync/sync_engine.dart';
import 'core/settings/app_settings.dart';
import 'core/theme/app_theme.dart';
import 'l10n/app_localizations.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Read once, here, so a build with a missing or unusable API_BASE_URL fails
  // while somebody is still watching it — rather than looking fine until the
  // first reader tries to sign in.
  ApiConfig.resolve();

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

class ICanReadApp extends ConsumerStatefulWidget {
  const ICanReadApp({super.key});

  @override
  ConsumerState<ICanReadApp> createState() => _ICanReadAppState();
}

class _ICanReadAppState extends ConsumerState<ICanReadApp> {
  StreamSubscription<String>? _taps;
  AppLifecycleListener? _lifecycle;

  @override
  void initState() {
    super.initState();

    // Syncing on launch and on every return to the foreground, rather than
    // only when the reader presses the button in settings. Reading happens
    // offline and in short bursts; a queue that only drains when somebody
    // thinks to drain it is a queue that is usually full.
    _lifecycle = AppLifecycleListener(onResume: _sync);
    WidgetsBinding.instance.addPostFrameCallback((_) => _sync());

    final channel = ref.read(reminderChannelProvider);
    _taps = channel.taps.listen(_openBook);
    // After the first frame, so the router has a navigator to push onto: a
    // reminder that launched the app arrives before anything is mounted.
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final bookId = await channel.takeLaunchPayload();
      if (bookId != null && mounted) _openBook(bookId);
    });
  }

  @override
  void dispose() {
    _taps?.cancel();
    _lifecycle?.dispose();
    super.dispose();
  }

  /// Drains the outbox and merges anything new, if there is an account.
  ///
  /// Signed out this does nothing at all — the controller has no engine to
  /// run — which is what keeps a reader who never wanted an account from ever
  /// making a network call.
  void _sync() {
    if (!mounted) return;
    unawaited(ref.read(syncControllerProvider.notifier).syncNow());
  }

  /// A tapped reminder opens the book, not the app.
  ///
  /// Landing on the day's list would make the reader find the book the
  /// reminder just named, which is work the reminder was supposed to save.
  void _openBook(String bookId) {
    unawaited(ref.read(appRouterProvider).push('/books/$bookId/read'));
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(appSettingsProvider);
    final router = ref.watch(appRouterProvider);
    // Watched, not used: this is what keeps the scheduled reminders in step
    // with the database for as long as the app is alive.
    ref.watch(reminderSyncProvider);
    // Also watched, not used, and for the same reason: providers auto-dispose
    // here, and the session is loaded from secure storage *after* the notifier
    // is built. Without a listener that outlives that round trip, the restored
    // sign-in would be thrown away before anything could see it.
    ref.watch(authStateProvider);

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
