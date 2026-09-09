import 'package:flutter_test/flutter_test.dart';
import 'package:i_can_read/features/reader/domain/sitting_clock.dart';

/// A hand-cranked monotonic clock, so a test can spend an hour in a line.
class _FakeTicks {
  var now = Duration.zero;

  Duration call() => now;

  void advance(Duration by) => now += by;
}

void main() {
  late _FakeTicks ticks;
  late SittingClock clock;

  setUp(() {
    ticks = _FakeTicks();
    clock = SittingClock(ticks: ticks.call);
  });

  test('starts at zero and runs from the moment the book opens', () {
    expect(clock.elapsed, Duration.zero);

    ticks.advance(const Duration(minutes: 10));

    expect(clock.elapsed, const Duration(minutes: 10));
  });

  test('a night in the background is not an evening of reading', () {
    ticks.advance(const Duration(minutes: 10));
    clock.pause();

    ticks.advance(const Duration(hours: 8));

    expect(clock.elapsed, const Duration(minutes: 10));
  });

  test('reading resumes where it stopped rather than starting over', () {
    ticks.advance(const Duration(minutes: 10));
    clock.pause();
    ticks.advance(const Duration(hours: 8));
    clock.resume();

    ticks.advance(const Duration(minutes: 5));

    expect(clock.elapsed, const Duration(minutes: 15));
  });

  test('several trips away each cost nothing', () {
    for (var i = 0; i < 3; i++) {
      ticks.advance(const Duration(minutes: 2));
      clock.pause();
      ticks.advance(const Duration(minutes: 30));
      clock.resume();
    }

    expect(clock.elapsed, const Duration(minutes: 6));
  });

  test('pausing twice does not bank the same stretch twice', () {
    // The lifecycle reports inactive and then paused for one trip away.
    ticks.advance(const Duration(minutes: 10));
    clock.pause();
    clock.pause();

    expect(clock.elapsed, const Duration(minutes: 10));
  });

  test('resuming while already running does not restart the count', () {
    ticks.advance(const Duration(minutes: 10));
    clock.resume();
    ticks.advance(const Duration(minutes: 5));

    expect(clock.elapsed, const Duration(minutes: 15));
  });

  test('a sitting spent entirely in the background counts as nothing', () {
    clock.pause();
    ticks.advance(const Duration(hours: 3));

    expect(clock.elapsed, Duration.zero);
  });
}
