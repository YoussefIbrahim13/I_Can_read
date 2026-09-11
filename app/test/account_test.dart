import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:i_can_read/core/auth/auth_client.dart';
import 'package:i_can_read/core/auth/auth_config.dart';
import 'package:i_can_read/core/auth/auth_state.dart';
import 'package:i_can_read/core/auth/google_identity.dart';
import 'package:i_can_read/core/db/app_database.dart';
import 'package:i_can_read/core/planning/plan_math.dart';
import 'package:i_can_read/core/settings/app_settings.dart';
import 'package:i_can_read/core/theme/app_theme.dart';
import 'package:i_can_read/core/sync/sync_client.dart';
import 'package:i_can_read/core/sync/sync_models.dart';
import 'package:i_can_read/features/account/application/account_controller.dart';
import 'package:i_can_read/features/account/presentation/account_screen.dart';
import 'package:i_can_read/features/settings/presentation/settings_screen.dart';
import 'package:i_can_read/l10n/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

final _jan1 = DateTime(2026, 1, 1, 9);
const _hash =
    'a3f5c1d2e4b6980a7c5e3f1d2b4a6c8e0f2d4b6a8c0e2f4d6b8a0c2e4f6d8b0a';

/// An auth server that answers however the test tells it to.
class FakeAuth implements AuthClient {
  /// Thrown instead of answering, when set.
  AuthException? failure;

  final List<String> registered = [];
  final List<String> loggedIn = [];
  String userId = 'reader-1';

  @override
  String get baseUrl => 'http://localhost:5000';

  AuthResponse _response(String email) => AuthResponse(
    accessToken: 'access',
    refreshToken: 'refresh',
    accessTokenExpiresAt: DateTime.now().add(const Duration(hours: 1)),
    user: AuthUser(id: userId, email: email),
  );

  @override
  Future<AuthResponse> register({
    required String email,
    required String password,
    String? displayName,
  }) async {
    if (failure case final failure?) throw failure;
    registered.add(email);
    return _response(email);
  }

  @override
  Future<AuthResponse> login({
    required String email,
    required String password,
  }) async {
    if (failure case final failure?) throw failure;
    loggedIn.add(email);
    return _response(email);
  }

  /// Tokens handed to `/api/auth/google`, in order.
  final List<String> googleTokens = [];

  @override
  Future<AuthResponse> google(String idToken) async {
    if (failure case final failure?) throw failure;
    googleTokens.add(idToken);
    return _response('google-reader@example.com');
  }

  @override
  Future<AuthResponse> refresh(String refreshToken) async =>
      _response('reader@example.com');

  /// Addresses a reset code was asked for, in order.
  final List<String> codesRequested = [];

  /// Codes the fake will accept. Anything else is refused the way the server
  /// refuses one: a 400 with nothing to distinguish it.
  final Set<String> validCodes = {'123456'};

  /// `(email, password)` of every reset that went through.
  final List<(String, String)> passwordsReset = [];

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
    if (!validCodes.contains(code)) {
      throw const AuthException('bad code', 400);
    }
    passwordsReset.add((email, newPassword));
  }

  @override
  Future<void> logout(String refreshToken) async {}

  @override
  void dispose() {}
}

/// A sync server that records what it was handed.
class FakeSync implements SyncApi {
  final List<SyncPayload> pushes = [];

  @override
  Future<SyncPushResponse> push(SyncPayload payload) async {
    pushes.add(payload);
    return SyncPushResponse(serverTime: _jan1, applied: 0, ignored: 0);
  }

  @override
  Future<SyncPullResponse> pull({DateTime? since}) async =>
      SyncPullResponse(serverTime: _jan1, changes: const SyncPayload());

  @override
  Future<BookDto?> lookupByHash(String sha256) async => null;
}

/// Google's account picker, without Play Services.
class FakeGoogle implements GoogleIdentityProvider {
  FakeGoogle({this.isAvailable = true});

  @override
  final bool isAvailable;

  /// Thrown instead of returning an identity, when set.
  GoogleSignInFailure? failure;

  var signedOut = false;

  @override
  Future<GoogleIdentity> signIn() async {
    if (failure case final failure?) throw failure;
    return const GoogleIdentity(
      idToken: 'a-token-google-signed',
      email: 'google-reader@example.com',
    );
  }

  @override
  Future<void> signOut() async => signedOut = true;
}

/// Secure storage that lives in a map, so no keychain is involved.
class FakeSecureStorage implements FlutterSecureStorage {
  final Map<String, String> values = {};

  @override
  Future<String?> read({
    required String key,
    dynamic iOptions,
    dynamic aOptions,
    dynamic lOptions,
    dynamic webOptions,
    dynamic mOptions,
    dynamic wOptions,
  }) async => values[key];

  @override
  Future<void> write({
    required String key,
    required String? value,
    dynamic iOptions,
    dynamic aOptions,
    dynamic lOptions,
    dynamic webOptions,
    dynamic mOptions,
    dynamic wOptions,
  }) async {
    if (value == null) {
      values.remove(key);
    } else {
      values[key] = value;
    }
  }

  @override
  Future<void> delete({
    required String key,
    dynamic iOptions,
    dynamic aOptions,
    dynamic lOptions,
    dynamic webOptions,
    dynamic mOptions,
    dynamic wOptions,
  }) async {
    values.remove(key);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} is not used here');
}

void main() {
  late AppDatabase db;
  late FakeAuth auth;
  late FakeSync sync;
  late FakeSecureStorage storage;
  late FakeGoogle google;
  late ProviderContainer container;

  Future<ProviderContainer> makeContainer([
    Map<String, Object> prefs = const {},
  ]) async {
    SharedPreferences.setMockInitialValues(prefs);
    final preferences = await SharedPreferences.getInstance();
    return ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        authClientProvider.overrideWithValue(auth),
        syncClientProvider.overrideWithValue(sync),
        googleIdentityProvider.overrideWithValue(google),
        secureStorageProvider.overrideWithValue(storage),
        sharedPreferencesProvider.overrideWithValue(preferences),
      ],
    );
  }

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    auth = FakeAuth();
    sync = FakeSync();
    storage = FakeSecureStorage();
    google = FakeGoogle();
    container = await makeContainer();
    // Auto-dispose is the default here, and the session has to outlive the
    // calls that set it — the app keeps it alive the same way, from `main`.
    container.listen(authStateProvider, (_, _) {});
  });

  tearDown(() {
    container.dispose();
    return db.close();
  });

  Future<void> readAsGuest() async {
    await db.insertImportedBook(
      bookId: 'book-1',
      fingerprintId: 'fp-1',
      title: 'Read before signing in',
      pageCount: 100,
      sha256: _hash,
      sizeBytes: 1024,
      originalFileName: 'book.pdf',
      relativePath: 'books/book-1.pdf',
      now: _jan1,
    );
    await db.savePlan(
      bookId: 'book-1',
      spec: PlanSpec(
        mode: PlanMode.byPagesPerDay,
        startPage: 1,
        endPage: 100,
        startDate: _jan1,
        targetEndDate: _jan1.add(const Duration(days: 9)),
        pagesPerDay: 10,
      ),
      now: _jan1,
      newPlanId: 'plan-1',
    );
    // Nowhere to send any of it yet.
    await db.clearOutbox();
  }

  AccountController controller() =>
      container.read(accountControllerProvider.notifier);

  group('signing in', () {
    test('a bad email never reaches the server', () async {
      await controller().submit(
        mode: AccountMode.signIn,
        email: 'not-an-email',
        password: 'longenoughpassword',
      );

      expect(
        container.read(accountControllerProvider),
        isA<AccountFailed>().having(
          (f) => f.error,
          'error',
          AccountError.email,
        ),
      );
      expect(auth.loggedIn, isEmpty);
    });

    test('a short password is caught before the round trip', () async {
      await controller().submit(
        mode: AccountMode.register,
        email: 'reader@example.com',
        password: 'short',
      );

      expect(
        (container.read(accountControllerProvider) as AccountFailed).error,
        AccountError.passwordTooShort,
      );
      expect(auth.registered, isEmpty);
    });

    test('an email already taken is told to sign in instead', () async {
      auth.failure = const AuthException('conflict', 409);

      await controller().submit(
        mode: AccountMode.register,
        email: 'reader@example.com',
        password: 'longenoughpassword',
      );

      expect(
        (container.read(accountControllerProvider) as AccountFailed).error,
        AccountError.emailTaken,
      );
    });

    test(
      'wrong details are named as wrong details, not as a server error',
      () async {
        auth.failure = const AuthException('unauthorized', 401);

        await controller().submit(
          mode: AccountMode.signIn,
          email: 'reader@example.com',
          password: 'longenoughpassword',
        );

        expect(
          (container.read(accountControllerProvider) as AccountFailed).error,
          AccountError.credentials,
        );
      },
    );

    test('a successful sign-in leaves a session behind', () async {
      await controller().submit(
        mode: AccountMode.signIn,
        email: 'reader@example.com',
        password: 'longenoughpassword',
      );

      expect(container.read(authStateProvider)?.email, 'reader@example.com');
      expect(container.read(accountControllerProvider), isA<AccountSignedIn>());
    });
  });

  group('a Google token is checked for freshness before it is sent', () {
    String jwt(Map<String, dynamic> claims) {
      String segment(Object value) =>
          base64Url.encode(utf8.encode(jsonEncode(value))).replaceAll('=', '');
      return '${segment({'alg': 'RS256'})}.${segment(claims)}.not-a-signature';
    }

    final now = DateTime.utc(2026, 9, 8, 12);

    test('an expired token is recognised', () {
      // The one that actually broke: Credential Manager handed back a token it
      // minted an hour earlier, and the server refused it — correctly.
      final token = jwt({
        'exp':
            now.subtract(const Duration(seconds: 1)).millisecondsSinceEpoch ~/
            1000,
      });

      expect(hasExpired(token, now: now), isTrue);
    });

    test('a token about to expire counts as expired', () {
      // It still has to survive the trip to the server.
      final token = jwt({
        'exp':
            now.add(const Duration(seconds: 5)).millisecondsSinceEpoch ~/ 1000,
      });

      expect(hasExpired(token, now: now), isTrue);
    });

    test('a fresh token is left alone', () {
      final token = jwt({
        'exp': now.add(const Duration(hours: 1)).millisecondsSinceEpoch ~/ 1000,
      });

      expect(hasExpired(token, now: now), isFalse);
    });

    test('an unreadable token is left for the server to judge', () {
      // Refusing to send it would turn a token the server might accept into a
      // sign-in that never gets attempted.
      for (final token in ['', 'not.a.jwt', 'only-one-part', jwt({})]) {
        expect(hasExpired(token, now: now), isFalse, reason: token);
      }
    });
  });

  group('signing in with Google', () {
    test('sends only the token, and lands in a session', () async {
      await controller().signInWithGoogle();

      // The email and the name Google gave the device are not sent. The server
      // reads them out of the token after checking who signed it — anything
      // the client asserts alongside would be a claim, not a fact.
      expect(auth.googleTokens, ['a-token-google-signed']);
      expect(container.read(accountControllerProvider), isA<AccountSignedIn>());
      expect(
        container.read(authStateProvider)?.email,
        'google-reader@example.com',
      );
    });

    test('backing out of the picker is not reported as a failure', () async {
      google.failure = const GoogleSignInFailure(true);

      await controller().signInWithGoogle();

      // The reader changed their mind. Telling them "sign-in failed" would be
      // reporting their own decision back to them as an error.
      expect(container.read(accountControllerProvider), isA<AccountIdle>());
      expect(auth.googleTokens, isEmpty);
    });

    test('a real Google failure is named as a Google failure', () async {
      google.failure = const GoogleSignInFailure(false);

      await controller().signInWithGoogle();

      expect(
        (container.read(accountControllerProvider) as AccountFailed).error,
        AccountError.google,
      );
    });

    test('an address that already has a password account says so', () async {
      auth.failure = const AuthException('conflict', 409);

      await controller().signInWithGoogle();

      // The server refuses to join the two accounts. The reader is pointed at
      // the door that already works rather than left guessing.
      expect(
        (container.read(accountControllerProvider) as AccountFailed).error,
        AccountError.googleEmailIsPasswordAccount,
      );
    });

    test(
      'brings the guest library along, exactly as a password sign-in does',
      () async {
        await readAsGuest();

        await controller().signInWithGoogle();

        expect(sync.pushes.single.books.single.id, 'book-1');
      },
    );

    test('signing out forgets the chosen Google account', () async {
      await controller().signInWithGoogle();

      await controller().signOut();

      // Otherwise the next sign-in silently reuses it, and a phone two people
      // share never offers the second one a choice.
      expect(google.signedOut, isTrue);
    });
  });

  group('the guest library', () {
    test('goes with the reader the first time they sign in', () async {
      await readAsGuest();

      await controller().submit(
        mode: AccountMode.register,
        email: 'reader@example.com',
        password: 'longenoughpassword',
      );

      // Everything built before there was an account is pushed on the first
      // sync, rather than the account looking brand new and empty.
      final pushed = sync.pushes.single;
      expect(pushed.books.single.id, 'book-1');
      expect(pushed.plans.single.id, 'plan-1');
    });

    test('is not sent twice when the same reader signs in again', () async {
      await readAsGuest();
      await controller().submit(
        mode: AccountMode.signIn,
        email: 'reader@example.com',
        password: 'longenoughpassword',
      );
      await controller().signOut();
      sync.pushes.clear();

      await controller().submit(
        mode: AccountMode.signIn,
        email: 'reader@example.com',
        password: 'longenoughpassword',
      );

      // Their own copy is already up there; re-seeding would push the whole
      // library again on every sign-in.
      expect(sync.pushes, isEmpty);
    });

    test(
      'is not handed to a different reader signing in on the same phone',
      () async {
        await readAsGuest();
        await controller().submit(
          mode: AccountMode.signIn,
          email: 'first@example.com',
          password: 'longenoughpassword',
        );
        await controller().signOut();
        sync.pushes.clear();

        auth.userId = 'reader-2';
        await controller().submit(
          mode: AccountMode.signIn,
          email: 'second@example.com',
          password: 'longenoughpassword',
        );

        // These books are not theirs to upload, and putting them in the wrong
        // account is not something the reader could undo.
        expect(sync.pushes, isEmpty);
      },
    );
  });

  group('signing out', () {
    test('empties the queue so it cannot follow the next reader in', () async {
      await controller().submit(
        mode: AccountMode.signIn,
        email: 'reader@example.com',
        password: 'longenoughpassword',
      );
      await readAsGuest();
      // A change made after signing in, still waiting to go up.
      await db.setBookStatus('book-1', BookStatus.finished, _jan1);
      expect(await db.pendingOutboxEntries(), isNotEmpty);

      await controller().signOut();

      expect(await db.pendingOutboxEntries(), isEmpty);
      expect(container.read(authStateProvider), isNull);
    });
  });

  group('the settings screen', () {
    Future<AppLocalizations> openSettings(WidgetTester tester) async {
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
            home: const SettingsScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      return AppLocalizations.delegate.load(const Locale('en'));
    }

    testWidgets('offers an account without nagging about it', (tester) async {
      final l10n = await openSettings(tester);

      // Redesign v2 made this a door rather than a section: one line saying
      // where the reader stands, and no argument about it.
      expect(find.text(l10n.settingsAccount), findsOneWidget);
      expect(find.text(l10n.settingsSignedOut), findsOneWidget);
      // The sign-in form lives behind the row now, not on this screen.
      expect(find.text(l10n.settingsSignIn), findsNothing);
    });

    testWidgets('names the signed-in reader on the row, not the form', (
      tester,
    ) async {
      await controller().submit(
        mode: AccountMode.signIn,
        email: 'reader@example.com',
        password: 'longenoughpassword',
      );

      final l10n = await openSettings(tester);

      expect(find.text(l10n.settingsAccount), findsOneWidget);
      expect(find.text('reader@example.com'), findsOneWidget);
    });
  });

  group('the account screen, signed in', () {
    testWidgets('says how many changes are still waiting, not just "saved"', (
      tester,
    ) async {
      await controller().submit(
        mode: AccountMode.signIn,
        email: 'reader@example.com',
        password: 'longenoughpassword',
      );
      // Read a book after signing in, with the phone offline: the import
      // queues the book and its fingerprint and nothing drains them.
      await db.insertImportedBook(
        bookId: 'book-1',
        fingerprintId: 'fp-1',
        title: 'Read on the train',
        pageCount: 100,
        sha256: _hash,
        sizeBytes: 1024,
        originalFileName: 'book.pdf',
        relativePath: 'books/book-1.pdf',
        now: _jan1,
      );

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
            home: const AccountScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final l10n = await AppLocalizations.delegate.load(const Locale('en'));

      // Two rows queued and nothing sent yet. Saying "up to date" here would
      // be a claim the reader could only check by losing the work.
      expect(find.text(l10n.settingsSyncPending(2)), findsOneWidget);
      expect(
        find.text(l10n.accountWelcome('reader@example.com')),
        findsOneWidget,
      );
      // Reached while already signed in, the screen is the account — not a
      // form asking the reader to get one.
      expect(find.text(l10n.accountModeRegister), findsNothing);
    });
  });

  group('the screen', () {
    Future<void> open(WidgetTester tester) async {
      // Taller than the 600px default. The form is a lazy list, so a field
      // below the fold is not merely off-screen — it is never built, and
      // `findsNothing` would be about the viewport rather than the screen.
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
            home: const AccountScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('says what happens to the PDF, on the screen that asks to send'
        ' something', (tester) async {
      await open(tester);

      final l10n = await AppLocalizations.delegate.load(const Locale('en'));
      expect(find.text(l10n.accountPrivacy), findsOneWidget);
    });

    testWidgets('a rejected sign-in explains itself in place', (tester) async {
      auth.failure = const AuthException('unauthorized', 401);
      await open(tester);

      final l10n = await AppLocalizations.delegate.load(const Locale('en'));
      await tester.enterText(
        find.byType(TextField).first,
        'reader@example.com',
      );
      await tester.enterText(find.byType(TextField).last, 'longenoughpassword');
      await tester.tap(find.text(l10n.accountSubmitSignIn).last);
      await tester.pumpAndSettle();

      // On the screen next to the fields it is about, not in a toast that
      // slides away while the reader is still reading it.
      expect(find.text(l10n.accountErrorCredentials), findsOneWidget);
    });

    testWidgets('fits a narrow phone in Arabic, with the form open', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            locale: const Locale('ar'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            theme: AppTheme.of(
              brightness: Brightness.light,
              locale: const Locale('ar'),
            ),
            home: const AccountScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // The two-segment control and the pinned button are the parts with no
      // room to give, and Arabic labels are the longest ones they carry.
      expect(tester.takeException(), isNull);
    });

    testWidgets('switching to create an account keeps what was typed', (
      tester,
    ) async {
      await open(tester);
      final l10n = await AppLocalizations.delegate.load(const Locale('en'));

      await tester.enterText(
        find.byType(TextField).first,
        'reader@example.com',
      );
      await tester.tap(find.text(l10n.accountModeRegister));
      await tester.pumpAndSettle();

      // Guessing the wrong door costs a tap, not the typing.
      expect(find.text('reader@example.com'), findsOneWidget);
      expect(find.text(l10n.accountName), findsOneWidget);
    });
  });
}
