import 'dart:math' as math;

import 'package:vector_math/vector_math.dart';

import 'particle.dart';

/// Something whose particles are a light source.
///
/// Opt-in, and that is the point: a fire lights a room, and smoke, blood and
/// bullet casings do not. Measuring every particle that happens to carry a
/// source key would make "emits light" an accident of the plumbing rather than
/// something an effect declares.
///
/// Mix it into whatever is passed to [ParticleSystem.emitFor] as the source.
/// The system fills [glow] in every step; the owner reads it and does whatever
/// a light means to it.
mixin class LightEmitter {
  /// What this emitter's particles currently amount to. Owned here, written by
  /// the particle system, read by anything that wants to be lit by fire.
  final ParticleGlow glow = ParticleGlow();
}

/// What a source's particles add up to: how much light they are, and where.
///
/// The reason this exists at all: a fire *is* its particles, so the light it
/// casts should be measured from them rather than produced by a second,
/// invented wobble running alongside. Two generators of the same quantity
/// disagree eventually, and the disagreement looks like a flame burning
/// brightly while the light it casts has gone out.
///
/// Smoothed, because a raw sum over forty particles jumps by tens of percent
/// between frames — a strobe rather than a flicker. A tenth of a second of lag
/// is invisible and turns the same numbers into fire.
final class ParticleGlow {
  /// Live particles from this source.
  int get count => _count;
  int _count = 0;

  /// Luminance times alpha times area, summed and smoothed.
  ///
  /// In no unit: a number that goes up when there is more fire. A caller
  /// divides by whatever a healthy flame settles at.
  double get power => _power;
  double _power = 0.0;

  /// Where the fire is, smoothed. A light placed here drifts with the flame
  /// instead of being nailed to the emitter.
  Vector3 get centre => _centre;
  final Vector3 _centre = Vector3.zero();

  /// Seconds for the smoothing to catch up most of the way.
  static const double smoothing = 0.09;

  double _rawPower = 0.0;
  final Vector3 _rawCentre = Vector3.zero();

  void beginStep() {
    _count = 0;
    _rawPower = 0.0;
    _rawCentre.setZero();
  }

  void accumulate(Particle particle) {
    _count++;
    final luminance = particle.color.x * 0.30 +
        particle.color.y * 0.59 +
        particle.color.z * 0.11;
    _rawPower += luminance * particle.color.w * particle.size * particle.size;
    _rawCentre.add(particle.position);
  }

  void endStep(double dt) {
    if (_count > 0) _rawCentre.scale(1.0 / _count);
    // Exponential and framerate independent: the same lag at sixty frames a
    // second and at a hundred and twenty.
    final alpha = 1.0 - math.exp(-dt / smoothing);
    _power += (_rawPower - _power) * alpha;
    if (_count > 0) {
      _centre.x += (_rawCentre.x - _centre.x) * alpha;
      _centre.y += (_rawCentre.y - _centre.y) * alpha;
      _centre.z += (_rawCentre.z - _centre.z) * alpha;
    }
  }
}
