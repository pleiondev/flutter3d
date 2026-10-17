/// How a component stepped on its own — outside a `HasFixedStep` game — cuts
/// a frame's time into fixed steps.
library;

import 'package:flutter3d_sim/flutter3d_sim.dart' show CatchUp, WorldTiming;

/// A frame's time spent in whole steps of [timing]'s size, at most
/// [catchUp]'s steps a frame, the leftover carried to the next frame.
///
/// **Internal to the bridge.** A game that steps by the engine's rules has
/// an `EngineLoop` (`HasFixedStep.engineLoop`); this is only for the two
/// components that still step themselves when the game does not.
final class StepCut {
  StepCut({
    this.timing = const WorldTiming(),
    this.catchUp = const CatchUp.announce(),
  });

  final WorldTiming timing;
  final CatchUp catchUp;

  double _accumulator = 0.0;
  double _alpha = 0.0;

  /// Seconds one step covers.
  double get stepSeconds => timing.stepSeconds;

  /// How far the frame is past the last step, from 0 up to 1.
  double get alpha => _alpha;

  /// Adds [dt] seconds and returns how many steps to run now.
  int advance(double dt) {
    if (dt.isFinite && dt > 0.0) _accumulator += dt;
    final step = stepSeconds;
    var steps = 0;
    while (_accumulator >= step && steps < catchUp.maxStepsPerFrame) {
      _accumulator -= step;
      steps++;
    }
    if (_accumulator >= step) {
      _accumulator -= (_accumulator ~/ step) * step;
    }
    if (_accumulator < 0.0) _accumulator = 0.0;
    _alpha = _accumulator / step;
    if (_alpha >= 1.0) _alpha = 0.0;
    return steps;
  }
}
