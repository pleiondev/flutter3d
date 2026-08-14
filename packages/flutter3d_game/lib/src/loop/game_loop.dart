import 'package:vector_math/vector_math.dart';

import '../input/input_state.dart';
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

  /// How far through the current step the next frame should draw.
  double get alpha => clock.alpha;

  /// Advances by [dt] real seconds and returns how many steps ran.
  int advance(double dt) {
    if (paused) {
      _wasPaused = true;
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

    final steps = clock.advance(dt);
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
      input.addLook(lookX, lookY);
      input.beginStep();
      onStep(clock.stepSeconds);
      input.endStep();
    }

    return steps;
  }
}
