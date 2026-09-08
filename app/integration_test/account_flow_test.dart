import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:i_can_read/core/auth/auth_state.dart';
import 'package:i_can_read/core/config/api_config.dart';
import 'package:i_can_read/core/db/app_database.dart';
import 'package:i_can_read/core/planning/plan_math.dart';
import 'package:i_can_read/core/settings/app_settings.dart';
import 'package:i_can_read/core/sync/sync_engine.dart';
import 'package:i_can_read/core/sync/sync_status.dart';
import 'package:i_can_read/features/account/application/account_controller.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

/// Registers and signs in against the **real API**, from a real device.
///
/// Everything in `test/account_test.dart` proves the app asks the right things
/// of a stand-in server. Only this proves the request leaves the phone at all —
/// which depends on the `INTERNET` permission, the network-security config
/// permitting cleartext to the emulator's host alias, and the wire format being
/// something ASP.NET Core will actually deserialise. None of those exist on the
/// host test VM.
///
/// Needs the API running:
/// ```
/// cd server && dotnet run --project src/ICanRead.Api --launch-profile http
/// flutter test integration_test/account_flow_test.dart -d <device>
/// ```
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late ProviderContainer container;

  /// A different address every run, so re-running does not hit "already
  /// registered" against rows the previous run left behind.
  String newEmail() =>
      'reader-${DateTime.now().microsecondsSinceEpoch}@example.com';

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();

    container = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        sharedPreferencesProvider.overrideWithValue(prefs),
      ],
    );
    // Auto-dispose is the default; the session has to outlive the calls that
    // set it, exactly as `main()` arranges in the app.
    container.listen(authStateProvider, (_, _) {});
  });

  tearDown(() async {
    // Leaves no signed-in session on the device for the next test.
    await container.read(accountControllerProvider.notifier).signOut();
    container.dispose();
    await db.close();
  });

  testWidgets('the build points somewhere usable', (tester) async {
    // If this fails, nothing below can mean anything.
    expect(ApiConfig.resolve(), isNotEmpty);
  });

  testWidgets('registering reaches the server and comes back with a session',
      (tester) async {
    final email = newEmail();

    await container.read(accountControllerProvider.notifier).submit(
          mode: AccountMode.register,
          email: email,
          password: 'a-long-enough-password',
        );

    final state = container.read(accountControllerProvider);
    expect(
      state,
      isA<AccountSignedIn>(),
      reason: state is AccountFailed
          ? 'register failed with ${state.error}'
          : 'register did not complete',
    );
    expect(container.read(authStateProvider)?.email, email);
  });

  testWidgets('the same email a second time is refused as already taken',
      (tester) async {
    final email = newEmail();
    final controller = container.read(accountControllerProvider.notifier);

    await controller.submit(
      mode: AccountMode.register,
      email: email,
      password: 'a-long-enough-password',
    );
    await controller.signOut();

    await controller.submit(
      mode: AccountMode.register,
      email: email,
      password: 'a-long-enough-password',
    );

    expect(
      (container.read(accountControllerProvider) as AccountFailed).error,
      AccountError.emailTaken,
    );
  });

  testWidgets('a wrong password is refused', (tester) async {
    final email = newEmail();
    final controller = container.read(accountControllerProvider.notifier);

    await controller.submit(
      mode: AccountMode.register,
      email: email,
      password: 'a-long-enough-password',
    );
    await controller.signOut();

    await controller.submit(
      mode: AccountMode.signIn,
      email: email,
      password: 'not-the-right-password',
    );

    expect(
      (container.read(accountControllerProvider) as AccountFailed).error,
      AccountError.credentials,
    );
  });

  testWidgets('signing back in returns the library that was pushed',
      (tester) async {
    final email = newEmail();
    final controller = container.read(accountControllerProvider.notifier);
    final now = DateTime.now();

    // Real UUIDs, because the server types every id as a Guid — the same
    // thing `Uuid().v4()` produces everywhere in the app. Anything else is
    // refused by model binding with a bare 400.
    const uuid = Uuid();
    final bookId = uuid.v4();
    final planId = uuid.v4();

    // A book and a plan built before there was an account.
    await db.insertImportedBook(
      bookId: bookId,
      fingerprintId: uuid.v4(),
      title: 'Read before signing in',
      pageCount: 100,
      sha256: 'a' * 64,
      sizeBytes: 1024,
      originalFileName: 'book.pdf',
      relativePath: 'books/book-1.pdf',
      now: now,
    );
    await db.savePlan(
      bookId: bookId,
      spec: PlanSpec(
        mode: PlanMode.byPagesPerDay,
        startPage: 1,
        endPage: 100,
        startDate: now,
        targetEndDate: now.add(const Duration(days: 9)),
        pagesPerDay: 10,
      ),
      now: now,
      newPlanId: planId,
    );
    await db.clearOutbox();

    await controller.submit(
      mode: AccountMode.register,
      email: email,
      password: 'a-long-enough-password',
    );
    expect(container.read(accountControllerProvider), isA<AccountSignedIn>());
    // The guest library was adopted and sent.
    final firstSync = container.read(syncControllerProvider);
    expect(
      await db.pendingOutboxEntries(),
      isEmpty,
      reason: firstSync is SyncFailed
          ? 'the first sync failed: ${firstSync.message}'
          : 'the outbox was not drained',
    );

    // Now a different phone: same account, empty database, no cursor.
    await container.read(accountControllerProvider.notifier).signOut();
    final phone2 = AppDatabase(NativeDatabase.memory());
    addTearDown(phone2.close);
    SharedPreferences.setMockInitialValues({});
    final prefs2 = await SharedPreferences.getInstance();
    final container2 = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWithValue(phone2),
        sharedPreferencesProvider.overrideWithValue(prefs2),
      ],
    );
    addTearDown(container2.dispose);
    container2.listen(authStateProvider, (_, _) {});

    await container2.read(accountControllerProvider.notifier).submit(
          mode: AccountMode.signIn,
          email: email,
          password: 'a-long-enough-password',
        );
    expect(container2.read(accountControllerProvider), isA<AccountSignedIn>());
    expect(container2.read(syncControllerProvider), isA<SyncComplete>());

    // The whole point of the account: the plan is waiting on the new phone,
    // even though the PDF itself never left the old one.
    final book = await phone2.findBook(bookId);
    expect(book?.title, 'Read before signing in');
    expect((await phone2.activePlanFor(bookId))?.pagesPerDay, 10);
    expect(await phone2.localFilePath(bookId), isNull);
  });
}
