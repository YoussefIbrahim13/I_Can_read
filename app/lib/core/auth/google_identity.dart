import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../config/api_config.dart';

/// The reader chose an account and Google signed a token saying so.
///
/// Only the token travels. The email and the name that come back alongside it
/// are for showing on screen while the call is in flight — the server takes
/// neither, because a value the client sends is a value the client can invent.
class GoogleIdentity {
  const GoogleIdentity({required this.idToken, required this.email});

  final String idToken;
  final String email;
}

/// Raised when Google could not, or would not, produce a token.
class GoogleSignInFailure implements Exception {
  const GoogleSignInFailure(this.cancelled);

  /// True when the reader dismissed the account picker.
  ///
  /// Separated from every other failure because it is not one: nothing went
  /// wrong, the reader changed their mind, and telling them "sign-in failed"
  /// would be reporting their own decision back to them as an error.
  final bool cancelled;
}

/// The account picker, behind a seam.
///
/// The plugin talks to Play Services, which is not something a test can stand
/// up. What is worth testing is everything after the token arrives, so that is
/// what this interface exists to let a test reach.
abstract interface class GoogleIdentityProvider {
  /// Whether this build can offer Google sign-in at all.
  bool get isAvailable;

  /// Shows the account picker and returns a signed token.
  Future<GoogleIdentity> signIn();

  /// Forgets the chosen account, so the picker appears again next time.
  Future<void> signOut();
}

class PlayServicesGoogleIdentity implements GoogleIdentityProvider {
  /// The one and only `initialize` call, kept as the future it returned.
  ///
  /// Static, not per-instance, and this matters. `GoogleSignIn.instance` is
  /// process-wide and its `initialize` may be called exactly once — twice is
  /// documented as undefined behaviour, and what actually happens is that the
  /// next `authenticate()` never returns, leaving the button spinning forever.
  /// A per-instance flag looks equivalent and is not: this class is built by a
  /// provider that auto-disposes, so the flag resets the moment nothing is
  /// listening, and the second sign-in of a session initialises again.
  ///
  /// Held as a future rather than a bool so that two sign-ins started at once
  /// await the same initialisation instead of racing to start a second.
  static Future<void>? _initialisation;

  @override
  bool get isAvailable => ApiConfig.googleServerClientId.isNotEmpty;

  @override
  Future<GoogleIdentity> signIn() async {
    if (!isAvailable) throw const GoogleSignInFailure(false);

    await (_initialisation ??= GoogleSignIn.instance.initialize(
      // The **Web** client ID. This is the audience Google mints the token
      // for, and it is what lets our server tell a token meant for us from
      // one the device happens to be holding for some other app.
      serverClientId: ApiConfig.googleServerClientId,
    ));

    var identity = await _authenticate();

    // Credential Manager caches the ID token and will hand back one it minted
    // up to an hour ago. Our server then refuses it — correctly, it is expired
    // — and the reader sees "Google sign-in didn't work" for a token Google
    // itself just gave us. Checking here is the difference between a failure
    // we can fix and one we can only report.
    //
    // `disconnect`, not `signOut`: signing out clears the plugin's own state
    // and leaves the cached credential in Play Services, so the retry is
    // handed the same stale token. Disconnecting drops the credential, at the
    // cost of asking the reader to consent again — which is the right trade on
    // a path that is otherwise a guaranteed failure, and only this path.
    if (hasExpired(identity.idToken)) {
      await GoogleSignIn.instance.disconnect();
      identity = await _authenticate();
    }

    return identity;
  }

  Future<GoogleIdentity> _authenticate() async {
    final GoogleSignInAccount account;
    try {
      account = await GoogleSignIn.instance.authenticate();
    } on GoogleSignInException catch (error) {
      throw GoogleSignInFailure(
        error.code == GoogleSignInExceptionCode.canceled,
      );
    }

    final idToken = account.authentication.idToken;
    if (idToken == null) {
      // Happens when serverClientId is wrong or the SHA-1 does not match the
      // Android OAuth client: Google signs the reader in but has nobody to
      // address the token to.
      throw const GoogleSignInFailure(false);
    }

    return GoogleIdentity(idToken: idToken, email: account.email);
  }

  @override
  Future<void> signOut() async {
    // Nothing to forget if the picker was never opened, and calling into the
    // plugin before `initialize` is the thing it asks callers not to do.
    if (_initialisation == null) return;
    await GoogleSignIn.instance.signOut();
  }
}

/// Whether a JWT's `exp` has passed, with a margin for the trip to the server.
///
/// Only the payload is read, and only the one claim. Nothing here is a
/// security check — the signature is what makes any of these claims true, and
/// verifying that is the server's job and deliberately not duplicated on a
/// device the reader controls. This is a freshness check, so that a token we
/// already know is stale is refreshed rather than sent and refused.
///
/// An unreadable token is reported as *not* expired: the server is the one
/// entitled to judge it, and guessing here would turn a token it might accept
/// into a sign-in that never gets attempted.
@visibleForTesting
bool hasExpired(String jwt, {DateTime? now}) {
  final parts = jwt.split('.');
  if (parts.length != 3) return false;

  try {
    final claims =
        jsonDecode(utf8.decode(base64Url.decode(base64Url.normalize(parts[1]))))
            as Map<String, dynamic>;
    final exp = claims['exp'];
    if (exp is! int) return false;

    final expiresAt = DateTime.fromMillisecondsSinceEpoch(
      exp * 1000,
      isUtc: true,
    );
    return (now ?? DateTime.now().toUtc())
        .add(const Duration(seconds: 30))
        .isAfter(expiresAt);
  } on FormatException {
    return false;
  }
}

final googleIdentityProvider = Provider<GoogleIdentityProvider>(
  (ref) => PlayServicesGoogleIdentity(),
);
