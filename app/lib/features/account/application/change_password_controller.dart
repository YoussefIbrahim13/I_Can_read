import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/account_api.dart';
import '../../../core/auth/auth_client.dart';
import '../../../core/auth/auth_state.dart';
import '../../../core/auth/google_identity.dart';
import 'account_rules.dart';

/// What stopped a password from being set.
enum ChangePasswordError {
  /// The current password did not match, or Google would not vouch again.
  notConfirmed,

  passwordTooShort,

  /// The new password is the one they already had.
  unchanged,

  /// Google itself refused, or had nothing to hand back.
  google,

  /// Too many attempts too quickly.
  tooManyRequests,

  offline,
}

sealed class ChangePasswordState {
  const ChangePasswordState();
}

final class ChangePasswordIdle extends ChangePasswordState {
  const ChangePasswordIdle();
}

final class ChangePasswordWorking extends ChangePasswordState {
  const ChangePasswordWorking();
}

final class ChangePasswordDone extends ChangePasswordState {
  const ChangePasswordDone();
}

final class ChangePasswordFailed extends ChangePasswordState {
  const ChangePasswordFailed(this.error);
  final ChangePasswordError error;
}

/// Setting a password, whether or not there was one before.
///
/// One controller for both because they are the same call: an account with a
/// password proves itself with that password, and an account that only signs in
/// with Google proves itself with a fresh Google token. The server decides which
/// applies from the stored account, so the only thing this has to get right is
/// fetching the Google token when there is no password to ask for.
class ChangePasswordController extends Notifier<ChangePasswordState> {
  @override
  ChangePasswordState build() => const ChangePasswordIdle();

  Future<void> submit({
    required String currentPassword,
    required String newPassword,
  }) async {
    if (newPassword.length < minPasswordLength) {
      state = const ChangePasswordFailed(ChangePasswordError.passwordTooShort);
      return;
    }

    final session = ref.read(authStateProvider);
    if (session == null) return;

    if (session.hasPassword && currentPassword == newPassword) {
      // Caught here rather than sent: the server would accept it happily and
      // sign every other device out for no reason at all.
      state = const ChangePasswordFailed(ChangePasswordError.unchanged);
      return;
    }

    state = const ChangePasswordWorking();

    String? googleIdToken;
    if (!session.hasPassword) {
      // No password to prove it with, so the proof is the way they got in. The
      // picker comes up before anything is sent anywhere.
      try {
        googleIdToken = (await ref.read(googleIdentityProvider).signIn()).idToken;
      } on GoogleSignInFailure catch (failure) {
        state = failure.cancelled
            ? const ChangePasswordIdle()
            : const ChangePasswordFailed(ChangePasswordError.google);
        return;
      }
    }

    final AuthResponse renewed;
    try {
      renewed = await ref
          .read(accountApiProvider)
          .changePassword(
            newPassword: newPassword,
            currentPassword: session.hasPassword ? currentPassword : null,
            googleIdToken: googleIdToken,
          );
    } on AuthException catch (error) {
      state = ChangePasswordFailed(switch (error.statusCode) {
        401 => ChangePasswordError.notConfirmed,
        429 => ChangePasswordError.tooManyRequests,
        // A 400 is the server's own length rule disagreeing with ours, which
        // means ours has drifted; the reader can only act on it as "too short".
        400 => ChangePasswordError.passwordTooShort,
        _ => ChangePasswordError.offline,
      });
      return;
    } on SocketException {
      state = const ChangePasswordFailed(ChangePasswordError.offline);
      return;
    } on HttpException {
      state = const ChangePasswordFailed(ChangePasswordError.offline);
      return;
    }

    // The change threw out every refresh token including this device's, so the
    // pair that came back is the only live session there is. Storing it is what
    // keeps the reader from being signed out of the phone in their hand.
    await ref.read(authStateProvider.notifier).updateTokens(renewed);
    state = const ChangePasswordDone();
  }

  void reset() => state = const ChangePasswordIdle();
}

final changePasswordControllerProvider =
    NotifierProvider<ChangePasswordController, ChangePasswordState>(
      ChangePasswordController.new,
    );
