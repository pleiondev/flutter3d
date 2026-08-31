/// Turns the display's variable frame time into a simulation that always
/// advances by the same amount.
///
/// ## Why this exists before anything it drives
///
/// Gravity, acceleration and jumping are integration, and integrating over a
/// variable step makes the result depend on the frame rate: the same jump
/// reaches a different height at 60 Hz and at 144 Hz. That is not a rounding
/// difference — it is a different game. And it cannot be fixed later, because by
/// then every tuning number has been chosen to compensate for it on whatever
/// machine the tuning was done on.
///
/// The fix is the standard one. Accumulate real time, spend it in whole steps of
/// a fixed size, and hand the renderer the leftover fraction so it can draw
/// between two simulated states instead of snapping to the last one.
final class FixedStep {
  FixedStep({
    this.stepSeconds = 1.0 / 60.0,
    this.maxStepsPerFrame = 5,
  })  : assert(stepSeconds > 0.0),
        assert(maxStepsPerFrame > 0);

  /// How much simulated time one step covers.
  final double stepSeconds;

  /// The ceiling on steps run for a single frame.
  ///
  /// Without it, a frame that took thirty seconds — a breakpoint, a laptop lid,
  /// a stalled asset load — asks for eighteen hundred steps at once, which takes
  /// longer than thirty seconds to run and so asks for even more next frame. The
  /// simulation never catches up and the application appears to hang. Five is
  /// enough to absorb an ordinary hitch and small enough that the spiral cannot
  /// start.
  final int maxStepsPerFrame;

  double _accumulator = 0.0;
  double _alpha = 0.0;
  int _droppedSteps = 0;

  /// Where the current frame sits between the last two simulated states, in
  /// `[0, 1)`.
  ///
  /// A renderer that ignores this and draws the latest state is visibly wrong on
  /// a display faster than the simulation: motion arrives in 60 Hz jumps on a
  /// 120 Hz screen, which reads as stutter even though nothing is dropped.
  double get alpha => _alpha;

  /// Simulated time that was thrown away because [maxStepsPerFrame] was hit.
  ///
  /// Reported rather than hidden. A number that keeps climbing during normal
  /// play means the simulation cannot keep up, and that is worth seeing in the
  /// frame overlay rather than discovering as "the game feels slow".
  int get droppedSteps => _droppedSteps;

  /// Adds [dt] seconds and returns how many steps the caller should run now.
  ///
  /// Time that does not fill a whole step is kept for the next call, so nothing
  /// is lost to rounding across a long session.
  int advance(double dt) {
    // A clock that goes backwards or produces a NaN is not this class's problem
    // to diagnose, but it must not corrupt the accumulator on the way through.
    if (dt.isFinite && dt > 0.0) {
      _accumulator += dt;
    }

    var steps = 0;
    while (_accumulator >= stepSeconds && steps < maxStepsPerFrame) {
      _accumulator -= stepSeconds;
      steps++;
    }

    if (_accumulator >= stepSeconds) {
      // Out of budget. Drop the backlog instead of carrying it: catching up is
      // what starts the spiral described on [maxStepsPerFrame].
      final dropped = _accumulator ~/ stepSeconds;
      _droppedSteps += dropped;
      _accumulator -= dropped * stepSeconds;
    }

    // The loop leaves the accumulator below one step; only floating-point error
    // can push it out of range, and only by an amount too small to see.
    if (_accumulator < 0.0) _accumulator = 0.0;
    _alpha = _accumulator / stepSeconds;
    if (_alpha >= 1.0) _alpha = 0.0;

    return steps;
  }

  /// Forgets accumulated time without running it.
  ///
  /// For resuming from a pause: the wall clock kept going, but none of that time
  /// happened in the game.
  void reset() {
    _accumulator = 0.0;
    _alpha = 0.0;
  }
}
