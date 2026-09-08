import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:i_can_read/core/settings/app_settings.dart';
import 'package:i_can_read/core/widgets/app_navigation_bar.dart';
import 'package:i_can_read/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Boots the real app against a backing store, as a cold start would.
Future<SharedPreferences> _pumpApp(
  WidgetTester tester, {
  Map<String, Object> saved = const {},
}) async {
  SharedPreferences.setMockInitialValues(saved);
  final prefs = await SharedPreferences.getInstance();

  await tester.pumpWidget(
    ProviderScope(
      overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
      child: const ICanReadApp(),
    ),
  );
  await tester.pumpAndSettle();
  return prefs;
}

void main() {
  testWidgets('a fresh install opens on the welcome screen', (tester) async {
    await _pumpApp(tester);

    expect(find.text('Finish the books you start.'), findsOneWidget);
    expect(find.text('Start reading'), findsOneWidget);
    // No tab bar: there is nothing to skip to yet.
    expect(find.byType(AppNavigationBar), findsNothing);
  });

  testWidgets('states the rule the whole app is built on', (tester) async {
    await _pumpApp(tester);

    expect(
      find.text(
        'Miss a day and your daily portion stays exactly the same. '
        'Only the finish date moves.',
      ),
      findsOneWidget,
    );
    expect(
      find.text('Your PDFs stay on this phone. They are never uploaded.'),
      findsOneWidget,
    );
  });

  testWidgets('a reader who has been through it goes straight to today', (
    tester,
  ) async {
    await _pumpApp(tester, saved: {'settings.hasOnboarded': true});

    expect(find.byType(AppNavigationBar), findsOneWidget);
    expect(find.text('Finish the books you start.'), findsNothing);
  });

  testWidgets('picking a language redraws the screen in it at once', (
    tester,
  ) async {
    await _pumpApp(tester);
    expect(find.text('Finish the books you start.'), findsOneWidget);

    await tester.tap(find.text('العربية'));
    await tester.pumpAndSettle();

    // Still on the welcome screen, now in Arabic — the choice is shown, not
    // promised for later.
    expect(find.text('خلّص الكتب اللي بتبدأها.'), findsOneWidget);
    expect(find.text('يلا نبدأ'), findsOneWidget);
    expect(find.text('Finish the books you start.'), findsNothing);

    await tester.tap(find.text('يلا نبدأ'));
    await tester.pumpAndSettle();

    // And the language it was started in is the one the app runs in.
    expect(
      find.descendant(
        of: find.byType(AppNavigationBar),
        matching: find.text('وردي اليوم'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('starting writes the flag before leaving', (tester) async {
    final prefs = await _pumpApp(tester);
    expect(prefs.getBool('settings.hasOnboarded'), isNull);

    await tester.tap(find.text('Start reading'));
    await tester.pumpAndSettle();

    // Written, not just held in memory: killing the app on the next frame
    // must not bring the introduction back.
    expect(prefs.getBool('settings.hasOnboarded'), isTrue);
    expect(find.byType(AppNavigationBar), findsOneWidget);
  });

  testWidgets('the welcome screen does not come back after a restart', (
    tester,
  ) async {
    await _pumpApp(tester);
    await tester.tap(find.text('Start reading'));
    await tester.pumpAndSettle();

    // Rebuild from the same backing store, as a cold start would.
    final prefs = await SharedPreferences.getInstance();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
        child: const ICanReadApp(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(AppNavigationBar), findsOneWidget);
    expect(find.text('Start reading'), findsNothing);
  });

  testWidgets('a back gesture cannot return to it', (tester) async {
    await _pumpApp(tester);
    await tester.tap(find.text('Start reading'));
    await tester.pumpAndSettle();

    // The system back button, as the OS would deliver it. The welcome screen
    // was replaced rather than pushed, so there is nothing behind Today to
    // go back to — a reader must not be able to reopen a screen they have
    // already answered.
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    expect(find.text('Start reading'), findsNothing);
    expect(find.byType(AppNavigationBar), findsOneWidget);
  });
}
