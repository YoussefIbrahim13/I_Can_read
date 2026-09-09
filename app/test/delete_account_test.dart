import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:i_can_read/core/auth/auth_config.dart';
import 'package:i_can_read/core/auth/auth_state.dart';
import 'package:i_can_read/core/auth/authenticated_http.dart';
import 'package:i_can_read/core/auth/google_identity.dart';
import 'package:i_can_read/core/db/app_database.dart';
import 'package:i_can_read/core/settings/app_settings.dart';
import 'package:i_can_read/core/theme/app_theme.dart';
import 'package:i_can_read/features/account/application/account_controller.dart';
import 'package:i_can_read/features/account/application/delete_account_controller.dart';
import 'package:i_can_read/features/account/presentation/delete_account_screen.dart';
import 'package:i_can_read/l10n/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A server that answers the delete call however the test tells it to.
class FakeDeleteHttp extends AuthenticatedHttp {
  FakeDeleteHttp() : super(ref: _unusedRef, baseUrl: 'http://localhost:5000');

  /// Bodies posted to `/api/me/delete`, in order.
  final List<Map<String, dynamic>> deletions = [];

  int status = 204;

  @override
  Future<http.Response> post(String path, Object body) async {
    if (path == '/api/me/delete') {
      deletions.add(Map<String, dynamic>.from(body as Map));
      return http.Response('', status);
    }
    return http.Response('', 404);
  }

  @override
  void dispose() {}

  /// The base class only stores the ref; nothing this fake does reads it.
  static final Ref _unusedRef = ProviderContainer().read(_refProvider);
}

final _refProvider = Provider<Ref>((ref) => ref);

class FakeGoogle implements GoogleIdentityProvider {
  bool signedOut = false;
  bool cancelled = false;

  @override
  bool get isAvailable => true;

  @override
  Future<GoogleIdentity> signIn() async {
    if (cancelled) throw const GoogleSignInFailure(true);
    return const GoogleIdentity(
      idToken: 'a-token-google-signed',
      email: 'reader@example.com',
    );
  }

  @override
  Future<void> signOut() async => signedOut = true;
}

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
  late FakeDeleteHttp api;
  late FakeGoogle google;
  late FakeSecureStorage storage;
  late SharedPreferences prefs;
  late ProviderContainer container;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    api = FakeDeleteHttp();
    google = FakeGoogle();
    storage = FakeSecureStorage();

    SharedPreferences.setMockInitialValues({dataOwnerKey: 'reader-1'});
    prefs = await SharedPreferences.getInstance();

    // A signed-in session, stored the way the app stores one.
    storage.values['auth.session'] = jsonEncode({
      'accessToken': 'access',
      'refreshToken': 'refresh',
      'accessTokenExpiresAt': DateTime.now()
          .add(const Duration(hours: 1))
          .toIso8601String(),
      'userId': 'reader-1',
      'email': 'reader@example.com',
    });

    container = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        authenticatedHttpProvider.overrideWithValue(api),
        googleIdentityProvider.overrideWithValue(google),
        secureStorageProvider.overrideWithValue(storage),
        sharedPreferencesProvider.overrideWithValue(prefs),
      ],
    );
    container.listen(authStateProvider, (_, _) {});
  });

  tearDown(() async {
    container.dispose();
    await db.close();
  });

  DeleteAccountController controller() =>
      container.read(deleteAccountControllerProvider.notifier);

  DeleteAccountState state() => container.read(deleteAccountControllerProvider);

  group('deleting', () {
    test('sends the password and leaves the phone unclaimed', () async {
      await controller().deleteWithPassword('correct horse battery');

      expect(api.deletions, [
        {'password': 'correct horse battery'},
      ]);
      expect(state(), isA<DeleteAccountDone>());

      // The library stops being anybody's, so signing up again adopts it back
      // instead of leaving it stranded as somebody else's.
      expect(prefs.getString(dataOwnerKey), isNull);
      expect(google.signedOut, isTrue);
    });

    test('a refused confirmation deletes nothing and says so', () async {
      api.status = 401;

      await controller().deleteWithPassword('not the password');

      expect(
        state(),
        isA<DeleteAccountFailed>().having(
          (s) => s.error,
          'error',
          DeleteAccountError.notConfirmed,
        ),
      );
      // Still signed in, still this account's library.
      expect(prefs.getString(dataOwnerKey), 'reader-1');
    });

    test('a Google account confirms with a fresh token', () async {
      await controller().deleteWithGoogle();

      expect(api.deletions, [
        {'googleIdToken': 'a-token-google-signed'},
      ]);
      expect(state(), isA<DeleteAccountDone>());
    });

    test('backing out of the Google picker is not a failure', () async {
      google.cancelled = true;

      await controller().deleteWithGoogle();

      expect(api.deletions, isEmpty);
      // A change of mind, and on this screen of all screens it is worth
      // respecting rather than reporting.
      expect(state(), isA<DeleteAccountIdle>());
    });

    test('the books on this phone are left alone', () async {
      await db.insertImportedBook(
        bookId: 'book-1',
        fingerprintId: 'fp-1',
        title: 'The Muqaddimah',
        pageCount: 300,
        sha256: 'a' * 64,
        sizeBytes: 1024,
        originalFileName: 'book.pdf',
        relativePath: 'books/book-1.pdf',
        now: DateTime(2026),
      );

      await controller().deleteWithPassword('correct horse battery');

      // They were never on the server to delete, the reader owns the files,
      // and wiping them would be doing something nobody asked for.
      expect(await db.findBook('book-1'), isNotNull);
      // What does go is the queue: those rows belong to an account that no
      // longer exists, and the next reader here must not inherit them.
      expect(await db.pendingOutboxEntries(), isEmpty);
    });
  });

  group('the screen', () {
    Future<AppLocalizations> open(
      WidgetTester tester, {
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
            home: const DeleteAccountScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      return AppLocalizations.delegate.load(locale);
    }

    testWidgets('says what goes and what stays before it asks', (tester) async {
      final l10n = await open(tester);

      expect(find.text(l10n.deleteAccountWhatGoes), findsOneWidget);
      expect(find.text(l10n.deleteAccountWhatStays), findsOneWidget);
      // And a way out that is as easy to find as the way through.
      expect(find.text(l10n.deleteAccountKeepMine), findsOneWidget);
    });

    testWidgets('deletes on the password that was typed', (tester) async {
      final l10n = await open(tester);

      await tester.enterText(find.byType(TextField), 'correct horse battery');
      await tester.tap(find.text(l10n.deleteAccountSubmit));
      await tester.pumpAndSettle();

      expect(api.deletions, hasLength(1));
      expect(find.text(l10n.deleteAccountDone), findsOneWidget);
    });

    testWidgets('fits a narrow phone in Arabic', (tester) async {
      tester.view.physicalSize = const Size(320 * 3, 640 * 3);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.resetPhysicalSize);

      await open(tester, locale: const Locale('ar'));

      expect(tester.takeException(), isNull);
    });
  });
}
