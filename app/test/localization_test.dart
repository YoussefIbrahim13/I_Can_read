import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:i_can_read/core/settings/app_settings.dart';
import 'package:i_can_read/core/widgets/app_navigation_bar.dart';
import 'package:i_can_read/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> _pumpApp(WidgetTester tester, {String? savedLanguage}) async {
  SharedPreferences.setMockInitialValues({'settings.locale': ?savedLanguage});
  final prefs = await SharedPreferences.getInstance();

  await tester.pumpWidget(
    ProviderScope(
      overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
      child: const ICanReadApp(),
    ),
  );
  await tester.pumpAndSettle();
}

/// The text direction the app actually renders its chrome with.
TextDirection _shellDirection(WidgetTester tester) =>
    Directionality.of(tester.element(find.byType(AppNavigationBar)));

/// Screen titles are reused as tab labels, so scope lookups to the tab bar.
Finder _navLabel(String label) => find.descendant(
  of: find.byType(AppNavigationBar),
  matching: find.text(label),
);

void main() {
  testWidgets('Arabic renders right-to-left with Arabic labels', (
    tester,
  ) async {
    await _pumpApp(tester, savedLanguage: 'ar');

    expect(_shellDirection(tester), TextDirection.rtl);
    expect(_navLabel('وردي اليوم'), findsOneWidget);
    expect(_navLabel('مكتبتي'), findsOneWidget);
  });

  testWidgets('English renders left-to-right with English labels', (
    tester,
  ) async {
    await _pumpApp(tester, savedLanguage: 'en');

    expect(_shellDirection(tester), TextDirection.ltr);
    expect(_navLabel('Today'), findsOneWidget);
    expect(_navLabel('Library'), findsOneWidget);
  });

  testWidgets('switching language from settings flips direction live', (
    tester,
  ) async {
    await _pumpApp(tester, savedLanguage: 'en');
    expect(_shellDirection(tester), TextDirection.ltr);

    await tester.tap(_navLabel('Settings'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('العربية'));
    await tester.pumpAndSettle();

    expect(_shellDirection(tester), TextDirection.rtl);
    expect(_navLabel('الإعدادات'), findsOneWidget);
  });

  testWidgets('the chosen language survives a restart', (tester) async {
    await _pumpApp(tester, savedLanguage: 'en');
    await tester.tap(_navLabel('Settings'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('العربية'));
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

    expect(_shellDirection(tester), TextDirection.rtl);
  });

  testWidgets('no saved language falls back to a supported locale', (
    tester,
  ) async {
    await _pumpApp(tester);

    // The test binding reports en-US, which resolves to the English bundle.
    expect(_navLabel('Today'), findsOneWidget);
  });
}
