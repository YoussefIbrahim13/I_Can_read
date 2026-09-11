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
      accessTokenExpiresAt: DateTime.parse(
        json['accessTokenExpiresAt'] as String,
      ),
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
    this.emailVerified = false,
    this.hasPassword = false,
    this.googleLinked = false,
  });

  /// Unique user ID.
  final String id;

  /// The user's email address.
  final String email;

  /// The user's optional display name.
  final String? displayName;

  /// Whether the reader has proved they can read mail at [email].
  ///
  /// What it gates on the server is linking Google to this account. What it
  /// gates here is a prompt on the account screen.
  final bool emailVerified;

  /// False for an account that only ever signs in with Google.
  ///
  /// Decides whether the account screen offers "set a password" or "change
  /// your password", and which proof the delete and unlink screens ask for.
  final bool hasPassword;

  /// Whether Google is one of the ways into this account.
  final bool googleLinked;

  /// Deserializes an [AuthUser] from JSON.
  ///
  /// The three flags default to false when absent, which is what a server
  /// older than they are answers with. False is the safe way round: the app
  /// offers a way to fix each of them, and offering it needlessly costs a tap.
  factory AuthUser.fromJson(Map<String, dynamic> json) {
    return AuthUser(
      id: json['id'] as String,
      email: json['email'] as String,
      displayName: json['displayName'] as String?,
      emailVerified: json['emailVerified'] as bool? ?? false,
      hasPassword: json['hasPassword'] as bool? ?? false,
      googleLinked: json['googleLinked'] as bool? ?? false,
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

  /// The server's own name for this refusal, when it gave one.
  ///
  /// The account endpoints answer several different refusals with the same 409
  /// — "confirm your address first" and "that Google account belongs to
  /// somebody else" among them — and the reader has to be told different
  /// things. The status cannot carry that, so the body does. Null when the
  /// response is not a problem document, which is every older endpoint.
  String? get code {
    try {
      final body = jsonDecode(message);
      return body is Map<String, dynamic> ? body['code'] as String? : null;
    } on FormatException {
      return null;
    }
  }

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

  /// Asks the server to email a reset code to [email].
  ///
  /// Answers nothing, and answers the same nothing for an address with no
  /// account — the server will not say which addresses it knows, and neither
  /// can this. A failure here is a network failure, not a wrong address.
  Future<void> forgotPassword(String email) async {
    final response = await _http.post(
      Uri.parse('$baseUrl/api/auth/forgot-password'),
      headers: _headers,
      body: jsonEncode({'email': email}),
    );
    if (response.statusCode != 204) {
      throw AuthException(response.body, response.statusCode);
    }
  }

  /// Spends a reset code and sets a new password.
  ///
  /// Throws with 400 when the code is wrong, expired, already used, or has been
  /// guessed at too many times — the server does not distinguish, and neither
  /// does the screen.
  Future<void> resetPassword({
    required String email,
    required String code,
    required String newPassword,
  }) async {
    final response = await _http.post(
      Uri.parse('$baseUrl/api/auth/reset-password'),
      headers: _headers,
      body: jsonEncode({
        'email': email,
        'code': code,
        'newPassword': newPassword,
      }),
    );
    if (response.statusCode != 204) {
      throw AuthException(response.body, response.statusCode);
    }
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
    throw AuthException(response.body, response.statusCode);
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
