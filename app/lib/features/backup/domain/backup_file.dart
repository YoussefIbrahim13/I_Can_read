/// The backup file format, as pure functions.
///
/// A backup is the reader's way out. It is what a guest with no account has
/// instead of an account, and it is why device backup can stay switched off:
/// Android's would have uploaded the PDFs, which is the one thing this app
/// promises never to do.
library;

import 'dart:convert';

import '../../../core/sync/sync_models.dart';

/// Bumped only when an older file could be read wrongly rather than not at all.
const backupFormatVersion = 1;

/// Marks the file as ours before anything is read out of it.
const _magic = 'i_can_read.backup';

/// Why a file could not be restored.
enum BackupProblem {
  /// Not JSON, or not this app's JSON.
  notABackup,

  /// Written by a newer version of the app than this one.
  ///
  /// Refused rather than guessed at: a format we do not know could carry a
  /// field whose absence here means something different, and silently dropping
  /// it would lose the reader's data while reporting success.
  tooNew,
}

class BackupException implements Exception {
  const BackupException(this.problem);

  final BackupProblem problem;

  @override
  String toString() => 'BackupException($problem)';
}

/// The payload plus the header that makes it identifiable.
///
/// JSON rather than the SQLite file itself. The database carries device-local
/// rows — where each PDF sits on *this* phone, the outbox — that mean nothing
/// anywhere else, and a schema version that would have to match exactly. JSON
/// is the same shape the server already speaks, so one merge serves both.
String encodeBackup(SyncPayload data, {required DateTime createdAt}) {
  return const JsonEncoder.withIndent('  ').convert({
    'format': _magic,
    'formatVersion': backupFormatVersion,
    'createdAt': wireInstant(createdAt),
    'data': data.toJson(),
  });
}

/// Reads a backup file, or says why it cannot.
SyncPayload decodeBackup(String contents) {
  final Object? parsed;
  try {
    parsed = jsonDecode(contents);
  } on FormatException {
    throw const BackupException(BackupProblem.notABackup);
  }

  if (parsed is! Map<String, dynamic> || parsed['format'] != _magic) {
    throw const BackupException(BackupProblem.notABackup);
  }

  final version = parsed['formatVersion'];
  if (version is! int) {
    throw const BackupException(BackupProblem.notABackup);
  }
  if (version > backupFormatVersion) {
    throw const BackupException(BackupProblem.tooNew);
  }

  final data = parsed['data'];
  if (data is! Map<String, dynamic>) {
    throw const BackupException(BackupProblem.notABackup);
  }

  try {
    return SyncPayload.fromJson(data);
  } on Object {
    // A file that says it is ours but does not hold what ours holds. The reader
    // can do nothing about the difference, so it is simply not a backup.
    throw const BackupException(BackupProblem.notABackup);
  }
}

/// What the file is called when the reader is asked where to put it.
///
/// Dated, because the first thing anyone does with a backup is make a second
/// one, and two files called the same thing is how the wrong one gets restored.
String backupFileName(DateTime createdAt) {
  final date = wireDate(createdAt);
  return 'yaqra-backup-$date.json';
}

/// How much a backup holds, for the line that reports it.
int backupItemCount(SyncPayload data) =>
    data.books.length +
    data.plans.length +
    data.sessions.length +
    data.logEntries.length;
