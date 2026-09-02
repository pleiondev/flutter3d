import 'package:vector_math/vector_math.dart';

import '../input/input_state.dart';
import '../input/input_tape.dart';
import 'fixed_step.dart';

/// Ties the clock, the input and the simulation into one call per frame.
///
/// Small enough to inline at the call site, and deliberately not inlined: the
/// order of the four things it does is the part that is easy to get wrong, and
/// every place that drives a simulation would otherwise have to get it right
/// again.
///
/// Free of Flutter on purpose, like the rest of `lib/src/game/` — the only
/// device-specific piece, draining accumulated view movement, arrives as a
/// callback.
final class GameLoop {
  GameLoop({
    required this.input,
    required this.onStep,
    FixedStep? clock,
    this.drainLook,
    this.longestFrame = 0.25,
  }) : clock = clock ?? FixedStep();

  final FixedStep clock;
  final InputState input;

  /// Runs one step of simulated time.
  final void Function(double dt) onStep;

  /// Takes view movement accumulated since the last call and writes it to the
  /// argument, leaving its own accumulator empty.
  ///
  /// A callback rather than a dependency so this file needs neither the mouse
  /// capture plugin nor a touch widget, and so a test can supply motion without
  /// either.
  final void Function(Vector2 out)? drainLook;

  final Vector2 _look = Vector2.zero();

  /// Write down what the player does, one entry per step each, while present.
  ///
  /// Here rather than at the call site because the moment matters and is easy
  /// to miss: after the step's look has been added and before the step runs,
  /// which is the one point where the latches hold what the step is about to
  /// consume. `InputTapeRecorder`'s own doc says so, and a loop that has the
  /// moment already is the place to keep it.
  ///
  /// A list, because two things want the same entry and neither should know
  /// about the other: a demo keeps the run from its start, a rewind buffer
  /// keeps the last few seconds and forgets the rest. Each gets the step
  /// written into its own tape.
  final List<InputTapeRecorder> recorders = <InputTapeRecorder>[];

  /// Drives the input from a tape instead of from the devices, while set.
  ///
  /// While a tape is playing the frame's own look is drained and dropped, not
  /// added: the recording holds what the mouse moved on every step, and adding
  /// this frame's motion on top would turn the view away from where the run
  /// went. **The devices are the application's to quiet.** A key pressed
  /// during a replay still reaches [input], because nothing here can tell a
  /// device from a tape — and should not, since that is also how a player takes
  /// over from a replay that has run out.
  ///
  /// Recording and playing at once records the tape being played, entry for
  /// entry, which is a way of copying a tape and not a mistake.
  InputTapePlayback? playback;

  /// Whether the simulation is stopped.
  ///
  /// While set, [advance] runs no steps and — this is the part that matters —
  /// **does not give the clock the time either**. The obvious implementation
  /// accumulates and then drops the backlog, which works and then reports a
  /// stall through [FixedStep.droppedSteps] that never happened: a number kept
  /// precisely so that a real one is noticeable.
  ///
  /// Held keys survive a pause and one-shot latches do not. A key still down
  /// when the game resumes is still down; a press taken while the menu was up
  /// belongs to the menu, and letting it through means the key that unpauses
  /// also fires the weapon.
  bool paused = false;

  bool _wasPaused = false;

  /// The longest real frame the simulation will accept, in seconds.
  ///
  /// **A quarter of a second, and the number belongs here rather than at each
  /// call site.** A frame that took longer than this is not a slow frame, it is
  /// a window that was dragged, a laptop that was shut, or a debugger that was
  /// sitting at a breakpoint — and handing the whole of it to a fixed step is
  /// asking for fifteen seconds of simulation in one frame, which arrives as
  /// everything in the world teleporting.
  ///
  /// Three games clamped this themselves, at `0.25`, at `0.1`, and — in one —
  /// not at all.
  final double longestFrame;

  /// How much time the last [advance] actually took, after clamping.
  ///
  /// **What everything else in the frame must use.** Particles, camera easing
  /// and anything else advanced beside the simulation are showing the world the
  /// simulation is in; given the raw frame time instead they run ahead of it.
  /// All three games did exactly that — `_particles.advance(dt)` with the
  /// unclamped number, one line after `advance(dt.clamp(0.0, 0.25))` — so after
  /// a hitch the smoke was somewhere the car had not been.
  ///
  /// Zero while paused, because no time passed in the game.
  double get lastFrame => _lastFrame;
  double _lastFrame = 0.0;

  /// How far through the current step the next frame should draw.
  double get alpha => clock.alpha;

  /// Advances by [dt] real seconds and returns how many steps ran.
  int advance(double dt) {
    if (paused) {
      _wasPaused = true;
      _lastFrame = 0.0;
      // Taken and thrown away. A pause can last minutes, and motion that piled
      // up behind a menu would arrive as one turn of the camera on the frame
      // the game came back. This is the opposite of what a frame too short to
      // step does below, and the difference is how long the wait is: there,
      // the motion belongs to the step that is about to happen.
      _look.setZero();
      drainLook?.call(_look);
      // The one-shot half of the input, for the reason on [paused].
      input.endStep();
      return 0;
    }

    if (_wasPaused) {
      _wasPaused = false;
      // The wall clock kept going and none of that time happened in the game.
      // `FixedStep.reset`'s own doc says it exists for this, and until now
      // nothing called it.
      clock.reset();
    }

    // Clamped once, here, and published as [lastFrame] so that nothing else in
    // the frame has to remember to do it — or gets to do it differently.
    _lastFrame = dt.isNaN ? 0.0 : dt.clamp(0.0, longestFrame);
    final steps = clock.advance(_lastFrame);
    if (steps == 0) {
      // Nothing is drained. On a display faster than the simulation most frames
      // run no step at all, and taking the mouse motion here would throw it
      // away — the accumulator on the other side of [drainLook] is the right
      // place for it to wait.
      return 0;
    }

    _look.setZero();
    drainLook?.call(_look);

    // View movement is spread across the steps rather than given to the first.
    // It happened over the whole frame, and handing it all to one step makes a
    // frame that ran three steps turn the camera in a single jerk.
    final perStep = 1.0 / steps;
    final lookX = _look.x * perStep;
    final lookY = _look.y * perStep;

    for (var i = 0; i < steps; i++) {
      final tape = playback;
      if (tape != null && !tape.isFinished) {
        tape.applyTo(input);
      } else {
        input.addLook(lookX, lookY);
      }
      for (var r = 0; r < recorders.length; r++) {
        recorders[r].record(input);
      }
      input.beginStep();
      onStep(clock.stepSeconds);
      input.endStep();
    }

    return steps;
  }
}
