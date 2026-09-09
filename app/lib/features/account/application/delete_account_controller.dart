import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/auth_state.dart';
import '../../../core/auth/authenticated_http.dart';
import '../../../core/auth/google_identity.dart';
import '../../../core/db/app_database.dart';
import '../../../core/settings/app_settings.dart';
import 'account_controller.dart' show dataOwnerKey;

/// Why closing an account did not go through.
enum DeleteAccountError {
  /// The password, or the Google account, did not prove it was them.
  notConfirmed,

  /// Google itself refused, or had nothing to hand back.
  google,

  offline,
}

sealed class DeleteAccountState {
  const DeleteAccountState();
}

final class DeleteAccountIdle extends DeleteAccountState {
  const DeleteAccountIdle();
}

final class DeleteAccountWorking extends DeleteAccountState {
  const DeleteAccountWorking();
}

final class DeleteAccountFailed extends DeleteAccountState {
  const DeleteAccountFailed(this.error);
  final DeleteAccountError error;
}

final class DeleteAccountDone extends DeleteAccountState {
  const DeleteAccountDone();
}

/// Closing the account for good.
///
/// The books on this phone are deliberately left alone. They were never on the
/// server to delete, the reader owns the files, and a "delete my account" that
/// also wiped a library off a device would be doing something nobody asked for
/// and nobody could undo. What is left behind becomes a guest library again,
/// exactly as it was before anyone signed in.
class DeleteAccountController extends Notifier<DeleteAccountState> {
  @override
  DeleteAccountState build() => const DeleteAccountIdle();

  /// Closes the account, confirming with the reader's password.
  Future<void> deleteWithPassword(String password) =>
      _delete({'password': password});

  /// Closes the account, confirming through Google.
  ///
  /// For an account that only ever signed in with Google there is no password
  /// to type, so the proof is a fresh token — the reader goes through the
  /// account picker again, which is the same act that created the account.
  Future<void> deleteWithGoogle() async {
    state = const DeleteAccountWorking();

    final GoogleIdentity identity;
    try {
      identity = await ref.read(googleIdentityProvider).signIn();
    } on GoogleSignInFailure catch (failure) {
      // Backing out of the picker is a change of mind, not a failure — and on
      // this screen, of all screens, a change of mind is worth respecting.
      state = failure.cancelled
          ? const DeleteAccountIdle()
          : const DeleteAccountFailed(DeleteAccountError.google);
      return;
    }

    await _delete({'googleIdToken': identity.idToken});
  }

  Future<void> _delete(Map<String, Object?> confirmation) async {
    state = const DeleteAccountWorking();

    try {
      final response = await ref
          .read(authenticatedHttpProvider)
          .post('/api/me/delete', confirmation);

      if (response.statusCode == 401 || response.statusCode == 403) {
        state = const DeleteAccountFailed(DeleteAccountError.notConfirmed);
        return;
      }
      if (response.statusCode != 204) {
        state = const DeleteAccountFailed(DeleteAccountError.offline);
        return;
      }
    } on SocketException {
      state = const DeleteAccountFailed(DeleteAccountError.offline);
      return;
    } on HttpException {
      state = const DeleteAccountFailed(DeleteAccountError.offline);
      return;
    } on Object {
      // A revoked session throws out of the token refresh rather than coming
      // back as a status. There is nothing left to delete in that case, but the
      // reader still needs to be told something other than "done".
      state = const DeleteAccountFailed(DeleteAccountError.offline);
      return;
    }

    await _forgetTheAccount();
    state = const DeleteAccountDone();
  }

  /// Leaves this phone as it was before anyone signed in.
  Future<void> _forgetTheAccount() async {
    // Queued changes go first, and it matters that they go before the sign-out
    // rather than after: they belong to an account that no longer exists, and
    // the next reader to sign in on this phone must not inherit them.
    await ref.read(appDatabaseProvider).clearOutbox();

    // The library stops being anybody's, so signing up again adopts it back
    // rather than treating it as somebody else's and leaving it stranded.
    await ref.read(sharedPreferencesProvider).remove(dataOwnerKey);

    await ref.read(googleIdentityProvider).signOut();
    await ref.read(authStateProvider.notifier).signOut();
  }

  void reset() => state = const DeleteAccountIdle();
}

final deleteAccountControllerProvider =
    NotifierProvider<DeleteAccountController, DeleteAccountState>(
      DeleteAccountController.new,
    );
