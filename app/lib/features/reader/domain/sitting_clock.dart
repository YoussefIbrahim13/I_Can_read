/// How long the book has actually been in front of the reader.
///
/// Pulled out of the reader screen so the arithmetic that decides what counts
/// as reading can be tested without a PDF, a device, or a wait.
library;

/// A source of monotonically increasing time.
typedef Ticks = Duration Function();

/// A stopwatch that only runs while someone is looking at the page.
///
/// Counts on a monotonic clock rather than the difference between two
/// timestamps: a device whose wall clock jumps mid-sitting — this machine's
/// runs an hour fast — must not be able to turn ten minutes of reading into
/// seventy.
class SittingClock {
  /// Starts running immediately: the reader opened the book to read it.
  SittingClock({Ticks? ticks}) : _ticks = ticks ?? _sinceLaunch {
    _startedAt = _ticks();
  }

  /// One process-wide stopwatch, so every clock reads the same monotonic line.
  static final Stopwatch _process = Stopwatch()..start();
  static Duration _sinceLaunch() => _process.elapsed;

  final Ticks _ticks;

  /// Where the current run began, or null while paused.
  Duration? _startedAt;

  /// Time from runs already ended.
  Duration _banked = Duration.zero;

  /// Everything counted so far, whether running or paused.
  Duration get elapsed {
    final startedAt = _startedAt;
    if (startedAt == null) return _banked;
    return _banked + (_ticks() - startedAt);
  }

  /// Stops counting. Idempotent, because the lifecycle reports `inactive` and
  /// `paused` for a single trip to the home screen.
  void pause() {
    final startedAt = _startedAt;
    if (startedAt == null) return;
    _banked += _ticks() - startedAt;
    _startedAt = null;
  }

  /// Starts counting again from now, keeping what came before.
  void resume() => _startedAt ??= _ticks();
}
