import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/auth_client.dart';
import 'account_rules.dart';

/// What stopped a reset, in terms the screen can name.
enum PasswordResetError {
  email,

  /// Wrong, expired, already spent, or guessed at too many times. The server
  /// deliberately does not tell them apart, so neither does this.
  code,

  passwordTooShort,

  /// Asked for too many codes too quickly.
  tooManyRequests,

  offline,
}

sealed class PasswordResetState {
  const PasswordResetState();
}

/// Asking for the address.
final class PasswordResetIdle extends PasswordResetState {
  const PasswordResetIdle();
}

final class PasswordResetWorking extends PasswordResetState {
  const PasswordResetWorking();
}

/// A code has been asked for. Whether one was actually sent is not something
/// the server will say, and the screen says so in as many words.
final class PasswordResetCodeSent extends PasswordResetState {
  const PasswordResetCodeSent(this.email);
  final String email;
}

final class PasswordResetDone extends PasswordResetState {
  const PasswordResetDone();
}

/// A failure, carrying the step it happened on so the screen stays where the
/// reader was rather than sending them back to retype an address.
final class PasswordResetFailed extends PasswordResetState {
  const PasswordResetFailed(this.error, {this.email});

  final PasswordResetError error;

  /// Non-null when the failure happened on the code step.
  final String? email;
}

class PasswordResetController extends Notifier<PasswordResetState> {
  @override
  PasswordResetState build() => const PasswordResetIdle();

  /// Asks for a code, and moves to the step that spends it.
  ///
  /// Moves there even for an address with no account. The server answers
  /// identically either way on purpose, and a screen that said "no such
  /// account" would undo that in one line of text.
  Future<void> requestCode(String email) async {
    final trimmed = email.trim();
    if (!looksLikeEmail(trimmed)) {
      state = const PasswordResetFailed(PasswordResetError.email);
      return;
    }

    state = const PasswordResetWorking();

    try {
      await ref.read(authClientProvider).forgotPassword(trimmed);
    } on AuthException catch (error) {
      state = PasswordResetFailed(
        error.statusCode == 429
            ? PasswordResetError.tooManyRequests
            : PasswordResetError.offline,
      );
      return;
    } on SocketException {
      state = const PasswordResetFailed(PasswordResetError.offline);
      return;
    } on HttpException {
      state = const PasswordResetFailed(PasswordResetError.offline);
      return;
    }

    state = PasswordResetCodeSent(trimmed);
  }

  /// Spends the code the reader typed.
  Future<void> submitNewPassword({
    required String code,
    required String newPassword,
  }) async {
    final email = switch (state) {
      PasswordResetCodeSent(:final email) => email,
      PasswordResetFailed(email: final email?) => email,
      // Nothing was asked for, so there is no code to spend.
      _ => null,
    };
    if (email == null) return;

    if (newPassword.length < minPasswordLength) {
      state = PasswordResetFailed(
        PasswordResetError.passwordTooShort,
        email: email,
      );
      return;
    }

    state = const PasswordResetWorking();

    try {
      await ref
          .read(authClientProvider)
          .resetPassword(
            email: email,
            code: code.trim(),
            newPassword: newPassword,
          );
    } on AuthException catch (error) {
      state = PasswordResetFailed(switch (error.statusCode) {
        400 => PasswordResetError.code,
        429 => PasswordResetError.tooManyRequests,
        _ => PasswordResetError.offline,
      }, email: email);
      return;
    } on SocketException {
      state = PasswordResetFailed(PasswordResetError.offline, email: email);
      return;
    } on HttpException {
      state = PasswordResetFailed(PasswordResetError.offline, email: email);
      return;
    }

    state = const PasswordResetDone();
  }

  void reset() => state = const PasswordResetIdle();
}

final passwordResetControllerProvider =
    NotifierProvider<PasswordResetController, PasswordResetState>(
      PasswordResetController.new,
    );
