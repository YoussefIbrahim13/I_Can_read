import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../config/api_config.dart';

/// The shape of a successful auth response from the server.
class AuthResponse {
  /// Creates an [AuthResponse].
  const AuthResponse({
    required this.accessToken,
    required this.refreshToken,
    required this.accessTokenExpiresAt,
    required this.user,
  });

  /// The access token for authenticating API requests.
  final String accessToken;

  /// The refresh token for obtaining new access tokens.
  final String refreshToken;

  /// When the access token expires.
  final DateTime accessTokenExpiresAt;

  /// The authenticated user's details.
  final AuthUser user;

  /// Deserializes an [AuthResponse] from JSON.
  factory AuthResponse.fromJson(Map<String, dynamic> json) {
    return AuthResponse(
      accessToken: json['accessToken'] as String,
      refreshToken: json['refreshToken'] as String,
      accessTokenExpiresAt:
          DateTime.parse(json['accessTokenExpiresAt'] as String),
      user: AuthUser.fromJson(json['user'] as Map<String, dynamic>),
    );
  }
}

/// A representation of the authenticated user.
class AuthUser {
  /// Creates an [AuthUser].
  const AuthUser({
    required this.id,
    required this.email,
    this.displayName,
  });

  /// Unique user ID.
  final String id;

  /// The user's email address.
  final String email;

  /// The user's optional display name.
  final String? displayName;

  /// Deserializes an [AuthUser] from JSON.
  factory AuthUser.fromJson(Map<String, dynamic> json) {
    return AuthUser(
      id: json['id'] as String,
      email: json['email'] as String,
      displayName: json['displayName'] as String?,
    );
  }
}

/// Exception thrown when the server rejects an auth request.
class AuthException implements Exception {
  /// Creates an [AuthException] with a [message] and [statusCode].
  const AuthException(this.message, this.statusCode);

  /// Error message returned by the server.
  final String message;

  /// HTTP status code of the failed response.
  final int statusCode;

  @override
  String toString() => 'AuthException($statusCode): $message';
}

/// Unauthenticated calls to the auth endpoints.
class AuthClient {
  /// Creates an [AuthClient] pointed at [baseUrl], with an optional custom
  /// [httpClient].
  AuthClient({required this.baseUrl, http.Client? httpClient})
      : _http = httpClient ?? http.Client();

  /// The API origin, from [ApiConfig] — never a hardcoded address.
  final String baseUrl;

  final http.Client _http;

  static const _headers = {'Content-Type': 'application/json; charset=UTF-8'};

  /// Registers a new user account.
  Future<AuthResponse> register({
    required String email,
    required String password,
    String? displayName,
  }) async {
    final response = await _http.post(
      Uri.parse('$baseUrl/api/auth/register'),
      headers: _headers,
      body: jsonEncode({
        'email': email,
        'password': password,
        'displayName': ?displayName,
      }),
    );
    return _parse(response);
  }

  /// Logs in an existing user with email and password.
  Future<AuthResponse> login({
    required String email,
    required String password,
  }) async {
    final response = await _http.post(
      Uri.parse('$baseUrl/api/auth/login'),
      headers: _headers,
      body: jsonEncode({'email': email, 'password': password}),
    );
    return _parse(response);
  }

  /// Trades a Google ID token for a session on our own server.
  ///
  /// Only the token goes. The server reads the email and the subject out of it
  /// after checking Google's signature — sending them alongside would be
  /// sending the server two things it must not believe.
  Future<AuthResponse> google(String idToken) async {
    final response = await _http.post(
      Uri.parse('$baseUrl/api/auth/google'),
      headers: _headers,
      body: jsonEncode({'idToken': idToken}),
    );
    return _parse(response);
  }

  /// Refreshes the authentication tokens using a refresh token.
  Future<AuthResponse> refresh(String refreshToken) async {
    final response = await _http.post(
      Uri.parse('$baseUrl/api/auth/refresh'),
      headers: _headers,
      body: jsonEncode({'refreshToken': refreshToken}),
    );
    return _parse(response);
  }

  /// Invalidates the given refresh token on the server.
  Future<void> logout(String refreshToken) async {
    await _http.post(
      Uri.parse('$baseUrl/api/auth/logout'),
      headers: _headers,
      body: jsonEncode({'refreshToken': refreshToken}),
    );
    // 204 on success, and we do not care about the status either way:
    // the server treats a nonexistent token the same as an existing one.
  }

  AuthResponse _parse(http.Response response) {
    if (response.statusCode == 200) {
      return AuthResponse.fromJson(
        jsonDecode(response.body) as Map<String, dynamic>,
      );
    }
    throw AuthException(
      response.body,
      response.statusCode,
    );
  }

  /// Closes the underlying HTTP client.
  void dispose() => _http.close();
}

/// The shared auth client. Overridden in tests to answer without a server.
final authClientProvider = Provider<AuthClient>((ref) {
  final client = AuthClient(baseUrl: ref.watch(apiBaseUrlProvider));
  ref.onDispose(client.dispose);
  return client;
});
