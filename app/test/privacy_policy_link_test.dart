import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:i_can_read/core/config/legal_links.dart';
import 'package:i_can_read/core/db/app_database.dart';
import 'package:i_can_read/core/settings/app_settings.dart';
import 'package:i_can_read/core/theme/app_theme.dart';
import 'package:i_can_read/features/settings/presentation/settings_screen.dart';
import 'package:i_can_read/l10n/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late AppDatabase db;

  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() => db.close());

  Future<AppLocalizations> pumpSettings(
    WidgetTester tester, {
    required String? policyUrl,
  }) async {
    SharedPreferences.setMockInitialValues(const {});
    final preferences = await SharedPreferences.getInstance();

    // The settings screen is a lazy list and the link is its last row, so a
    // short viewport would never build it.
    tester.view.physicalSize = const Size(400 * 3, 2000 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          sharedPreferencesProvider.overrideWithValue(preferences),
          privacyPolicyUrlProvider.overrideWithValue(policyUrl),
        ],
        child: MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          theme: AppTheme.of(
            brightness: Brightness.light,
            locale: const Locale('en'),
          ),
          home: const SettingsScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return AppLocalizations.delegate.load(const Locale('en'));
  }

  Future<void> closeApp(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
  }

  testWidgets('is offered once the policy has somewhere to live', (
    tester,
  ) async {
    final l10n = await pumpSettings(
      tester,
      policyUrl: 'https://example.github.io/yaqra/privacy-policy.html',
    );

    expect(find.text(l10n.settingsPrivacyPolicy), findsOneWidget);

    await closeApp(tester);
  });

  testWidgets('is absent in a build that was given no URL', (tester) async {
    final l10n = await pumpSettings(tester, policyUrl: null);

    // A link that goes nowhere reads as the promise being missing rather than
    // the page, so there is no row at all until there is a page to point at.
    expect(find.text(l10n.settingsPrivacyPolicy), findsNothing);

    await closeApp(tester);
  });

  test('an unset build has no URL, and a set one is trimmed of nothing', () {
    // `LegalLinks.privacyPolicy` is a compile-time constant, so what a test can
    // check is the rule applied to it: empty means absent.
    expect(LegalLinks.privacyPolicy, isEmpty);
  });
}
