import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:i_can_read/core/auth/auth_client.dart';
import 'package:i_can_read/core/theme/app_theme.dart';
import 'package:i_can_read/features/account/application/password_reset_controller.dart';
import 'package:i_can_read/features/account/presentation/password_reset_screen.dart';
import 'package:i_can_read/l10n/app_localizations.dart';

/// An auth server that only knows about resets.
///
/// Separate from `account_test.dart`'s `FakeAuth` on purpose: this file is
/// about the two reset calls, and implementing sign-in here would be four
/// methods of noise around them.
class FakeResetAuth implements AuthClient {
  AuthException? failure;

  final List<String> codesRequested = [];
  final List<(String, String)> passwordsReset = [];
  final Set<String> validCodes = {'123456'};

  @override
  String get baseUrl => 'http://localhost:5000';

  @override
  Future<void> forgotPassword(String email) async {
    if (failure case final failure?) throw failure;
    codesRequested.add(email);
  }

  @override
  Future<void> resetPassword({
    required String email,
    required String code,
    required String newPassword,
  }) async {
    if (failure case final failure?) throw failure;
    // Wrong, expired and spent all look the same coming back from the server.
    if (!validCodes.contains(code)) throw const AuthException('no', 400);
    passwordsReset.add((email, newPassword));
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} is not used here');
}

void main() {
  late FakeResetAuth auth;
  late ProviderContainer container;

  setUp(() {
    auth = FakeResetAuth();
    container = ProviderContainer(
      overrides: [authClientProvider.overrideWithValue(auth)],
    );
  });

  tearDown(() => container.dispose());

  PasswordResetController controller() =>
      container.read(passwordResetControllerProvider.notifier);

  PasswordResetState state() => container.read(passwordResetControllerProvider);

  group('asking for a code', () {
    test('a bad address never reaches the server', () async {
      await controller().requestCode('not an address');

      expect(auth.codesRequested, isEmpty);
      expect(
        state(),
        isA<PasswordResetFailed>().having(
          (s) => s.error,
          'error',
          PasswordResetError.email,
        ),
      );
    });

    test('the address is trimmed before it is sent', () async {
      await controller().requestCode('  reader@example.com  ');

      expect(auth.codesRequested, ['reader@example.com']);
      expect(state(), isA<PasswordResetCodeSent>());
    });

    test('too many requests is its own message, not "offline"', () async {
      auth.failure = const AuthException('slow down', 429);

      await controller().requestCode('reader@example.com');

      expect(
        state(),
        isA<PasswordResetFailed>().having(
          (s) => s.error,
          'error',
          PasswordResetError.tooManyRequests,
        ),
      );
    });
  });

  group('spending the code', () {
    Future<void> reachCodeStep() =>
        controller().requestCode('reader@example.com');

    test('sets the password and finishes', () async {
      await reachCodeStep();

      await controller().submitNewPassword(
        code: '123456',
        newPassword: 'a whole new passphrase',
      );

      expect(auth.passwordsReset, [
        ('reader@example.com', 'a whole new passphrase'),
      ]);
      expect(state(), isA<PasswordResetDone>());
    });

    test('a short password is caught before the code is spent', () async {
      await reachCodeStep();

      await controller().submitNewPassword(
        code: '123456',
        newPassword: 'short',
      );

      // Nothing was sent, so the code the reader is holding is still good.
      expect(auth.passwordsReset, isEmpty);
      final failed = state() as PasswordResetFailed;
      expect(failed.error, PasswordResetError.passwordTooShort);
      expect(failed.email, 'reader@example.com');
    });

    test('a wrong code keeps the reader on the step they are on', () async {
      await reachCodeStep();

      await controller().submitNewPassword(
        code: '000000',
        newPassword: 'a whole new passphrase',
      );

      final failed = state() as PasswordResetFailed;
      expect(failed.error, PasswordResetError.code);
      // The address is kept, so the screen does not send them back to retype
      // it — and so the next attempt still knows which account it is about.
      expect(failed.email, 'reader@example.com');

      await controller().submitNewPassword(
        code: '123456',
        newPassword: 'a whole new passphrase',
      );
      expect(state(), isA<PasswordResetDone>());
    });

    test('does nothing at all when no code was ever asked for', () async {
      await controller().submitNewPassword(
        code: '123456',
        newPassword: 'a whole new passphrase',
      );

      expect(auth.passwordsReset, isEmpty);
      expect(state(), isA<PasswordResetIdle>());
    });
  });

  group('the screen', () {
    Future<AppLocalizations> open(
      WidgetTester tester, {
      String? initialEmail,
      Locale locale = const Locale('en'),
    }) async {
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            locale: locale,
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            theme: AppTheme.of(brightness: Brightness.light, locale: locale),
            home: PasswordResetScreen(initialEmail: initialEmail),
          ),
        ),
      );
      await tester.pumpAndSettle();
      return AppLocalizations.delegate.load(locale);
    }

    testWidgets('carries over the address the reader already typed', (
      tester,
    ) async {
      await open(tester, initialEmail: 'reader@example.com');

      expect(find.text('reader@example.com'), findsOneWidget);
    });

    testWidgets('walks the whole flow without ever asking twice', (
      tester,
    ) async {
      final l10n = await open(tester, initialEmail: 'reader@example.com');

      await tester.tap(find.text(l10n.resetSendCode));
      await tester.pumpAndSettle();

      // Deliberately hedged: saying "we sent it" would say the address has an
      // account here, which the server refuses to say.
      expect(
        find.text(l10n.resetCodeSent('reader@example.com')),
        findsOneWidget,
      );

      await tester.enterText(find.byType(TextField).first, '123456');
      await tester.enterText(
        find.byType(TextField).last,
        'a whole new passphrase',
      );
      await tester.tap(find.text(l10n.resetSubmit));
      await tester.pumpAndSettle();

      expect(find.text(l10n.resetDone), findsOneWidget);
      expect(auth.passwordsReset, hasLength(1));
    });

    testWidgets('a wrong code is explained in place, with the code kept', (
      tester,
    ) async {
      final l10n = await open(tester, initialEmail: 'reader@example.com');
      await tester.tap(find.text(l10n.resetSendCode));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField).first, '000000');
      await tester.enterText(
        find.byType(TextField).last,
        'a whole new passphrase',
      );
      await tester.tap(find.text(l10n.resetSubmit));
      await tester.pumpAndSettle();

      expect(find.text(l10n.resetErrorCode), findsOneWidget);
      // Still on the code step rather than back at the address.
      expect(find.text(l10n.resetCode), findsOneWidget);
    });

    testWidgets('fits a narrow phone in Arabic', (tester) async {
      tester.view.physicalSize = const Size(320 * 3, 640 * 3);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.resetPhysicalSize);

      final l10n = await open(
        tester,
        initialEmail: 'reader@example.com',
        locale: const Locale('ar'),
      );
      await tester.tap(find.text(l10n.resetSendCode));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
    });
  });
}
