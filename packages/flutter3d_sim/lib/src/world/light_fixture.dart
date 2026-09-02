import 'dart:math' as math;

import 'package:vector_math/vector_math.dart';

import 'mechanism.dart';

/// How a light behaves over time.
///
/// A hierarchy because the three differ only in this one function, and because
/// a level pack wanting a failing fluorescent tube should write a class rather
/// than add a flag to a flicker that was only ever meant to be a torch.
abstract base class LightBehaviour {
  const LightBehaviour();

  /// Brightness multiplier at [time] seconds, for the fixture identified by
  /// [seed].
  ///
  /// The seed is what stops a row of torches from pulsing in unison, which is
  /// the single thing that makes flickering light read as machinery instead of
  /// as fire.
  double at(double time, double seed);
}

/// Steady. A lamp, a stained window with daylight behind it.
final class SteadyLight extends LightBehaviour {
  const SteadyLight();

  @override
  double at(double time, double seed) => 1.0;
}

/// Fire.
///
/// Two sine waves at unrelated frequencies plus a slow one, which is the
/// cheapest thing that does not read as a repeating loop. Deliberately not
/// random: a value computed from the time is the same on every machine and
/// after every reload, which is what lets a golden hold still.
final class FlameFlicker extends LightBehaviour {
  const FlameFlicker({this.depth = 0.22, this.rate = 7.0});

  /// How far it dips below full, from 0 to 1.
  final double depth;

  /// Roughly, flickers per second.
  final double rate;

  @override
  double at(double time, double seed) {
    final t = time * rate + seed * 10.0;
    final wobble =
        math.sin(t) * 0.6 +
        math.sin(t * 1.7 + 1.3) * 0.3 +
        math.sin(t * 0.31 + 2.1) * 0.1;
    return 1.0 - depth * (0.5 - 0.5 * wobble);
  }
}

/// A slow swell, for something magical rather than burning.
final class PulseLight extends LightBehaviour {
  const PulseLight({this.depth = 0.35, this.period = 3.5});

  final double depth;
  final double period;

  @override
  double at(double time, double seed) {
    final phase = 2.0 * math.pi * (time / period + seed);
    return 1.0 - depth * (0.5 - 0.5 * math.sin(phase));
  }
}

/// Something in the level that gives off light and can be seen doing it.
///
/// The light itself is already in the level's light list; this is the object
/// that owns it, so the brightness and whatever is drawn glowing use one
/// number rather than two that drift apart. A torch whose flame stays bright
/// while its light dims is a torch nobody believes.
final class LightFixture extends Mechanism {
  LightFixture({
    super.name,
    required this.light,
    this.behaviour = const SteadyLight(),
    this.seed = 0.0,
    this.enabled = true,
  });

  /// The name of the level light this drives, when it drives one. A purely
  /// decorative fixture — an unlit sconce — names none.
  final String? light;

  final LightBehaviour behaviour;

  /// Offsets this fixture's phase. See [LightBehaviour.at].
  final double seed;

  /// Switched off by a button, or by the level starting dark.
  bool enabled;

  /// Brightness multiplier for this frame, in `[0, 1]`.
  double get brightness => _brightness;
  double _brightness = 1.0;

  /// True once something has measured this fixture's fire.
  ///
  /// A fixture whose light comes from particles must not also run a
  /// [LightBehaviour]: two generators of the same number disagree eventually,
  /// and the disagreement looks like a flame burning while its light is out.
  /// So [measure] takes over, and [behaviour] is left for the fixtures that
  /// have nothing to measure — a lamp, a pulsing crystal.
  bool get isMeasured => _measured;
  bool _measured = false;

  /// Whether it is lit, and nothing else.
  ///
  /// The brightness is not saved and that is deliberate: it is a function of
  /// the clock and the seed, so it comes back on its own at the first step and
  /// storing it would be storing a number that is about to be overwritten.
  /// Whether somebody switched the lamp off is the only thing here that a
  /// player did.
  @override
  Map<String, Object?> save() => <String, Object?>{'enabled': enabled};

  @override
  void restore(Map<String, Object?> from) {
    final on = from['enabled'];
    if (on is bool) enabled = on;
  }

  /// Where the fire actually is, or null if nothing has said.
  ///
  /// A flame is not a point and it does not sit still, so the light it casts
  /// belongs where the particles currently are rather than at the bracket
  /// holding them. The drift is small — a few centimetres — and it is the
  /// difference between a light that flickers and one that lives.
  Vector3? get measuredAt => _measuredAt;
  Vector3? _measuredAt;

  /// Reports what this fixture's fire actually amounts to, from 0 to 1, and
  /// optionally where it is.
  ///
  /// Called every step by whatever owns the particles. The flicker of a real
  /// flame is the randomness of its own burning, so a light driven from here
  /// needs no wobble added to it.
  ///
  /// [at] is copied rather than kept: the caller's vector is a live buffer the
  /// particle system rewrites every step, and holding it would make this
  /// fixture's idea of where its fire is change underneath whoever is reading.
  void measure(double fraction, {Vector3? at}) {
    _measured = true;
    _brightness = enabled ? fraction.clamp(0.0, 1.0) : 0.0;
    if (at != null) (_measuredAt ??= Vector3.zero()).setFrom(at);
  }

  double _time = 0.0;

  @override
  void step(double dt) {
    _time += dt;
    if (_measured) return;
    _brightness = enabled ? behaviour.at(_time, seed).clamp(0.0, 1.0) : 0.0;
  }

  /// Toggling is the only thing that can be done to it, and a level that
  /// wires a button to a lamp gets that for free.
  @override
  ActivationOutcome activate(Activation by) {
    enabled = !enabled;
    return const Activated();
  }
}
