import 'dart:math' as math;

import 'package:vector_math/vector_math.dart';

import '../math/motion.dart';

/// A position the simulation writes at a fixed rate and the renderer reads at
/// the display's rate.
///
/// Holds the previous and the current simulated value and blends between them by
/// [FixedStep.alpha]. Without this the renderer shows the newest state on every
/// frame, which on a display faster than the simulation means several frames in
/// a row show the same position and then one jumps — the classic 60-on-120
/// stutter.
///
/// Reading takes an output parameter, like the rest of the maths in this
/// project: it is called once per drawn object per frame, and returning a fresh
/// [Vector3] there is a guaranteed allocation on the hottest path there is.
final class InterpolatedVector3 {
  InterpolatedVector3({
    Vector3? initial,
    this.stepLimit = 0.0,
    this.stepRecovery = 0.1,
  }) : assert(stepLimit >= 0.0),
       assert(stepRecovery > 0.0),
       _previous = initial?.clone() ?? Vector3.zero(),
       _current = initial?.clone() ?? Vector3.zero();

  /// The most of a climbed ledge the picture may hold back at once, in metres.
  ///
  /// Zero — the default — turns step smoothing off entirely, which is what
  /// anything that is not a walking body wants.
  ///
  /// A character controller climbs a low ledge by *teleporting*: it lifts the
  /// body, moves it across and sets it down, all inside one simulated step. The
  /// simulation is right to do that, and the renderer showing it means a riser
  /// of fifteen centimetres arrives at nine metres a second, which pitches the
  /// horizon on every stair. So the rise is taken out of the drawn position and
  /// let back in over [stepRecovery].
  ///
  /// The cap is what keeps the body from sinking into a staircase it is
  /// climbing quickly: whatever is still held back, the drawn feet are never
  /// more than one riser below the real ones.
  final double stepLimit;

  /// How long a held-back rise takes to be given back, as a time constant.
  ///
  /// The offset falls by `exp(-dt / stepRecovery)` each step, so at the default
  /// a tenth of a second gives back about two thirds of it and three tenths
  /// gives back all but a twentieth.
  final double stepRecovery;

  final Vector3 _previous;
  final Vector3 _current;

  /// How much of a climbed ledge each endpoint is still holding back.
  ///
  /// Two values rather than one, and that is the whole of why this is
  /// continuous: the blend has to interpolate the offset alongside the position
  /// it belongs to. A single offset subtracted from the blended result drops
  /// the drawn body by the height of the ledge the instant the ledge is
  /// climbed — the very jump this exists to remove, moved one frame earlier.
  double _previousHidden = 0.0;
  double _currentHidden = 0.0;

  /// The value the last completed step produced, without interpolation.
  ///
  /// This is what the simulation itself must read — collision, AI and damage all
  /// have to agree on one authoritative position, and the interpolated one is a
  /// display artefact that exists between two of them.
  Vector3 get current => _current;

  /// Records a new simulated value, keeping the one before it to blend from.
  ///
  /// [steppedUp] is how far the body was lifted onto a ledge this step, and
  /// [dt] is how long the step covered. Both are ignored unless [stepLimit] is
  /// set.
  ///
  /// **The height has to be reported, not inferred.** Working it out here as
  /// "the body rose while it was on the ground" reads a lift exactly the same
  /// way, because a passenger is carried by having its position moved; a lift
  /// rising at two metres a second would hold back its own travel until the
  /// clamp stopped it and draw the runner a fifth of a metre inside the floor
  /// for the whole ascent.
  void push(Vector3 value, {double dt = 0.0, double steppedUp = 0.0}) {
    if (stepLimit > 0.0) {
      _previousHidden = _currentHidden;
      _currentHidden *= math.exp(-dt / stepRecovery);
      if (steppedUp > 0.0) {
        _currentHidden = math.min(stepLimit, _currentHidden + steppedUp);
      }
    }
    _previous.setFrom(_current);
    _current.setFrom(value);
  }

  /// Moves both endpoints at once, so the next frame shows no motion.
  ///
  /// For teleports — a spawn, a level change, stepping through a portal. Pushing
  /// a distant value instead would draw the object smearing across the level for
  /// one frame.
  void jumpTo(Vector3 value) {
    _previous.setFrom(value);
    _current.setFrom(value);
    _previousHidden = 0.0;
    _currentHidden = 0.0;
  }

  /// Blends into [out] by [alpha], which [FixedStep] supplies.
  void read(double alpha, Vector3 out) {
    final t = alpha.clamp(0.0, 1.0);
    // Written out rather than through a helper: `vector_math` 2.2.0 has no
    // in-place lerp on Vector3, and the alternatives all allocate.
    out.setValues(
      _previous.x + (_current.x - _previous.x) * t,
      _previous.y + (_current.y - _previous.y) * t,
      _previous.z + (_current.z - _previous.z) * t,
    );
    if (stepLimit > 0.0) {
      out.y -= _previousHidden + (_currentHidden - _previousHidden) * t;
    }
  }
}

/// An angle in radians that the simulation writes and the renderer reads.
///
/// Separate from [InterpolatedVector3] because blending angles linearly is
/// wrong at the wrap point: going from `+3.1` to `-3.1` is a hair's movement one
/// way and almost a full turn the other, and a plain lerp always picks the long
/// one. A monster turning to face the player crosses that boundary constantly.
final class InterpolatedAngle {
  InterpolatedAngle([double initial = 0.0])
    : _previous = initial,
      _current = initial;

  double _previous;
  double _current;

  double get current => _current;

  void push(double value) {
    _previous = _current;
    _current = value;
  }

  void jumpTo(double value) {
    _previous = value;
    _current = value;
  }

  double read(double alpha) {
    final t = alpha.clamp(0.0, 1.0);
    return _previous + shortestAngle(_previous, _current) * t;
  }

  /// The signed distance from [from] to [to], never longer than half a turn.
}
