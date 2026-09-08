import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'auth_client.dart';
import 'auth_config.dart';

/// The signed-in session, or null when the reader is anonymous.
///
/// Persisted to secure storage so it survives app restarts.
class AuthSession {
  const AuthSession({
    required this.userId,
    required this.email,
    required this.accessToken,
    required this.refreshToken,
    required this.accessTokenExpiresAt,
    this.displayName,
  });

  final String userId;
  final String email;
  final String accessToken;
  final String refreshToken;
  final DateTime accessTokenExpiresAt;
  final String? displayName;

  /// Whether the access token needs refreshing before the next request.
  ///
  /// A 30-second buffer avoids the race where the token expires between the
  /// check and the request reaching the server.
  bool get isAccessTokenExpired =>
      DateTime.now().isAfter(accessTokenExpiresAt.subtract(
        const Duration(seconds: 30),
      ));

  AuthSession copyWith({
    String? accessToken,
    String? refreshToken,
    DateTime? accessTokenExpiresAt,
  }) {
    return AuthSession(
      userId: userId,
      email: email,
      accessToken: accessToken ?? this.accessToken,
      refreshToken: refreshToken ?? this.refreshToken,
      accessTokenExpiresAt:
          accessTokenExpiresAt ?? this.accessTokenExpiresAt,
      displayName: displayName,
    );
  }
}

// Storage keys.
const _keyUserId = 'auth.userId';
const _keyEmail = 'auth.email';
const _keyDisplayName = 'auth.displayName';
const _keyAccessToken = 'auth.accessToken';
const _keyRefreshToken = 'auth.refreshToken';
const _keyExpiresAt = 'auth.accessTokenExpiresAt';

class AuthStateNotifier extends Notifier<AuthSession?> {
  FlutterSecureStorage get _storage => ref.read(secureStorageProvider);

  @override
  AuthSession? build() {
    // Loaded asynchronously on first access, then kept in memory.
    // The initial state is null; _loadFromStorage fills it.
    _loadFromStorage();
    return null;
  }

  /// Reads persisted tokens on startup.
  Future<void> _loadFromStorage() async {
    final userId = await _storage.read(key: _keyUserId);
    if (userId == null) return; // never signed in

    final email = await _storage.read(key: _keyEmail);
    final accessToken = await _storage.read(key: _keyAccessToken);
    final refreshToken = await _storage.read(key: _keyRefreshToken);
    final expiresAtRaw = await _storage.read(key: _keyExpiresAt);

    if (email == null ||
        accessToken == null ||
        refreshToken == null ||
        expiresAtRaw == null) {
      return;
    }

    state = AuthSession(
      userId: userId,
      email: email,
      accessToken: accessToken,
      refreshToken: refreshToken,
      accessTokenExpiresAt: DateTime.parse(expiresAtRaw),
      displayName: await _storage.read(key: _keyDisplayName),
    );
  }

  /// Records a successful sign-in.
  Future<void> signIn(AuthResponse response) async {
    final session = AuthSession(
      userId: response.user.id,
      email: response.user.email,
      accessToken: response.accessToken,
      refreshToken: response.refreshToken,
      accessTokenExpiresAt: response.accessTokenExpiresAt,
      displayName: response.user.displayName,
    );
    state = session;
    await _persist(session);
  }

  /// Updates the tokens after a successful refresh.
  Future<void> updateTokens(AuthResponse response) async {
    final current = state;
    if (current == null) return;

    final updated = current.copyWith(
      accessToken: response.accessToken,
      refreshToken: response.refreshToken,
      accessTokenExpiresAt: response.accessTokenExpiresAt,
    );
    state = updated;
    await _persist(updated);
  }

  /// Signs out, clearing all persisted auth state.
  Future<void> signOut() async {
    final refreshToken = state?.refreshToken;
    state = null;

    await Future.wait([
      _storage.delete(key: _keyUserId),
      _storage.delete(key: _keyEmail),
      _storage.delete(key: _keyDisplayName),
      _storage.delete(key: _keyAccessToken),
      _storage.delete(key: _keyRefreshToken),
      _storage.delete(key: _keyExpiresAt),
    ]);

    // Best-effort server logout — do not block the UI on it.
    if (refreshToken != null) {
      unawaited(
        ref.read(authClientProvider).logout(refreshToken).catchError((_) {}),
      );
    }
  }

  Future<void> _persist(AuthSession session) async {
    await Future.wait([
      _storage.write(key: _keyUserId, value: session.userId),
      _storage.write(key: _keyEmail, value: session.email),
      if (session.displayName != null)
        _storage.write(key: _keyDisplayName, value: session.displayName),
      _storage.write(key: _keyAccessToken, value: session.accessToken),
      _storage.write(key: _keyRefreshToken, value: session.refreshToken),
      _storage.write(
        key: _keyExpiresAt,
        value: session.accessTokenExpiresAt.toIso8601String(),
      ),
    ]);
  }
}

/// The current auth session, or null. Watched by everything that cares about
/// whether the reader is signed in.
final authStateProvider =
    NotifierProvider<AuthStateNotifier, AuthSession?>(AuthStateNotifier.new);

/// Convenience: true when the reader has an account on this device.
final isSignedInProvider = Provider<bool>((ref) {
  return ref.watch(authStateProvider) != null;
});
