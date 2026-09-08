/// Synchronization status states representing client-server sync progress.
library;

/// Base state for synchronization status.
sealed class SyncStatus {
  const SyncStatus();
}

/// No sync operation is currently active.
final class SyncIdle extends SyncStatus {
  const SyncIdle();
}

/// A synchronization operation is currently in progress.
final class SyncInProgress extends SyncStatus {
  const SyncInProgress();
}

/// A synchronization operation failed with an error [message].
final class SyncFailed extends SyncStatus {
  const SyncFailed(this.message);

  final String message;
}

/// A synchronization operation completed successfully.
final class SyncComplete extends SyncStatus {
  const SyncComplete({
    required this.pushed,
    required this.pulled,
  });

  /// Number of local changes pushed to the server.
  final int pushed;

  /// Number of remote changes pulled from the server.
  final int pulled;
}
