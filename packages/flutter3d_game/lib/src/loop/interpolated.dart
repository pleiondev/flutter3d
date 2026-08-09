import 'dart:math' as math;

import 'package:vector_math/vector_math.dart';

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
  InterpolatedVector3([Vector3? initial])
      : _previous = initial?.clone() ?? Vector3.zero(),
        _current = initial?.clone() ?? Vector3.zero();

  final Vector3 _previous;
  final Vector3 _current;

  /// The value the last completed step produced, without interpolation.
  ///
  /// This is what the simulation itself must read — collision, AI and damage all
  /// have to agree on one authoritative position, and the interpolated one is a
  /// display artefact that exists between two of them.
  Vector3 get current => _current;

  /// Records a new simulated value, keeping the one before it to blend from.
  void push(Vector3 value) {
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
    return _previous + _shortestDelta(_previous, _current) * t;
  }

  /// The signed distance from [from] to [to], never longer than half a turn.
  static double _shortestDelta(double from, double to) {
    const twoPi = 2.0 * math.pi;
    var delta = (to - from) % twoPi;
    if (delta > math.pi) {
      delta -= twoPi;
    } else if (delta < -math.pi) {
      delta += twoPi;
    }
    return delta;
  }
}
