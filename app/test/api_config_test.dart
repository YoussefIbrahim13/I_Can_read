import 'package:flutter_test/flutter_test.dart';
import 'package:i_can_read/core/config/api_config.dart';

void main() {
  String resolve(String? value, {bool isRelease = false}) =>
      ApiConfig.resolve(value: value, isRelease: isRelease);

  group('when nothing was supplied', () {
    test('a development build falls back to the emulator loopback', () {
      expect(resolve(''), ApiConfig.developmentDefault);
    });

    test('a release build refuses to start', () {
      // The same rule the server applies to its signing key: a misconfigured
      // build should fail while somebody is still watching it, not quietly
      // point a shipped app at a developer's laptop.
      expect(
        () => resolve('', isRelease: true),
        throwsA(isA<ApiConfigError>()),
      );
    });
  });

  group('what it will accept', () {
    test('an https origin', () {
      expect(resolve('https://api.example.com'), 'https://api.example.com');
    });

    test('a port and a path prefix', () {
      expect(
        resolve('https://example.com:8443/icanread'),
        'https://example.com:8443/icanread',
      );
    });

    test('a trailing slash, which it drops', () {
      // Paths are joined as '$baseUrl/api/…', and '//api/…' is routed by some
      // hosts and 404'd by others.
      expect(resolve('https://api.example.com/'), 'https://api.example.com');
    });

    test('plaintext to the machine the app is running on', () {
      for (final host in ['localhost', '127.0.0.1', '10.0.2.2']) {
        expect(resolve('http://$host:5000'), 'http://$host:5000');
      }
    });
  });

  group('what it refuses', () {
    test('plaintext to a remote host', () {
      // Everything on this connection is a password, a token, or the record of
      // what somebody reads.
      expect(
        () => resolve('http://api.example.com'),
        throwsA(isA<ApiConfigError>()),
      );
    });

    test('a scheme that is not http or https', () {
      expect(
        () => resolve('ftp://api.example.com'),
        throwsA(isA<ApiConfigError>()),
      );
    });

    test('a host with no scheme', () {
      expect(
        () => resolve('api.example.com'),
        throwsA(isA<ApiConfigError>()),
      );
    });

    test('a query string, which would be dropped silently when paths are added',
        () {
      expect(
        () => resolve('https://api.example.com?token=abc'),
        throwsA(isA<ApiConfigError>()),
      );
    });
  });
}
