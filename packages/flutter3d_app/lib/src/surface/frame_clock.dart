import 'package:clock/clock.dart' show Clock, clock;
import 'package:flutter/scheduler.dart' show Ticker;

/// How long since the last frame, measured on the wall clock.
///
/// **Five applications had written this out, and the first frame differed in
/// three ways.** A ticker hands out the time since it started, not the time
/// since the last frame, so every one of them kept a `Duration` and subtracted
/// — and every one of them had to answer the same question on the frame where
/// there is no previous frame to subtract from. Three said a sixtieth of a
/// second, spelled `1 / 60`, `1.0 / 60.0` and `1 / 60` again; one said nought.
///
/// **Nought is the answer here, and the disagreement is why it is worth
/// stating.** A sixtieth is a guess about a machine nobody has measured yet: on
/// the first frame the application has run for no time at all, nothing has
/// moved, and a simulation asked to advance a sixtieth advances through a world
/// the player has not been shown. Every one of the five recovers on the second
/// frame either way; the difference is whether the first frame is a measurement
/// or an assumption.
///
/// **The ticker's own timestamp is not the clock, and that is the second thing
/// the five had in common.** What a [Ticker] hands to its callback is the
/// frame's *scheduled* time — the vsync the frame is aimed at — not the moment
/// the callback runs. While the GPU keeps up the two agree. When it falls
/// behind, frames get scheduled in pairs: the timestamps step by a whole
/// interval, then by almost nothing, then by a whole interval again, and every
/// motion integrated against their differences staggers in time with them —
/// interpolation, particles, a camera's smoothing — exactly when the machine is
/// already struggling. [tick] measures the wall instead, through `package:clock`
/// rather than a `Stopwatch` so that a widget test's `pump` still advances it.
/// [secondsSince] keeps taking a `Duration` for the caller with a clock of its
/// own, and for the tests.
///
/// It does not clamp. A frame longer than a simulation will accept is the
/// simulation's business — `GameLoop` refuses it and says how much it took —
/// and a clock that quietly shortened a two-second stall would leave anything
/// reading it in disagreement with anything reading the loop.
final class FrameClock {
  /// A clock reading the wall, or [wallClock] to read another.
  ///
  /// Null reads the ambient `package:clock` clock, which is real time in an
  /// application and fake time under `flutter_test`.
  FrameClock({Clock? wallClock}) : _wall = wallClock;

  final Clock? _wall;

  /// Seconds since the previous [tick], on the wall clock, and nought on the
  /// first one.
  ///
  /// Call once a frame, from the ticker's callback, ignoring what the ticker
  /// passed: that is the frame's scheduled time, not the present, and the
  /// difference between two of them is not a frame's length under load.
  double tick() {
    final wall = _wall ?? clock;
    return secondsSince(
      Duration(microseconds: wall.now().microsecondsSinceEpoch),
    );
  }

  /// Seconds since the previous frame, and nought on the first one, from a
  /// timestamp the caller measured.
  ///
  /// Call once a frame: this both answers and advances. [tick] is this with the
  /// wall clock as the caller.
  double secondsSince(Duration now) {
    final seconds = _last == null ? 0.0 : (now - _last!).inMicroseconds / 1e6;
    _last = now;
    _elapsed += seconds;
    if (seconds > 0.0) _fps = _fps * 0.9 + (1.0 / seconds) * 0.1;
    return seconds;
  }

  /// Seconds since the first frame, summed from what was handed out.
  ///
  /// The sum rather than the ticker's own elapsed, so that anything drawn from
  /// it — a fog that alternates, a torch that flickers — agrees exactly with
  /// what everything else this frame was told.
  double get elapsed => _elapsed;

  /// Frames a second, smoothed.
  ///
  /// Smoothed because the raw number is unreadable: one long frame in sixty
  /// makes a counter jump to a figure that was true for a sixtieth of a second,
  /// and a player watching for a stutter cannot see it in a number that moves
  /// every frame.
  double get fps => _fps;

  /// Forgets the last frame, so the next one is a first frame again.
  ///
  /// For a game that was away — a level being loaded, a window that was not
  /// drawing — where the honest answer to "how long since the last frame" is
  /// the same as it was at launch.
  void reset() => _last = null;

  /// Null until the first frame, which is what makes a first frame knowable.
  ///
  /// Not `Duration.zero`: a ticker can legitimately hand out zero, and the four
  /// applications that compared against it were one lucky frame away from
  /// treating a real frame as the first one for ever.
  Duration? _last;

  double _elapsed = 0.0;
  double _fps = 0.0;
}
