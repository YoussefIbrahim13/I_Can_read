import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Thrown when the build was given a server address it cannot use.
class ApiConfigError extends Error {
  ApiConfigError(this.message);

  final String message;

  @override
  String toString() => 'ApiConfigError: $message';
}

/// Where the API lives, supplied at build time.
///
/// ```
/// flutter run  --dart-define=API_BASE_URL=http://192.168.1.20:5000
/// flutter build apk --dart-define=API_BASE_URL=https://api.example.com
/// ```
///
/// A compile-time constant rather than something the reader can type. A field
/// for "server address" in settings is a field an attacker can talk somebody
/// into filling in, and what would go to it is an email and a password.
abstract final class ApiConfig {
  static const _fromEnvironment = String.fromEnvironment('API_BASE_URL');

  /// The Android emulator's loopback to the machine running the API, which is
  /// what a developer wants without having to say so.
  static const developmentDefault = 'http://10.0.2.2:5203';

  /// The **Web** OAuth client ID, which Google mints the ID token for.
  ///
  /// Not the Android client ID — that one never appears in code, because
  /// Google matches it by package name and signing certificate instead. And
  /// not a secret: this exact string ships inside the APK. It is committed
  /// rather than passed in because it identifies the Google Cloud project,
  /// which does not change between a debug build and a release one.
  ///
  /// Empty turns Google sign-in off, and the button disappears with it.
  static const googleServerClientId = String.fromEnvironment(
    'GOOGLE_SERVER_CLIENT_ID',
    defaultValue:
        '152219793195-hvfftji3qjbrmc0j3nm32trdr8n8qkf5.apps.googleusercontent.com',
  );

  /// Hosts that are this machine under another name. Nothing sent to one of
  /// these leaves the device or the machine hosting it.
  static const _loopbackHosts = {
    'localhost',
    '127.0.0.1',
    '::1',
    // The Android emulator's and Genymotion's aliases for the host.
    '10.0.2.2',
    '10.0.3.2',
  };

  /// Works out the base URL, or explains why it cannot.
  ///
  /// [value] and [isRelease] exist so the rules can be tested; the app calls
  /// this with neither.
  static String resolve({String? value, bool isRelease = kReleaseMode}) {
    final raw = (value ?? _fromEnvironment).trim();

    if (raw.isEmpty) {
      // Deliberately not falling back to the development address in a release
      // build. The same rule the server applies to its signing key: a
      // misconfigured build should fail while somebody is still watching,
      // rather than at the first reader's first sign-in.
      if (isRelease) {
        throw ApiConfigError(
          'API_BASE_URL was not set. Pass --dart-define=API_BASE_URL=https://…',
        );
      }
      return developmentDefault;
    }

    final uri = Uri.tryParse(raw);
    if (uri == null || !uri.isAbsolute || uri.host.isEmpty) {
      throw ApiConfigError('API_BASE_URL is not an absolute URL: "$raw"');
    }
    if (uri.scheme != 'http' && uri.scheme != 'https') {
      throw ApiConfigError('API_BASE_URL must be http or https: "$raw"');
    }
    // Plaintext is fine when the packets never reach a network, and nowhere
    // else: everything on this connection is a password, a token, or the list
    // of what somebody reads.
    if (uri.scheme == 'http' && !_loopbackHosts.contains(uri.host)) {
      throw ApiConfigError(
        'API_BASE_URL must use https for a remote host: "$raw"',
      );
    }
    if (uri.hasQuery || uri.hasFragment) {
      throw ApiConfigError('API_BASE_URL must be a bare origin: "$raw"');
    }

    // Paths are joined as '$baseUrl/api/…', so a trailing slash would produce
    // '//api/…' — which some hosts route and some do not.
    return raw.endsWith('/') ? raw.substring(0, raw.length - 1) : raw;
  }
}

/// The API's base URL. Overridden in tests that stand up a fake server.
final apiBaseUrlProvider = Provider<String>((ref) => ApiConfig.resolve());
