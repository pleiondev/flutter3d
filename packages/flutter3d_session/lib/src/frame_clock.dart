import 'package:flutter/scheduler.dart' show Ticker;

/// How long since the last frame, from a [Ticker]'s clock.
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
/// It does not clamp. A frame longer than a simulation will accept is the
/// simulation's business — `GameLoop` refuses it and says how much it took —
/// and a clock that quietly shortened a two-second stall would leave anything
/// reading it in disagreement with anything reading the loop.
final class FrameClock {
  /// Seconds since the previous frame, and nought on the first one.
  ///
  /// Call once a frame: this both answers and advances.
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
