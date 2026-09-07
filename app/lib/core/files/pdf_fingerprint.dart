import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';

/// SHA-256 of a file, computed off the UI isolate.
///
/// This is the identity a book keeps across devices: re-adding the same PDF on
/// a new phone matches this hash and relinks to the existing plan instead of
/// starting a fresh book.
///
/// Runs in an isolate via [compute] because hashing a few hundred megabytes is
/// enough CPU work to drop frames if done inline, and reads the file in chunks
/// so a large scan is never held in memory all at once.
Future<String> hashFile(String absolutePath) =>
    compute(_hashFileInIsolate, absolutePath);

Future<String> _hashFileInIsolate(String absolutePath) async {
  late Digest digest;
  final input = sha256.startChunkedConversion(
    ChunkedConversionSink<Digest>.withCallback(
      (digests) => digest = digests.single,
    ),
  );

  final stream = File(absolutePath).openRead();
  await for (final chunk in stream) {
    input.add(chunk);
  }
  input.close();

  return digest.toString();
}
