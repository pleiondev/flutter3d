import 'dart:math' as math;

import 'package:vector_math/vector_math.dart';

/// How much of the grip available a tyre is actually using, given how much it
/// is sliding.
///
/// ## Why a curve and not a number
///
/// The cheap model is "keep the forward speed, throw away some fraction of the
/// sideways speed", and it drives like a slot car: grip is constant, so there
/// is no limit to find, and a corner taken too fast feels exactly like a corner
/// taken properly. Everything interesting about driving lives in the *shape* of
/// this curve — grip rises with slip, peaks, and then falls away. The peak is
/// the limit a driver is looking for, and the fall past it is what makes losing
/// the back end a thing that happens to you rather than a thing you switch on.
///
/// ## Why not the full Pacejka formula
///
/// Because it has thirty-odd coefficients that come from fitting real tyre
/// data, and there is no real tyre here. This keeps the shape and drops the
/// fitting: two numbers per direction, both of which a person can hold an
/// opinion about — where the grip peaks, and how much is left when the car is
/// fully sideways. The curve through them is the magic formula's own
/// `sin(C·atan(B·x))`, so it is smooth everywhere including across the peak,
/// which matters because the peak is exactly where a car spends its
/// interesting moments.
///
/// ## Normalised, so mass never appears
///
/// These return a fraction of the grip available, not a force. The vehicle
/// multiplies by what the surface and the load allow, in metres per second
/// squared. Every force on a car is proportional to its mass and every
/// acceleration divides by it again, so carrying a mass through the model would
/// only be carrying a number that cancels.
final class TireModel {
  TireModel({
    this.peakSlipAngle = 0.16,
    double lateralTail = 0.72,
    this.peakSlipRatio = 0.14,
    double longitudinalTail = 0.82,
  })  : _lateralShape = _shapeFor(lateralTail),
        _longitudinalShape = _shapeFor(longitudinalTail) {
    _lateralStiffness = _stiffnessFor(_lateralShape, peakSlipAngle);
    _longitudinalStiffness = _stiffnessFor(_longitudinalShape, peakSlipRatio);
  }

  /// The slip angle, in radians, at which cornering grip is at its best.
  ///
  /// About nine degrees. Below it the car is gripping and the driver has no
  /// idea how close the limit is; above it the car is sliding.
  final double peakSlipAngle;

  /// The slip ratio at which driving and braking grip is at its best. The
  /// reason threshold braking beats standing on the pedal.
  final double peakSlipRatio;

  final double _lateralShape;
  final double _longitudinalShape;
  late final double _lateralStiffness;
  late final double _longitudinalStiffness;

  /// How much cornering grip is in use at [slipAngle], from `-1` to `1`.
  ///
  /// Signed with the slip: a car sliding one way is pushed back the other. The
  /// caller negates it, because which way "back" is depends on the car and not
  /// on the tyre.
  double lateralAt(double slipAngle) =>
      _curve(slipAngle, _lateralStiffness, _lateralShape);

  /// How much driving or braking grip is in use at [slipRatio].
  double longitudinalAt(double slipRatio) =>
      _curve(slipRatio, _longitudinalStiffness, _longitudinalShape);

  /// Holds the two together to what the tyre can actually do.
  ///
  /// The one line that makes braking cost cornering and cornering cost braking.
  /// Worked out separately, the two are each within their own limit and their
  /// sum is not, which produces a car that can brake at full strength in the
  /// middle of a corner it is already taking at the limit — and a driver who
  /// never has to choose. Choosing is the game.
  ///
  /// [limit] is what the surface and the load allow, in metres per second
  /// squared. Both components are scaled together, so the direction of the
  /// force survives and only its size is cut.
  static void clampToCircle(Vector2 force, double limit) {
    final magnitude = force.length;
    if (magnitude <= limit || magnitude < 1e-9) return;
    force.scale(limit / magnitude);
  }

  /// The magic formula, less the parts that need a laboratory.
  static double _curve(double slip, double stiffness, double shape) =>
      math.sin(shape * math.atan(stiffness * slip));

  /// The shape factor that leaves [tail] of the peak when fully sliding.
  ///
  /// `sin(C·π/2)` is what the curve settles to as slip runs away, so this is
  /// that read backwards. Past the peak the curve is falling, which is the
  /// branch wanted — hence `π − asin`, not `asin`.
  static double _shapeFor(double tail) {
    final clamped = tail.clamp(0.05, 0.999);
    return 2.0 - 2.0 * math.asin(clamped) / math.pi;
  }

  /// The stiffness that puts the peak at [peak].
  ///
  /// The curve peaks where `C·atan(B·x)` reaches a quarter turn, so this is
  /// that solved for `B`.
  static double _stiffnessFor(double shape, double peak) {
    if (peak <= 1e-6) return 1e6;
    return math.tan(math.pi / (2.0 * shape)) / peak;
  }
}

/// What each named surface does to the grip available.
///
/// The sibling of the platformer's `Surfaces`, and the same division of labour:
/// a track file or a brush says a word, and the genre decides what the word is
/// worth. One number rather than a table here, because unlike walking — where
/// ice is low friction *and* low acceleration *and* a different jump — driving
/// on a loose surface is one idea, and it is "there is less grip".
final class GripTable {
  const GripTable(this._byName, {this.fallback = 1.0});

  /// Nothing named, everything the same. What a test fixture gets.
  const GripTable.plain() : this(const <String, double>{});

  /// A reasonable place to start, against a car that pulls about one gravity
  /// on tarmac.
  const GripTable.common()
      : this(const <String, double>{
          'asphalt': 1.0,
          'concrete': 0.95,
          'kerb': 0.85,
          'dirt': 0.65,
          'gravel': 0.55,
          'grass': 0.45,
          'sand': 0.4,
          'wet': 0.7,
          'ice': 0.22,
        });

  final Map<String, double> _byName;

  /// What an unnamed surface, or one this table has never heard of, is worth.
  ///
  /// Full grip on purpose: a track may name a surface for its tyre noise alone,
  /// and that must not quietly turn a straight into an ice rink.
  final double fallback;

  double gripFor(String? surface) =>
      surface == null ? fallback : (_byName[surface] ?? fallback);

  bool knows(String surface) => _byName.containsKey(surface);

  Iterable<String> get names => _byName.keys;
}
