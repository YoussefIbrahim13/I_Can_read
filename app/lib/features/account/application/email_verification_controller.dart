import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/account_api.dart';
import '../../../core/auth/auth_client.dart';
import '../../../core/auth/auth_state.dart';

/// What stopped an address from being confirmed.
enum EmailVerificationError {
  /// Wrong, expired, already spent, or guessed at too many times. The server
  /// deliberately does not tell them apart, so neither does this.
  code,

  /// Asked for too many codes too quickly.
  tooManyRequests,

  offline,
}

sealed class EmailVerificationState {
  const EmailVerificationState();
}

/// A code has been asked for, or one is already in the reader's inbox.
final class EmailVerificationIdle extends EmailVerificationState {
  const EmailVerificationIdle();
}

final class EmailVerificationWorking extends EmailVerificationState {
  const EmailVerificationWorking();
}

/// A fresh code has just gone out, which the screen says so the reader knows
/// the older one in their inbox is now worthless.
final class EmailVerificationCodeSent extends EmailVerificationState {
  const EmailVerificationCodeSent();
}

final class EmailVerificationDone extends EmailVerificationState {
  const EmailVerificationDone();
}

final class EmailVerificationFailed extends EmailVerificationState {
  const EmailVerificationFailed(this.error);
  final EmailVerificationError error;
}

/// Proving the address on the account, from inside the account.
///
/// Unlike the password reset, there is no address to type: the reader is signed
/// in, so the server already knows which one it sent the code to.
class EmailVerificationController extends Notifier<EmailVerificationState> {
  @override
  EmailVerificationState build() => const EmailVerificationIdle();

  /// Asks for a fresh code, retiring whatever is already in the inbox.
  Future<void> sendCode() async {
    state = const EmailVerificationWorking();

    try {
      await ref.read(accountApiProvider).sendEmailCode();
    } on AuthException catch (error) {
      state = EmailVerificationFailed(
        error.statusCode == 429
            ? EmailVerificationError.tooManyRequests
            : EmailVerificationError.offline,
      );
      return;
    } on SocketException {
      state = const EmailVerificationFailed(EmailVerificationError.offline);
      return;
    } on HttpException {
      state = const EmailVerificationFailed(EmailVerificationError.offline);
      return;
    }

    state = const EmailVerificationCodeSent();
  }

  /// Spends the code the reader typed.
  Future<void> submit(String code) async {
    state = const EmailVerificationWorking();

    final api = ref.read(accountApiProvider);
    try {
      await api.verifyEmail(code.trim());
    } on AuthException catch (error) {
      state = EmailVerificationFailed(switch (error.statusCode) {
        400 => EmailVerificationError.code,
        429 => EmailVerificationError.tooManyRequests,
        _ => EmailVerificationError.offline,
      });
      return;
    } on SocketException {
      state = const EmailVerificationFailed(EmailVerificationError.offline);
      return;
    } on HttpException {
      state = const EmailVerificationFailed(EmailVerificationError.offline);
      return;
    }

    // Confirmed, and now the stored session says so — which is what takes the
    // prompt off the account screen and puts the "connect Google" row on it.
    // Best effort: the address is proved either way, and a failure here would
    // be corrected at the next refresh.
    try {
      await ref.read(authStateProvider.notifier).updateUser(await api.me());
    } on Object {
      // Nothing to tell the reader. What they asked for has happened.
    }

    state = const EmailVerificationDone();
  }

  void reset() => state = const EmailVerificationIdle();
}

final emailVerificationControllerProvider =
    NotifierProvider<EmailVerificationController, EmailVerificationState>(
      EmailVerificationController.new,
    );
