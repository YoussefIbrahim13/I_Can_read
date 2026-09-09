import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/auth_state.dart';
import '../../../core/db/app_database.dart';
import '../../../core/sync/sync_models.dart';
import '../../../core/sync/sync_engine.dart';
import '../domain/backup_file.dart';

/// Where the backup screen's two buttons are.
sealed class BackupState {
  const BackupState();
}

final class BackupIdle extends BackupState {
  const BackupIdle();
}

final class BackupWorking extends BackupState {
  const BackupWorking();
}

/// A file was written. [items] is what went into it.
final class BackupExported extends BackupState {
  const BackupExported(this.items);
  final int items;
}

/// A file was folded in. [items] is what it held.
final class BackupImported extends BackupState {
  const BackupImported(this.items);
  final int items;
}

final class BackupFailed extends BackupState {
  const BackupFailed(this.problem);

  /// Null when it was not the file's fault — no room to write, a read that
  /// failed halfway.
  final BackupProblem? problem;
}

/// Writing the library out to a file, and reading one back in.
class BackupController extends Notifier<BackupState> {
  @override
  BackupState build() => const BackupIdle();

  AppDatabase get _db => ref.read(appDatabaseProvider);

  /// Writes everything worth keeping to a file the reader chooses.
  ///
  /// Where it goes is their business — a cloud folder, a memory card, a
  /// message to themselves. The app deliberately does not upload it anywhere.
  Future<void> export() async {
    state = const BackupWorking();

    try {
      final data = await _db.exportLocalData();
      final now = DateTime.now();
      final contents = encodeBackup(data, createdAt: now);

      final saved = await FilePicker.saveFile(
        fileName: backupFileName(now),
        bytes: Uint8List.fromList(utf8.encode(contents)),
        mimeType: 'application/json',
      );
      // Null means the reader closed the dialog. Backing out of a save is not
      // a failure, and reporting one would make it look like something broke.
      if (saved == null) {
        state = const BackupIdle();
        return;
      }

      state = BackupExported(backupItemCount(data));
    } on Object {
      state = const BackupFailed(null);
    }
  }

  /// Folds a chosen backup into this phone.
  Future<void> import() async {
    final picked = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: const ['json'],
    );
    if (picked == null) return;

    state = const BackupWorking();

    final SyncPayload data;
    try {
      final bytes = <int>[];
      await for (final chunk in picked.readAsByteStream()) {
        bytes.addAll(chunk);
      }
      data = decodeBackup(utf8.decode(bytes));
    } on BackupException catch (error) {
      state = BackupFailed(error.problem);
      return;
    } on Object {
      state = const BackupFailed(null);
      return;
    }

    try {
      await _db.importBackup(data);
    } on Object {
      state = const BackupFailed(null);
      return;
    }

    // A restore while signed in has to reach the account too, or the reader
    // has their books back on this phone and nowhere else — and the next pull
    // would look like the server disagreeing with them.
    if (ref.read(authStateProvider) != null) {
      await _db.seedOutboxFromLocalData();
      await ref.read(syncControllerProvider.notifier).syncNow();
    }

    state = BackupImported(backupItemCount(data));
  }

  void reset() => state = const BackupIdle();
}

final backupControllerProvider =
    NotifierProvider<BackupController, BackupState>(BackupController.new);
