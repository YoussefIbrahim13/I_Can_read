import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import 'auth_client.dart';
import 'authenticated_http.dart';

/// One live session on the account, as `/api/me/sessions` describes it.
class AccountSession {
  /// Creates an [AccountSession].
  const AccountSession({
    required this.id,
    required this.createdAt,
    required this.expiresAt,
    required this.isCurrent,
    this.ipAddress,
    this.device,
  });

  /// Names the session to the server. Not a credential — see the server's
  /// `SessionResponse`.
  final String id;

  /// When this device signed in.
  final DateTime createdAt;

  /// When it will be signed out for you.
  final DateTime expiresAt;

  /// True for the device this list was asked from.
  final bool isCurrent;

  /// The address the session was opened from, if the server recorded one.
  final String? ipAddress;

  /// The client that opened it, verbatim. Something to recognise a phone by,
  /// never something the app decides anything on.
  final String? device;

  /// Deserializes an [AccountSession] from JSON.
  factory AccountSession.fromJson(Map<String, dynamic> json) {
    return AccountSession(
      id: json['id'] as String,
      createdAt: DateTime.parse(json['createdAt'] as String),
      expiresAt: DateTime.parse(json['expiresAt'] as String),
      isCurrent: json['isCurrent'] as bool? ?? false,
      ipAddress: json['ipAddress'] as String?,
      device: json['device'] as String?,
    );
  }
}

/// The signed-in half of the account API: everything under `/api/me`.
///
/// Separate from [AuthClient], which speaks to the endpoints that have no
/// session yet. Everything here needs one, and goes through
/// [AuthenticatedHttp] so a token about to expire is renewed first.
class AccountApi {
  /// Creates an [AccountApi] over [http].
  const AccountApi(this._http);

  final AuthenticatedHttp _http;

  /// The account as the server currently sees it.
  Future<AuthUser> me() async => _user(await _http.get('/api/me'));

  /// Changes the reader's display name. An empty [displayName] clears it.
  Future<AuthUser> updateName(String? displayName) async =>
      _user(await _http.patch('/api/me', {'displayName': displayName}));

  /// Sets a new password, and returns the session that replaces every old one.
  ///
  /// Exactly one of [currentPassword] and [googleIdToken] applies: the password
  /// for an account that has one, a fresh Google token for an account that only
  /// signs in with Google. Which is which is decided by the server from the
  /// stored account, not from what is sent.
  Future<AuthResponse> changePassword({
    required String newPassword,
    String? currentPassword,
    String? googleIdToken,
  }) async {
    final response = await _http.post('/api/me/password', {
      'currentPassword': ?currentPassword,
      'googleIdToken': ?googleIdToken,
      'newPassword': newPassword,
    });

    if (response.statusCode != 200) {
      throw AuthException(response.body, response.statusCode);
    }

    return AuthResponse.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
    );
  }

  /// Asks for a fresh code to confirm the address on the account.
  Future<void> sendEmailCode() async =>
      _nothing(await _http.postEmpty('/api/me/email/send-code'));

  /// Spends a confirmation code.
  ///
  /// Throws with 400 when the code is wrong, expired, already used, or has been
  /// guessed at too many times — the server does not distinguish, and neither
  /// does the screen.
  Future<void> verifyEmail(String code) async =>
      _nothing(await _http.post('/api/me/email/verify', {'code': code}));

  /// Adds Google as a second way into this account.
  Future<void> linkGoogle(String idToken) async =>
      _nothing(await _http.post('/api/me/google/link', {'idToken': idToken}));

  /// Takes Google back off. Refused by the server while it is the only way in.
  Future<void> unlinkGoogle({String? password, String? googleIdToken}) async =>
      _nothing(
        await _http.post('/api/me/google/unlink', {
          'password': ?password,
          'googleIdToken': ?googleIdToken,
        }),
      );

  /// The reader's live sessions, newest first.
  Future<List<AccountSession>> sessions() async {
    final response = await _http.get('/api/me/sessions');
    if (response.statusCode != 200) {
      throw AuthException(response.body, response.statusCode);
    }

    return (jsonDecode(response.body) as List<dynamic>)
        .map((raw) => AccountSession.fromJson(raw as Map<String, dynamic>))
        .toList(growable: false);
  }

  /// Signs one device out.
  Future<void> revokeSession(String id) async =>
      _nothing(await _http.delete('/api/me/sessions/$id'));

  /// Signs out everywhere except this device.
  Future<void> revokeOtherSessions() async =>
      _nothing(await _http.postEmpty('/api/me/sessions/revoke-others'));

  AuthUser _user(http.Response response) {
    if (response.statusCode != 200) {
      throw AuthException(response.body, response.statusCode);
    }

    return AuthUser.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
    );
  }

  void _nothing(http.Response response) {
    // 204 on success. Anything else is a refusal the caller has to name, and
    // the status is the only part of it worth showing a reader — the server's
    // own wording is not in the language they chose.
    if (response.statusCode != 204) {
      throw AuthException(response.body, response.statusCode);
    }
  }
}

/// The shared account API. Overridden in tests to answer without a server.
final accountApiProvider = Provider<AccountApi>(
  (ref) => AccountApi(ref.watch(authenticatedHttpProvider)),
);
