import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/auth_client.dart';
import '../../../core/auth/auth_state.dart';
import '../../../core/auth/google_identity.dart';
import '../../../core/db/app_database.dart';
import '../../../core/settings/app_settings.dart';
import '../../../core/sync/sync_engine.dart';
import 'account_rules.dart';

export 'account_rules.dart' show minPasswordLength;

/// Which of the two things the account screen is doing.
enum AccountMode { signIn, register }

/// Why a sign-in did not work, in terms the screen can name.
///
/// Deliberately not the server's own message: the reader is told what to do
/// next, and "That email already has an account" only means anything in the
/// language they chose.
enum AccountError {
  email,
  passwordTooShort,
  emailTaken,
  credentials,
  offline,

  /// Google vouched for the reader, but that address is already a password
  /// account here — see the server's `GoogleSignInAsync` for why the two are
  /// not joined up on our own say-so.
  googleEmailIsPasswordAccount,

  /// Google itself refused, or had nothing to hand back.
  google,
}

sealed class AccountState {
  const AccountState();
}

final class AccountIdle extends AccountState {
  const AccountIdle();
}

final class AccountWorking extends AccountState {
  const AccountWorking();
}

/// Signed in, and the guest library is being handed to the account.
final class AccountAdopting extends AccountState {
  const AccountAdopting();
}

final class AccountFailed extends AccountState {
  const AccountFailed(this.error);
  final AccountError error;
}

final class AccountSignedIn extends AccountState {
  const AccountSignedIn(this.email);
  final String email;
}

/// Which account the books on this phone belong to.
///
/// Written the first time a reader signs in. It is what tells a guest library
/// ("nobody has claimed this yet") apart from one that is already somebody's.
const _dataOwnerKey = 'sync.dataOwner';

class AccountController extends Notifier<AccountState> {
  @override
  AccountState build() => const AccountIdle();

  /// Signs in or registers, then hands over whatever is already on the phone.
  Future<void> submit({
    required AccountMode mode,
    required String email,
    required String password,
    String? displayName,
  }) async {
    final trimmed = email.trim();
    if (!looksLikeEmail(trimmed)) {
      state = const AccountFailed(AccountError.email);
      return;
    }
    if (password.length < minPasswordLength) {
      state = const AccountFailed(AccountError.passwordTooShort);
      return;
    }

    state = const AccountWorking();

    final client = ref.read(authClientProvider);
    final AuthResponse response;
    try {
      response = switch (mode) {
        AccountMode.signIn => await client.login(
          email: trimmed,
          password: password,
        ),
        AccountMode.register => await client.register(
          email: trimmed,
          password: password,
          displayName: displayName?.trim().isEmpty ?? true
              ? null
              : displayName!.trim(),
        ),
      };
    } on AuthException catch (error) {
      state = AccountFailed(switch (error.statusCode) {
        409 => AccountError.emailTaken,
        401 => AccountError.credentials,
        // A 400 is the server's own validation disagreeing with ours, and a
        // 500 is not something the reader can act on. Both are "try again".
        _ => AccountError.offline,
      });
      return;
    } on SocketException {
      state = const AccountFailed(AccountError.offline);
      return;
    } on HttpException {
      state = const AccountFailed(AccountError.offline);
      return;
    }

    await ref.read(authStateProvider.notifier).signIn(response);
    state = const AccountAdopting();
    await _adoptLocalData(response.user.id);
    state = AccountSignedIn(response.user.email);
  }

  /// Signs in with Google.
  ///
  /// Two round trips, and the order matters: Google first, so the reader picks
  /// an account before anything is sent anywhere, then our server, which is
  /// the only party that decides whether that token means an account here.
  Future<void> signInWithGoogle() async {
    state = const AccountWorking();

    final GoogleIdentity identity;
    try {
      identity = await ref.read(googleIdentityProvider).signIn();
    } on GoogleSignInFailure catch (failure) {
      // Backing out of the account picker is not a failure to report. Anything
      // else is, and the reader is told Google was the part that went wrong.
      state = failure.cancelled
          ? const AccountIdle()
          : const AccountFailed(AccountError.google);
      return;
    }

    final AuthResponse response;
    try {
      response = await ref.read(authClientProvider).google(identity.idToken);
    } on AuthException catch (error) {
      state = AccountFailed(switch (error.statusCode) {
        409 => AccountError.googleEmailIsPasswordAccount,
        401 => AccountError.google,
        _ => AccountError.offline,
      });
      return;
    } on SocketException {
      state = const AccountFailed(AccountError.offline);
      return;
    } on HttpException {
      state = const AccountFailed(AccountError.offline);
      return;
    }

    await ref.read(authStateProvider.notifier).signIn(response);
    state = const AccountAdopting();
    await _adoptLocalData(response.user.id);
    state = AccountSignedIn(response.user.email);
  }

  /// Gives the account whatever the reader built before they had one.
  ///
  /// Only unclaimed data is handed over. If these books already belong to a
  /// different account — someone else signed in on this phone first — they are
  /// left alone rather than pushed into the new one: they are not this
  /// reader's to upload, and the mistake would not be undoable.
  Future<void> _adoptLocalData(String userId) async {
    final prefs = ref.read(sharedPreferencesProvider);
    final owner = prefs.getString(_dataOwnerKey);

    if (owner == null) {
      await ref.read(appDatabaseProvider).seedOutboxFromLocalData();
      await prefs.setString(_dataOwnerKey, userId);
    }

    // Even when nothing was adopted this is worth doing: it is what pulls the
    // account's existing library down onto a phone that has just signed in.
    await ref.read(syncControllerProvider.notifier).syncNow();
  }

  /// Signs out and stops anything queued from following the next reader in.
  Future<void> signOut() async {
    final engine = ref.read(syncEngineProvider);

    // One last attempt to hand over what is queued, before the token that
    // could send it is thrown away. Best effort — a reader signing out on a
    // train should not be held there by it.
    if (engine != null) {
      try {
        await engine.syncNow();
      } on Object {
        // Nothing to do but carry on to the part that matters.
      }
    }

    // Whatever is still queued is dropped, sent or not. Leaving it would mean
    // that if a different reader signs in on this phone, their very first sync
    // pushes the previous reader's rows into their account.
    await ref.read(appDatabaseProvider).clearOutbox();

    // Forgets the chosen Google account too. Without this the next sign-in
    // silently reuses it, and a phone that two people share never offers the
    // second one a choice.
    await ref.read(googleIdentityProvider).signOut();

    await ref.read(authStateProvider.notifier).signOut();
    state = const AccountIdle();
  }
}

final accountControllerProvider =
    NotifierProvider<AccountController, AccountState>(AccountController.new);
