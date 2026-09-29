import 'package:flame/components.dart';
import 'package:flame/game.dart';
import 'package:flutter3d_sim/flutter3d_sim.dart' show FixedStep;

/// A component whose game logic runs in the game's fixed steps rather than
/// in its frames. See [HasFixedStep].
mixin FixedStepUpdate on Component {
  /// Moves this component on by one step of [step] seconds.
  void fixedUpdate(double step);
}

/// A Flame game whose logic runs in fixed steps: the same second of play
/// comes out the same at any frame rate.
///
/// **Flame's `update` is a frame, and a frame is whatever it took.** A jet
/// flown by `speed * dt` travels the same distance at any frame rate only
/// until something is decided along the way: a turn read from input, a
/// fuel tank emptied, a collision caught one frame and missed the next. A
/// replay recorded at 60 frames a second and played at 144 came out
/// differently, and so did a run on a machine that stalled. The physics and
/// the actors already step in fixed steps; this is the same for the game's
/// own logic.
///
/// Each frame, the time is spent in whole steps of [fixedStep]'s size, at
/// most its `maxStepsPerFrame` after a stall. Each step calls
/// [fixedUpdate] on the game and then on every [FixedStepUpdate] component
/// in it, in tree order. Flame's own `update` still runs once a frame after
/// them, for what should follow the screen rather than the simulation: a
/// camera, an animation, a sound. [alpha] is how far the frame is past the
/// last step.
///
/// **Input keeps a press until a step has read it.** A frame with no step
/// in it would otherwise close the input step with a press nobody saw;
/// `FlameInputBridge.stepEnd` closes it only after a frame with a step.
///
/// Flame's collision detection still runs once a frame.
mixin HasFixedStep on FlameGame {
  /// How the frame's time is cut: a sixtieth of a second unless replaced.
  FixedStep fixedStep = FixedStep();

  int _steps = 0;

  /// How many steps this frame ran.
  int get stepsThisFrame => _steps;

  /// How far this frame is past the last step, from 0 up to 1.
  double get alpha => fixedStep.alpha;

  /// The game's own logic for one step of [step] seconds.
  void fixedUpdate(double step) {}

  @override
  void update(double dt) {
    _steps = fixedStep.advance(dt);
    for (var i = 0; i < _steps; i++) {
      final step = fixedStep.stepSeconds;
      fixedUpdate(step);
      for (final component
          in descendants().whereType<FixedStepUpdate>().toList()) {
        if (component.isMounted && !component.isRemoving) {
          component.fixedUpdate(step);
        }
      }
    }
    super.update(dt);
  }
}
