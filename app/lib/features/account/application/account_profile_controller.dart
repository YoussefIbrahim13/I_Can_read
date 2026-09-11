import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/account_api.dart';
import '../../../core/auth/auth_client.dart';
import '../../../core/auth/auth_state.dart';
import '../../../core/auth/google_identity.dart';

/// What stopped a change to the account's details.
enum AccountProfileError {
  /// The address on this account has not been proved yet, so Google cannot be
  /// matched against it.
  emailNotVerified,

  /// The Google account picked uses a different address than this account.
  googleEmailMismatch,

  /// That Google account is already the way into somebody else's account here.
  googleAlreadyInUse,

  /// Unlinking would leave the account with no way in at all.
  wouldLockOut,

  /// The password given did not confirm the account.
  notConfirmed,

  /// Google itself refused, or had nothing to hand back.
  google,

  tooManyRequests,

  offline,
}

/// Which control on the account screen a result belongs under.
///
/// The panel is one column of unrelated things, so a note at the bottom of it
/// would sit three buttons away from the field it is about. Carrying the
/// subject lets the screen put the answer where the question was asked.
enum AccountSubject { name, google }

sealed class AccountProfileState {
  const AccountProfileState();
}

final class AccountProfileIdle extends AccountProfileState {
  const AccountProfileIdle();
}

final class AccountProfileWorking extends AccountProfileState {
  const AccountProfileWorking(this.subject);
  final AccountSubject subject;
}

/// Something changed and the account screen should say so.
final class AccountProfileSaved extends AccountProfileState {
  const AccountProfileSaved(this.subject);
  final AccountSubject subject;
}

final class AccountProfileFailed extends AccountProfileState {
  const AccountProfileFailed(this.error, this.subject);

  final AccountProfileError error;
  final AccountSubject subject;
}

/// The reader's name, and whether Google is one of the ways in.
///
/// Together in one controller because they are the same screen's two halves and
/// share every failure path; apart from the password, which signs devices out
/// and has a screen of its own.
class AccountProfileController extends Notifier<AccountProfileState> {
  @override
  AccountProfileState build() => const AccountProfileIdle();

  /// Changes what the reader is called. An empty [name] clears it.
  Future<void> saveName(String name) async {
    final trimmed = name.trim();
    state = const AccountProfileWorking(AccountSubject.name);

    await _run(
      AccountSubject.name,
      (api) async => ref
          .read(authStateProvider.notifier)
          .updateUser(await api.updateName(trimmed.isEmpty ? null : trimmed)),
    );
  }

  /// Adds Google as a second way into this account.
  Future<void> linkGoogle() async {
    state = const AccountProfileWorking(AccountSubject.google);

    final GoogleIdentity identity;
    try {
      identity = await ref.read(googleIdentityProvider).signIn();
    } on GoogleSignInFailure catch (failure) {
      // Backing out of the account picker is not a failure to report.
      state = failure.cancelled
          ? const AccountProfileIdle()
          : const AccountProfileFailed(
              AccountProfileError.google,
              AccountSubject.google,
            );
      return;
    }

    await _run(AccountSubject.google, (api) async {
      await api.linkGoogle(identity.idToken);
      await ref.read(authStateProvider.notifier).updateUser(await api.me());
    });
  }

  /// Takes Google back off, confirmed with the account's password.
  ///
  /// The password is what the server asks for, and it only ever gets this far
  /// for an account that has one — an account with no password is refused,
  /// because unlinking would shut the last door behind the reader.
  Future<void> unlinkGoogle(String password) async {
    state = const AccountProfileWorking(AccountSubject.google);

    await _run(AccountSubject.google, (api) async {
      await api.unlinkGoogle(password: password);
      await ref.read(authStateProvider.notifier).updateUser(await api.me());
    });
  }

  /// Runs a call and turns whatever it throws into something the screen names.
  Future<void> _run(
    AccountSubject subject,
    Future<void> Function(AccountApi api) call,
  ) async {
    try {
      await call(ref.read(accountApiProvider));
    } on AuthException catch (error) {
      // Four different refusals arrive as 409, so the status alone is not
      // enough — the server names each one in the body. See `AuthException.code`.
      state = AccountProfileFailed(switch (error.code) {
        'emailNotVerified' => AccountProfileError.emailNotVerified,
        'googleEmailMismatch' => AccountProfileError.googleEmailMismatch,
        'googleAlreadyInUse' => AccountProfileError.googleAlreadyInUse,
        'wouldLockOut' => AccountProfileError.wouldLockOut,
        'notConfirmed' => AccountProfileError.notConfirmed,
        'invalidGoogleToken' => AccountProfileError.google,
        _ => switch (error.statusCode) {
          401 => AccountProfileError.notConfirmed,
          429 => AccountProfileError.tooManyRequests,
          _ => AccountProfileError.offline,
        },
      }, subject);
      return;
    } on SocketException {
      state = AccountProfileFailed(AccountProfileError.offline, subject);
      return;
    } on HttpException {
      state = AccountProfileFailed(AccountProfileError.offline, subject);
      return;
    }

    state = AccountProfileSaved(subject);
  }

  void reset() => state = const AccountProfileIdle();
}

final accountProfileControllerProvider =
    NotifierProvider<AccountProfileController, AccountProfileState>(
      AccountProfileController.new,
    );
