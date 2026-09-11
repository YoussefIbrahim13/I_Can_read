import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../config/api_config.dart';
import 'auth_client.dart';
import 'auth_state.dart';

/// HTTP client that attaches the bearer token and refreshes it transparently.
///
/// Every sync and data request goes through this. If the access token is about
/// to expire (<30 s), the wrapper refreshes it before the request. If refresh
/// fails (the token was revoked or the account deleted), it signs the reader
/// out and throws so the caller can stop.
class AuthenticatedHttp {
  AuthenticatedHttp({
    required this.ref,
    required this.baseUrl,
    http.Client? httpClient,
  }) : _http = httpClient ?? http.Client();

  final Ref ref;

  /// The API origin, from [ApiConfig] — never a hardcoded address.
  final String baseUrl;

  final http.Client _http;

  static const _jsonHeaders = {
    'Content-Type': 'application/json; charset=UTF-8',
  };

  /// GET with bearer token.
  Future<http.Response> get(String path) async {
    final token = await _validAccessToken();
    return _http.get(
      Uri.parse('$baseUrl$path'),
      headers: {'Authorization': 'Bearer $token', 'Accept': 'application/json'},
    );
  }

  /// POST with bearer token and JSON body.
  Future<http.Response> post(String path, Object body) async {
    final token = await _validAccessToken();
    return _http.post(
      Uri.parse('$baseUrl$path'),
      headers: {'Authorization': 'Bearer $token', ..._jsonHeaders},
      body: jsonEncode(body),
    );
  }

  /// POST with bearer token and no body, for endpoints that take no argument.
  ///
  /// Separate from [post] rather than a null default: an endpoint that wants
  /// nothing and one that wants `null` are different requests, and sending
  /// `"null"` as a JSON body is how the second happens by accident.
  Future<http.Response> postEmpty(String path) async {
    final token = await _validAccessToken();
    return _http.post(
      Uri.parse('$baseUrl$path'),
      headers: {'Authorization': 'Bearer $token', 'Accept': 'application/json'},
    );
  }

  /// PATCH with bearer token and JSON body.
  Future<http.Response> patch(String path, Object body) async {
    final token = await _validAccessToken();
    return _http.patch(
      Uri.parse('$baseUrl$path'),
      headers: {'Authorization': 'Bearer $token', ..._jsonHeaders},
      body: jsonEncode(body),
    );
  }

  /// DELETE with bearer token.
  Future<http.Response> delete(String path) async {
    final token = await _validAccessToken();
    return _http.delete(
      Uri.parse('$baseUrl$path'),
      headers: {'Authorization': 'Bearer $token', 'Accept': 'application/json'},
    );
  }

  /// Returns a valid access token, refreshing it first if necessary.
  Future<String> _validAccessToken() async {
    final session = ref.read(authStateProvider);
    if (session == null) {
      throw StateError('Not signed in');
    }

    if (!session.isAccessTokenExpired) {
      return session.accessToken;
    }

    // Token is about to expire — refresh it.
    try {
      final response = await ref
          .read(authClientProvider)
          .refresh(session.refreshToken);
      await ref.read(authStateProvider.notifier).updateTokens(response);
      return response.accessToken;
    } on AuthException {
      // The refresh token was revoked or expired. Sign out.
      await ref.read(authStateProvider.notifier).signOut();
      rethrow;
    }
  }

  void dispose() => _http.close();
}

/// Shared authenticated HTTP client. Disposed with the container.
final authenticatedHttpProvider = Provider<AuthenticatedHttp>((ref) {
  final client = AuthenticatedHttp(
    ref: ref,
    baseUrl: ref.watch(apiBaseUrlProvider),
  );
  ref.onDispose(client.dispose);
  return client;
});
