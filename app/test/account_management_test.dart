import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:i_can_read/core/auth/account_api.dart';
import 'package:i_can_read/core/auth/auth_client.dart';
import 'package:i_can_read/core/auth/auth_config.dart';
import 'package:i_can_read/core/auth/auth_state.dart';
import 'package:i_can_read/core/auth/google_identity.dart';
import 'package:i_can_read/core/db/app_database.dart';
import 'package:i_can_read/core/settings/app_settings.dart';
import 'package:i_can_read/core/sync/sync_client.dart';
import 'package:i_can_read/core/sync/sync_models.dart';
import 'package:i_can_read/core/theme/app_theme.dart';
import 'package:i_can_read/features/account/application/account_profile_controller.dart';
import 'package:i_can_read/features/account/application/change_password_controller.dart';
import 'package:i_can_read/features/account/application/email_verification_controller.dart';
import 'package:i_can_read/features/account/application/sessions_controller.dart';
import 'package:i_can_read/features/account/presentation/account_screen.dart';
import 'package:i_can_read/features/account/presentation/devices_screen.dart';
import 'package:i_can_read/l10n/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

final _jan1 = DateTime(2026, 1, 1, 9);

/// The `/api/me` half of the server, answering however the test tells it to.
class FakeAccountApi implements AccountApi {
  FakeAccountApi();

  /// The account as this fake currently holds it.
  AuthUser user = const AuthUser(
    id: 'reader-1',
    email: 'reader@example.com',
    displayName: 'Reader',
    emailVerified: false,
    hasPassword: true,
  );

  /// Thrown instead of answering, when set.
  AuthException? failure;

  /// Codes the fake accepts. Anything else is refused the way the server
  /// refuses one: a 400 with nothing to distinguish it.
  final Set<String> validCodes = {'123456'};

  final List<String> namesSaved = [];
  final List<String> googleTokensLinked = [];
  final List<String> sessionsRevoked = [];
  var codesSent = 0;
  var othersRevoked = 0;
  (String?, String?)? passwordChange;

  List<AccountSession> liveSessions = [
    AccountSession(
      id: 'session-here',
      createdAt: _jan1,
      expiresAt: _jan1.add(const Duration(days: 30)),
      isCurrent: true,
      device: 'Pixel 8',
      ipAddress: '198.51.100.7',
    ),
    AccountSession(
      id: 'session-elsewhere',
      createdAt: _jan1.subtract(const Duration(days: 3)),
      expiresAt: _jan1.add(const Duration(days: 27)),
      isCurrent: false,
      device: 'An old tablet',
      ipAddress: '203.0.113.9',
    ),
  ];

  void _check() {
    if (failure case final failure?) throw failure;
  }

  @override
  Future<AuthUser> me() async {
    _check();
    return user;
  }

  @override
  Future<AuthUser> updateName(String? displayName) async {
    _check();
    namesSaved.add(displayName ?? '');
    user = AuthUser(
      id: user.id,
      email: user.email,
      displayName: displayName,
      emailVerified: user.emailVerified,
      hasPassword: user.hasPassword,
      googleLinked: user.googleLinked,
    );
    return user;
  }

  @override
  Future<AuthResponse> changePassword({
    required String newPassword,
    String? currentPassword,
    String? googleIdToken,
  }) async {
    _check();
    passwordChange = (currentPassword, googleIdToken);
    user = AuthUser(
      id: user.id,
      email: user.email,
      displayName: user.displayName,
      emailVerified: user.emailVerified,
      hasPassword: true,
      googleLinked: user.googleLinked,
    );
    return AuthResponse(
      accessToken: 'access-after-change',
      refreshToken: 'refresh-after-change',
      accessTokenExpiresAt: DateTime.now().add(const Duration(hours: 1)),
      user: user,
    );
  }

  @override
  Future<void> sendEmailCode() async {
    _check();
    codesSent++;
  }

  @override
  Future<void> verifyEmail(String code) async {
    _check();
    if (!validCodes.contains(code)) {
      throw const AuthException('bad code', 400);
    }
    user = AuthUser(
      id: user.id,
      email: user.email,
      displayName: user.displayName,
      emailVerified: true,
      hasPassword: user.hasPassword,
      googleLinked: user.googleLinked,
    );
  }

  @override
  Future<void> linkGoogle(String idToken) async {
    _check();
    googleTokensLinked.add(idToken);
    user = AuthUser(
      id: user.id,
      email: user.email,
      displayName: user.displayName,
      emailVerified: user.emailVerified,
      hasPassword: user.hasPassword,
      googleLinked: true,
    );
  }

  @override
  Future<void> unlinkGoogle({String? password, String? googleIdToken}) async {
    _check();
    user = AuthUser(
      id: user.id,
      email: user.email,
      displayName: user.displayName,
      emailVerified: user.emailVerified,
      hasPassword: user.hasPassword,
    );
  }

  @override
  Future<List<AccountSession>> sessions() async {
    _check();
    return liveSessions;
  }

  @override
  Future<void> revokeSession(String id) async {
    _check();
    sessionsRevoked.add(id);
    liveSessions = liveSessions.where((s) => s.id != id).toList();
  }

  @override
  Future<void> revokeOtherSessions() async {
    _check();
    othersRevoked++;
    liveSessions = liveSessions.where((s) => s.isCurrent).toList();
  }
}

class FakeSync implements SyncApi {
  @override
  Future<SyncPushResponse> push(SyncPayload payload) async =>
      SyncPushResponse(serverTime: _jan1, applied: 0, ignored: 0);

  @override
  Future<SyncPullResponse> pull({DateTime? since}) async =>
      SyncPullResponse(serverTime: _jan1, changes: const SyncPayload());

  @override
  Future<BookDto?> lookupByHash(String sha256) async => null;
}

class FakeGoogle implements GoogleIdentityProvider {
  FakeGoogle({this.isAvailable = true});

  @override
  final bool isAvailable;

  GoogleSignInFailure? failure;

  @override
  Future<GoogleIdentity> signIn() async {
    if (failure case final failure?) throw failure;
    return const GoogleIdentity(
      idToken: 'a-token-google-signed',
      email: 'reader@example.com',
    );
  }

  @override
  Future<void> signOut() async {}
}

class FakeSecureStorage implements FlutterSecureStorage {
  final Map<String, String> values = {};

  @override
  Future<String?> read({required String key, dynamic iOptions, dynamic aOptions,
      dynamic lOptions, dynamic webOptions, dynamic mOptions,
      dynamic wOptions}) async => values[key];

  @override
  Future<void> write({required String key, required String? value,
      dynamic iOptions, dynamic aOptions, dynamic lOptions, dynamic webOptions,
      dynamic mOptions, dynamic wOptions}) async {
    if (value == null) {
      values.remove(key);
    } else {
      values[key] = value;
    }
  }

  @override
  Future<void> delete({required String key, dynamic iOptions, dynamic aOptions,
      dynamic lOptions, dynamic webOptions, dynamic mOptions,
      dynamic wOptions}) async {
    values.remove(key);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} is not used here');
}

void main() {
  late AppDatabase db;
  late FakeAccountApi api;
  late FakeGoogle google;
  late FakeSecureStorage storage;
  late ProviderContainer container;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    api = FakeAccountApi();
    google = FakeGoogle();
    storage = FakeSecureStorage();

    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();

    container = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        accountApiProvider.overrideWithValue(api),
        syncClientProvider.overrideWithValue(FakeSync()),
        googleIdentityProvider.overrideWithValue(google),
        secureStorageProvider.overrideWithValue(storage),
        sharedPreferencesProvider.overrideWithValue(preferences),
      ],
    );
    // Auto-dispose is the default, and the session has to outlive the calls
    // that set it — the app keeps it alive the same way, from `main`.
    container.listen(authStateProvider, (_, _) {});
  });

  tearDown(() {
    container.dispose();
    return db.close();
  });

  /// Signs the container in as an account in whatever state the test needs.
  Future<void> signIn({
    bool emailVerified = false,
    bool hasPassword = true,
    bool googleLinked = false,
  }) async {
    api.user = AuthUser(
      id: 'reader-1',
      email: 'reader@example.com',
      displayName: 'Reader',
      emailVerified: emailVerified,
      hasPassword: hasPassword,
      googleLinked: googleLinked,
    );

    await container
        .read(authStateProvider.notifier)
        .signIn(
          AuthResponse(
            accessToken: 'access',
            refreshToken: 'refresh',
            accessTokenExpiresAt: DateTime.now().add(const Duration(hours: 1)),
            user: api.user,
          ),
        );
  }

  group('changing a password', () {
    ChangePasswordController controller() =>
        container.read(changePasswordControllerProvider.notifier);

    test('a short one never reaches the server', () async {
      await signIn();

      await controller().submit(currentPassword: 'old', newPassword: 'short');

      expect(
        (container.read(changePasswordControllerProvider)
                as ChangePasswordFailed)
            .error,
        ChangePasswordError.passwordTooShort,
      );
      expect(api.passwordChange, isNull);
    });

    test('the password they already have never reaches the server', () async {
      await signIn();

      await controller().submit(
        currentPassword: 'longenoughpassword',
        newPassword: 'longenoughpassword',
      );

      // The server would take it happily and sign every other device out for
      // no reason at all.
      expect(
        (container.read(changePasswordControllerProvider)
                as ChangePasswordFailed)
            .error,
        ChangePasswordError.unchanged,
      );
      expect(api.passwordChange, isNull);
    });

    test('a wrong current password is named as such', () async {
      await signIn();
      api.failure = const AuthException('unauthorized', 401);

      await controller().submit(
        currentPassword: 'not the password',
        newPassword: 'a brand new password',
      );

      expect(
        (container.read(changePasswordControllerProvider)
                as ChangePasswordFailed)
            .error,
        ChangePasswordError.notConfirmed,
      );
    });

    test('success keeps this device signed in on the new tokens', () async {
      await signIn();

      await controller().submit(
        currentPassword: 'longenoughpassword',
        newPassword: 'a brand new password',
      );

      expect(
        container.read(changePasswordControllerProvider),
        isA<ChangePasswordDone>(),
      );
      // The change threw out every refresh token including this one, so the
      // pair that came back is the only live session there is.
      final session = container.read(authStateProvider)!;
      expect(session.refreshToken, 'refresh-after-change');
      expect(session.accessToken, 'access-after-change');
    });

    test('an account with only Google proves itself with Google', () async {
      await signIn(hasPassword: false);

      await controller().submit(currentPassword: '', newPassword: 'a new one');

      // No old password to send, and the picker came up instead.
      expect(api.passwordChange, (null, 'a-token-google-signed'));
      expect(container.read(authStateProvider)!.hasPassword, isTrue);
    });

    test('backing out of the Google picker is not reported as a failure',
        () async {
      await signIn(hasPassword: false);
      google.failure = const GoogleSignInFailure(true);

      await controller().submit(currentPassword: '', newPassword: 'a new one');

      expect(
        container.read(changePasswordControllerProvider),
        isA<ChangePasswordIdle>(),
      );
      expect(api.passwordChange, isNull);
    });
  });

  group('confirming an address', () {
    EmailVerificationController controller() =>
        container.read(emailVerificationControllerProvider.notifier);

    test('a wrong code confirms nothing', () async {
      await signIn();

      await controller().submit('000000');

      expect(
        (container.read(emailVerificationControllerProvider)
                as EmailVerificationFailed)
            .error,
        EmailVerificationError.code,
      );
      expect(container.read(authStateProvider)!.emailVerified, isFalse);
    });

    test('the right code takes the prompt off the account screen', () async {
      await signIn();

      await controller().submit('123456');

      expect(
        container.read(emailVerificationControllerProvider),
        isA<EmailVerificationDone>(),
      );
      // The stored session is what the prompt is drawn from, so it has to move
      // on too — otherwise the reader confirms their address and is asked again.
      expect(container.read(authStateProvider)!.emailVerified, isTrue);
    });

    test('asking again is rate limited rather than reported as broken',
        () async {
      await signIn();
      api.failure = const AuthException('too many', 429);

      await controller().sendCode();

      expect(
        (container.read(emailVerificationControllerProvider)
                as EmailVerificationFailed)
            .error,
        EmailVerificationError.tooManyRequests,
      );
    });
  });

  group('the account details', () {
    AccountProfileController controller() =>
        container.read(accountProfileControllerProvider.notifier);

    test('a name is trimmed, and an empty one clears it', () async {
      await signIn();

      await controller().saveName('  Yusuf  ');
      expect(api.namesSaved.last, 'Yusuf');
      expect(container.read(authStateProvider)!.displayName, 'Yusuf');

      await controller().saveName('   ');
      expect(api.namesSaved.last, '');
      expect(container.read(authStateProvider)!.displayName, isNull);
    });

    test('linking Google updates what the account screen offers', () async {
      await signIn(emailVerified: true);

      await controller().linkGoogle();

      expect(api.googleTokensLinked, ['a-token-google-signed']);
      expect(container.read(authStateProvider)!.googleLinked, isTrue);
    });

    /// Four different refusals arrive as 409, so the status alone cannot say
    /// which. If these codes drift from the server's, every one of these
    /// messages silently becomes "couldn't reach the server".
    test('each refusal is told apart by the code the server sends', () async {
      await signIn();

      for (final (code, expected) in [
        ('emailNotVerified', AccountProfileError.emailNotVerified),
        ('googleEmailMismatch', AccountProfileError.googleEmailMismatch),
        ('googleAlreadyInUse', AccountProfileError.googleAlreadyInUse),
        ('wouldLockOut', AccountProfileError.wouldLockOut),
      ]) {
        api.failure = AuthException('{"code":"$code"}', 409);

        await controller().linkGoogle();

        expect(
          (container.read(accountProfileControllerProvider)
                  as AccountProfileFailed)
              .error,
          expected,
          reason: code,
        );
      }
    });

    test('a 409 with nothing to go on is not mistaken for a real answer',
        () async {
      await signIn();
      api.failure = const AuthException('not json at all', 409);

      await controller().linkGoogle();

      expect(
        (container.read(accountProfileControllerProvider)
                as AccountProfileFailed)
            .error,
        AccountProfileError.offline,
      );
    });
  });

  group('the devices list', () {
    test('signing one out leaves the rest alone', () async {
      await signIn();

      await container.read(sessionsControllerProvider.future);
      await container
          .read(sessionsControllerProvider.notifier)
          .revoke('session-elsewhere');

      expect(api.sessionsRevoked, ['session-elsewhere']);
      final left = container.read(sessionsControllerProvider).value!;
      expect(left.single.id, 'session-here');
    });

    test('signing out everywhere else keeps this one', () async {
      await signIn();

      await container.read(sessionsControllerProvider.future);
      await container.read(sessionsControllerProvider.notifier).revokeOthers();

      expect(api.othersRevoked, 1);
      expect(container.read(sessionsControllerProvider).value!.single.isCurrent,
          isTrue);
    });
  });

  group('the screens', () {
    Future<AppLocalizations> open(WidgetTester tester, Widget screen) async {
      // Taller than the 600px default. These screens are lazy lists, so a
      // control below the fold is never built at all, and `findsNothing` would
      // be about the viewport rather than about the screen.
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            theme: AppTheme.of(
              brightness: Brightness.light,
              locale: const Locale('en'),
            ),
            home: screen,
          ),
        ),
      );
      await tester.pumpAndSettle();
      return AppLocalizations.delegate.load(const Locale('en'));
    }

    testWidgets('an unconfirmed address is asked about, once confirmed is not',
        (tester) async {
      await signIn();
      var l10n = await open(tester, const AccountScreen());

      expect(find.text(l10n.verifyEmailPrompt), findsOneWidget);

      await container
          .read(emailVerificationControllerProvider.notifier)
          .submit('123456');
      await tester.pumpAndSettle();

      l10n = await AppLocalizations.delegate.load(const Locale('en'));
      expect(find.text(l10n.verifyEmailPrompt), findsNothing);
    });

    testWidgets('an account with no password is offered one, not a change',
        (tester) async {
      await signIn(hasPassword: false, googleLinked: true, emailVerified: true);
      final l10n = await open(tester, const AccountScreen());

      expect(find.text(l10n.manageSetPassword), findsOneWidget);
      expect(find.text(l10n.manageChangePassword), findsNothing);
      // And Google cannot come off, because it is the only way in. The server
      // refuses it; the screen should not offer it as though it might work.
      expect(find.text(l10n.manageDisconnectGoogle), findsOneWidget);
    });

    testWidgets('an account with a password is offered a change', (
      tester,
    ) async {
      await signIn();
      final l10n = await open(tester, const AccountScreen());

      expect(find.text(l10n.manageChangePassword), findsOneWidget);
      expect(find.text(l10n.manageSetPassword), findsNothing);
      expect(find.text(l10n.manageConnectGoogle), findsOneWidget);
    });

    testWidgets('Google is not offered where Google is not available', (
      tester,
    ) async {
      google = FakeGoogle(isAvailable: false);
      container.dispose();
      SharedPreferences.setMockInitialValues({});
      final preferences = await SharedPreferences.getInstance();
      container = ProviderContainer(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          accountApiProvider.overrideWithValue(api),
          syncClientProvider.overrideWithValue(FakeSync()),
          googleIdentityProvider.overrideWithValue(google),
          secureStorageProvider.overrideWithValue(storage),
          sharedPreferencesProvider.overrideWithValue(preferences),
        ],
      );
      container.listen(authStateProvider, (_, _) {});
      await signIn();

      final l10n = await open(tester, const AccountScreen());

      // A button that leads nowhere every time is worse than no button.
      expect(find.text(l10n.manageConnectGoogle), findsNothing);
      expect(find.text(l10n.manageDisconnectGoogle), findsNothing);
    });

    testWidgets('the devices list names this one and offers to drop the others',
        (tester) async {
      await signIn();
      final l10n = await open(tester, const DevicesScreen());

      // Uppercased because English kickers are set in caps — see `Kicker`.
      expect(find.text(l10n.sessionsCurrent.toUpperCase()), findsOneWidget);
      expect(find.text('An old tablet · 203.0.113.9'), findsOneWidget);
      // One sign-out button, for the device that is not this one: signing this
      // device out is what the account screen's own button is for, and it has
      // the rest of the tidying to do.
      expect(find.text(l10n.sessionsSignOutOne), findsOneWidget);
      expect(find.text(l10n.sessionsSignOutOthers), findsOneWidget);
    });

    testWidgets('one device left says so rather than offering an empty action',
        (tester) async {
      await signIn();
      api.liveSessions = [api.liveSessions.first];

      final l10n = await open(tester, const DevicesScreen());

      expect(find.text(l10n.sessionsOnlyThisOne), findsOneWidget);
      expect(find.text(l10n.sessionsSignOutOthers), findsNothing);
    });
  });
}
