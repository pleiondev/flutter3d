import 'dart:math' as math;

/// How a sound gets quieter with distance.
///
/// A hierarchy rather than an enum and a switch, and the three subclasses are
/// the three OpenAL defines because they are what sound designers already
/// think in. A game wanting a fourth writes a class instead of editing this
/// file — which is the whole reason a footstep and a siren can obey different
/// curves without either of them being a special case.
///
/// **Units.** Distances in metres; the curve's answer is a linear gain in
/// `[0, 1]`, which `gainToDecibels` turns into the level a desk would show.
/// With the default [reference] of one metre, [InverseRolloff] is the
/// inverse-distance law: −6 dB for each doubling of distance.
abstract base class Attenuation {
  const Attenuation({this.reference = 1.0, this.maximum = 40.0})
    : assert(reference > 0.0),
      assert(maximum > 0.0);

  /// Inside this radius, in metres, the sound is at full volume.
  ///
  /// Without it every model divides by a distance approaching zero, and a
  /// player standing on a torch gets an unbounded gain.
  final double reference;

  /// Beyond this distance, in metres, the sound is silent, and the voice can
  /// be dropped entirely.
  final double maximum;

  /// Linear gain in `[0, 1]` at [distance] metres.
  double gainAt(double distance);

  /// Whether a source this far away is worth a voice at all.
  bool carriesTo(double distance) => distance < maximum;

  double _clampedDistance(double distance) =>
      distance.clamp(reference, maximum);
}

/// Falls off as `1 / distance`, which is what sound actually does.
///
/// The default, because it is the only one of the three that sounds right when
/// the player walks past something rather than towards it.
///
/// **It does not reach nought at [maximum]; it stops there.** At the defaults
/// the gain at forty metres is still a fortieth, −32 dB, and one step further
/// [carriesTo] drops the voice: a quiet step, under most mixes, but a step.
/// A sound that must fade out exactly by a distance wants [LinearRolloff],
/// and a loud one heard across a valley a larger [maximum].
final class InverseRolloff extends Attenuation {
  const InverseRolloff({super.reference, super.maximum, this.factor = 1.0});

  /// Scales the whole curve. Above one, sounds die faster than physics says —
  /// which small rooms usually want. A unitless multiplier on the distance
  /// beyond [reference].
  final double factor;

  @override
  double gainAt(double distance) {
    final d = _clampedDistance(distance);
    return reference / (reference + factor * (d - reference));
  }
}

/// Straight line from full to silent. Predictable, and wrong.
///
/// Kept because it is what a designer means by "audible within ten metres",
/// and being able to say exactly where a sound stops is sometimes worth more
/// than being right.
final class LinearRolloff extends Attenuation {
  const LinearRolloff({super.reference, super.maximum});

  @override
  double gainAt(double distance) {
    final d = _clampedDistance(distance);
    if (maximum <= reference) return 1.0;
    return 1.0 - (d - reference) / (maximum - reference);
  }
}

/// `(d / reference) ^ -factor`. Steep near the source, long tail after.
final class ExponentialRolloff extends Attenuation {
  const ExponentialRolloff({super.reference, super.maximum, this.factor = 1.0});

  /// The curve's unitless exponent: one falls as `1 / distance`.
  final double factor;

  @override
  double gainAt(double distance) {
    final d = _clampedDistance(distance);
    return math.pow(d / reference, -factor).toDouble();
  }
}

/// Never gets quieter and never pans. Music, narration, the wind.
final class NoAttenuation extends Attenuation {
  const NoAttenuation() : super(maximum: double.infinity);

  @override
  double gainAt(double distance) => 1.0;

  @override
  bool carriesTo(double distance) => true;
}
