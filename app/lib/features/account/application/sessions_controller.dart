import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/account_api.dart';

/// The reader's live sessions, newest first.
///
/// An [AsyncNotifier] rather than the sealed-state pattern the other account
/// controllers use: this one is a list that is fetched, and loading, failure and
/// "here it is" are exactly what [AsyncValue] already names. Inventing three
/// more classes to say the same thing would only mean the screen has two idioms
/// to read instead of one.
class SessionsController extends AsyncNotifier<List<AccountSession>> {
  @override
  Future<List<AccountSession>> build() =>
      ref.watch(accountApiProvider).sessions();

  /// Signs one device out, then shows what is left.
  Future<void> revoke(String id) async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() async {
      final api = ref.read(accountApiProvider);
      await api.revokeSession(id);
      return api.sessions();
    });
  }

  /// Signs out everywhere except this device.
  Future<void> revokeOthers() async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() async {
      final api = ref.read(accountApiProvider);
      await api.revokeOtherSessions();
      return api.sessions();
    });
  }

  /// Asks the server again — after a sign-in elsewhere, or a pull to refresh.
  Future<void> reload() async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(ref.read(accountApiProvider).sessions);
  }
}

final sessionsControllerProvider =
    AsyncNotifierProvider<SessionsController, List<AccountSession>>(
      SessionsController.new,
    );
