import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/authenticated_http.dart';
import 'sync_models.dart';

/// The three calls the sync engine makes.
///
/// An interface rather than the concrete client so the engine can be driven
/// against a stand-in server: the merge rules and the cursor are the parts
/// worth testing, and neither of them is about HTTP.
abstract interface class SyncApi {
  Future<SyncPullResponse> pull({DateTime? since});
  Future<SyncPushResponse> push(SyncPayload payload);
  Future<BookDto?> lookupByHash(String sha256);
}

/// HTTP calls to the three sync endpoints.
///
/// All serialisation lives here so the engine works with typed objects only.
class SyncClient implements SyncApi {
  SyncClient({required this.http});

  final AuthenticatedHttp http;

  /// Everything of the reader's that changed since [since].
  ///
  /// Omit [since] on a new device to get everything.
  @override
  Future<SyncPullResponse> pull({DateTime? since}) async {
    final path = since == null
        ? '/api/sync/pull'
        // `wireInstant`, not `toIso8601String`: a cursor sent without a zone
        // would be read as the server's local time, and a pull would skip
        // however many hours the phone happens to be offset by.
        : '/api/sync/pull?since=${Uri.encodeComponent(wireInstant(since))}';
    final response = await http.get(path);
    _assertOk(response.statusCode, response.body);
    return SyncPullResponse.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
    );
  }

  /// Pushes local changes to the server.
  @override
  Future<SyncPushResponse> push(SyncPayload payload) async {
    final response = await http.post('/api/sync/push', payload.toJson());
    _assertOk(response.statusCode, response.body);
    return SyncPushResponse.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
    );
  }

  /// New-device relink: "I have this file — do I already own the book?"
  @override
  Future<BookDto?> lookupByHash(String sha256) async {
    final response = await http.post(
      '/api/books/lookup-by-hash',
      {'sha256': sha256},
    );
    _assertOk(response.statusCode, response.body);
    final json = jsonDecode(response.body) as Map<String, dynamic>;
    return LookupByHashResponse.fromJson(json).book;
  }

  void _assertOk(int statusCode, String body) {
    if (statusCode >= 200 && statusCode < 300) return;
    throw SyncException(statusCode, body);
  }
}

/// Exception thrown when a sync endpoint returns a non-success status.
class SyncException implements Exception {
  const SyncException(this.statusCode, this.body);
  final int statusCode;
  final String body;

  @override
  String toString() => 'SyncException($statusCode): $body';
}

/// Shared sync client, using the authenticated HTTP wrapper.
final syncClientProvider = Provider<SyncApi>((ref) {
  return SyncClient(http: ref.watch(authenticatedHttpProvider));
});
