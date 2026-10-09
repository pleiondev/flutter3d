/// What a fire's heat does to a person standing near it: the flux its flame
/// radiates onto them, and the share of their tolerance that flux uses up.
///
/// The one place these two laws are written: the effects layer, the crypt,
/// the strategy map and the platformer all burn by them.
library;

import 'dart:math' as math;

import 'package:flutter3d_foundation/flutter3d_foundation.dart' show Portable;
import 'package:flutter3d_matter/flutter3d_matter.dart';
import 'package:vector_math/vector_math.dart';

import 'native_world.dart';

/// The heat [NativeFire]s throw onto a point, and the harm it does there.
abstract final class FireExposure {
  /// The incident radiant flux at or below which skin takes no harm however
  /// long, in watts per square metre (ISO 13571:2012, §8.4).
  static const double harmlessFlux = 2500.0;

  /// The middle of [fire]'s flame, half its reach along its axis: where
  /// [fluxFrom] measures the distance from.
  static Vector3 middleOf(NativeFire fire) =>
      fire.at + fire.axis * (0.5 * fire.reach);

  /// W/m² a flame radiating [radiant] W, its soot glowing at
  /// [sootTemperature] K, throws onto a point [distanceSquared] m² from the
  /// middle of the flame.
  ///
  /// **Modak's point source** (Combustion and Flame 29, 1977; Beyler, SFPE
  /// Handbook, "Fire hazard calculations for large, open hydrocarbon
  /// fires"): the radiant share of the power the fire gives off, χ_r·Q,
  /// spread over a sphere about the middle of its flame, χ_r·Q / (4πR²).
  /// Close in the point source overstates without bound, and nothing is
  /// heated past what the flame's own soot radiates, σT⁴: in the flame, that
  /// is the flux. A flame radiating nothing heats nothing.
  static double flux({
    required double radiant,
    required double sootTemperature,
    required double distanceSquared,
  }) {
    if (radiant <= 0.0) return 0.0;
    final t = sootTemperature;
    final soot = stefanBoltzmann * t * t * t * t;
    // At nought the sphere's flux is infinite, and the soot's is the answer.
    return distanceSquared <= 0.0
        ? soot
        : math.min(radiant / (4.0 * math.pi * distanceSquared), soot);
  }

  /// [flux] for [fire], its radiant share of the power the core gives it, at
  /// [distanceSquared] m² from the [middleOf] its flame.
  static double fluxFrom(NativeFire fire, double distanceSquared) => flux(
    radiant: fire.radiantShare * fire.power,
    sootTemperature: fire.sootTemperature,
    distanceSquared: distanceSquared,
  );

  /// W/m² of radiant heat at [at] from every one of [fires], each [fluxFrom]
  /// the middle of its flame, summed.
  static double fluxAt(Iterable<NativeFire> fires, Vector3 at) => fires.fold(
    0.0,
    (sum, f) => sum + fluxFrom(f, middleOf(f).distanceToSquared(at)),
  );

  /// The share of a person's tolerance [flux] W/m² of radiant heat uses up a
  /// second.
  ///
  /// **ISO 13571:2012**: at or below [harmlessFlux], 2.5 kW/m², skin takes
  /// no harm however long (§8.4); above it the time to a second-degree burn
  /// is t = 6.9·q^−1.56 minutes, q in kW/m² (eq. 7, after Wieczorek and
  /// Dembsey, J. Fire Prot. Eng. 11, 2001). The dose a second is 1/t, and
  /// each second's share is summed, as the standard's fractional effective
  /// dose is: a whole dose is the whole of a character's health.
  ///
  /// Portable, as everything a step reads is: `dart:math`'s pow differs in
  /// its last bits from one platform to the next.
  static double burnDoseRate(double flux) => flux <= harmlessFlux
      ? 0.0
      : Portable.pow(flux / 1000.0, 1.56) / (6.9 * 60.0);
}
