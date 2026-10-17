/// The smoke plume over a fire: how wide it is, how fast it rises, and how
/// much light it stops (`doc/smoke_plume.md`).
library;

import 'dart:math' as math;

import 'package:flutter3d_foundation/flutter3d_foundation.dart' show Portable;

/// The plume over a fire of a given heat, kW, on a base so wide, m: what a
/// game's watcher asks of it before seeing through it
/// ([ElementsSimulation.seenThroughSmoke]), and what `FireView` in
/// `flutter3d_effects` draws each puff of its smoke as dark as.
///
/// Heskestad's virtual origin and width and McCaffrey's centreline speed,
/// with the soot's mass extinction; every power through [Portable], so a
/// watcher's step reads the same bits on every platform.
abstract final class SmokePlume {
  /// The height of a plume's virtual origin over its fire's base, m:
  /// Heskestad's z₀ = 0.083 Q^(2/5) − 1.02 D, Q in kW.
  static double virtualOrigin(double kw, double base) =>
      0.083 * Portable.pow(math.max(kw, 0.0), 0.4) - 1.02 * base;

  /// McCaffrey's plume centreline velocity, m/s, [z] m over a fire of
  /// [kw], from no lower than where his plume begins, 0.2·Q^(2/5): below
  /// that, in the flame's intermittent top, the gas rises as fast as it
  /// does there.
  static double centerlineSpeed(double kw, double z) =>
      1.11 *
      Portable.pow(kw, 1 / 3) *
      Portable.pow(
        math.max(z, math.max(0.2 * Portable.pow(kw, 0.4), 0.05)),
        -1 / 3,
      );

  /// The light a kilogram of soot stops, m²: 8.7 m² a gram, 8700 ± 1100
  /// m²/kg at 633 nm over many fuels' flaming soot (Mulholland and
  /// Croarkin, as the FDS User's Guide, NIST SP 1019, gives it). Crude
  /// oil's smoke measured 9.1 (Evans and colleagues, J. Res. NIST 106,
  /// 2001), inside that spread, so one value serves every fuel
  /// (`doc/smoke_plume.md`).
  static const double extinction = 8700.0;

  /// kg of soot per joule a wood fire makes, the core's wood's: 0.015 of
  /// it burnt, at 15 MJ/kg — what [depth] takes when it is not told.
  static const double woodSoot = 0.015 / 1.5e7;

  /// The plume's half-width [z] m over a fire of [kw] on a base [base]
  /// across, m: Heskestad's 0.12 (z − z₀), and no narrower than the base
  /// it rises from.
  static double halfWidth(double kw, double base, double z) =>
      math.max(0.12 * (z - virtualOrigin(kw, base)), 0.5 * base);

  /// The plume's optical depth across its middle [z] m over a fire of [kw]
  /// on a base [base] across, making [sootYield] kg of soot a joule
  /// (`NativeFire.sootYield`), τ = 2 K_m ṁ_s / (π b u)
  /// (`doc/smoke_plume.md`).
  static double depth(
    double kw,
    double base,
    double z, {
    double sootYield = woodSoot,
  }) =>
      2.0 *
      extinction *
      sootYield *
      1000.0 *
      kw /
      (math.pi * halfWidth(kw, base, z) * centerlineSpeed(kw, z));
}
