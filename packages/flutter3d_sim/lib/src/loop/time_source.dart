/// Where the loop's time comes from.
library;

/// How many seconds of simulated time a displayed frame brings: the loop's
/// clock.
///
/// **One loop, an abstract source.** The loop steps at the world's fixed
/// rate whatever drives it, so determinism holds under every source; what
/// changes is how much time a frame hands it, and so how many steps it
/// runs. A game runs on [TimeSource.realTime]; a laboratory slows or
/// speeds time with [TimeSource.scaled], or steps it by hand with
/// [TimeSource.manual]; a digital twin replays a telemetry log at the pace
/// it was recorded with [TimeSource.log].
///
/// The loop asks once per frame it draws, with the vsync timestamps of the
/// frame drawn before and of this one ([elapsed]); `FrameCadence` decides
/// which refreshes are drawn and asks the same question.
///
/// `base`, so a member added later arrives with a default: a source of a
/// game's own extends this.
abstract base class TimeSource {
  const TimeSource();

  /// The wall clock, as the display's vsync measures it.
  const factory TimeSource.realTime() = _RealTime;

  /// The wall clock times [factor]: a half is half speed, two is double.
  /// Throws an [ArgumentError] for a factor that is not finite or is below
  /// nought; nought holds the world still.
  factory TimeSource.scaled(double factor) = _Scaled;

  /// The gaps of a recorded log, one a frame: [timestamps] in seconds,
  /// ascending, each frame advancing to the next one. Throws an
  /// [ArgumentError] for timestamps that go back.
  factory TimeSource.log(List<double> timestamps) = LogTime;

  /// Time that moves only when told to ([ManualTime.advance]).
  factory TimeSource.manual() = ManualTime;

  /// The simulated seconds between the frame drawn at [from] and the one at
  /// [to], vsync timestamps both, which a source is free to ignore.
  double elapsed(Duration from, Duration to);

  /// Forgets anything the source has kept between frames: a game that was
  /// away. Does nothing by default.
  void reset() {}
}

final class _RealTime extends TimeSource {
  const _RealTime();

  @override
  double elapsed(Duration from, Duration to) =>
      (to - from).inMicroseconds / 1e6;

  @override
  String toString() => 'TimeSource.realTime()';
}

final class _Scaled extends TimeSource {
  _Scaled(this.factor) {
    if (!factor.isFinite || factor < 0.0) {
      throw ArgumentError.value(factor, 'factor', 'nought or more');
    }
  }

  final double factor;

  @override
  double elapsed(Duration from, Duration to) =>
      (to - from).inMicroseconds / 1e6 * factor;

  @override
  String toString() => 'TimeSource.scaled($factor)';
}

/// A recorded log's time: each frame advances to the log's next timestamp,
/// whatever the wall clock did.
///
/// **For a replay of a twin's data at the pace it arrived.** A frame
/// brings the gap to the next sample, so the simulation is where the log
/// was when it took that sample; once the log runs out, frames bring
/// nothing ([isFinished]).
final class LogTime extends TimeSource {
  /// A source walking [timestamps], seconds, ascending.
  LogTime(List<double> timestamps)
    : timestamps = List<double>.unmodifiable(timestamps) {
    for (var i = 1; i < this.timestamps.length; i++) {
      if (!(this.timestamps[i] >= this.timestamps[i - 1])) {
        throw ArgumentError.value(
          this.timestamps[i],
          'timestamps',
          'goes back from ${this.timestamps[i - 1]} at $i',
        );
      }
    }
  }

  /// The log's timestamps, seconds.
  final List<double> timestamps;

  int _at = 0;

  /// The index of the timestamp the last frame reached.
  int get position => _at;

  /// Whether every gap of the log has been handed out.
  bool get isFinished => _at >= timestamps.length - 1;

  @override
  double elapsed(Duration from, Duration to) {
    if (isFinished) return 0.0;
    final gap = timestamps[_at + 1] - timestamps[_at];
    _at++;
    return gap;
  }

  /// Back to the log's first timestamp.
  @override
  void reset() => _at = 0;

  @override
  String toString() => 'TimeSource.log(${timestamps.length} timestamps)';
}

/// Time a person or a test moves by hand: a laboratory that steps when the
/// student presses "step", a test that knows exactly how much time passed.
///
/// What [advance] queued is handed to the next frame, all of it, and the
/// frames after bring nothing until it is called again.
final class ManualTime extends TimeSource {
  ManualTime();

  double _owed = 0.0;

  /// Seconds queued for the next frame.
  double get pending => _owed;

  /// Queues [seconds] for the next frame. Throws an [ArgumentError] for a
  /// value that is not finite or is below nought: time is not taken back
  /// here, a rewind is the loop's (`EngineLoop.rewindTo`).
  void advance(double seconds) {
    if (!seconds.isFinite || seconds < 0.0) {
      throw ArgumentError.value(seconds, 'seconds', 'nought or more');
    }
    _owed += seconds;
  }

  @override
  double elapsed(Duration from, Duration to) {
    final owed = _owed;
    _owed = 0.0;
    return owed;
  }

  /// Drops what was queued.
  @override
  void reset() => _owed = 0.0;

  @override
  String toString() => 'TimeSource.manual()';
}
