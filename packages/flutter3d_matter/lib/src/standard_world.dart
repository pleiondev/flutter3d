/// What a world is when nobody says otherwise: the values a
/// `WorldProperties` starts with, and the one place each of those defaults is
/// written as a number.
///
/// **Defaults, not the world.** A game sets its own world — the platformer's
/// falls at 24 m/s², the racing game's at 20 — and a level may set its own
/// on top (`Level.world`); what a body, a runner, a cloth or a spark falls by
/// is read from that world (`WorldProperties`, `CollisionWorld.properties`,
/// the core's `NativeWorld`), never from here. These constants are only what
/// a world nobody configured starts with, so a level set on the Moon is one
/// number changed in the level, not twenty-five in the code.
///
/// The C core's `f3d_world_create` starts with the same values, from the
/// header `tool/gen_materials.dart` writes from these. They are what every
/// recorded run, tape and golden was made under, so they are kept to the
/// bit — 9.81 and not 9.80665, because 9.81 is what the core has always had.
///
/// What belongs to a substance — water's density, viscosity, heat — is not
/// here: it is the substance's entry in the material catalogue (`Materials`,
/// `MaterialCatalog`), which every preset (`FluidMedium.water`,
/// `NativeLiquidProperties.water`, the core's heat presets) is a view of.
/// What belongs to nature — the Stefan–Boltzmann constant, the gas
/// constant — is in `physical_constants.dart`.
library;

import 'dart:math' as math;

import 'package:vector_math/vector_math.dart';

/// The acceleration a body falls with at the Earth's surface, m/s²: standard
/// gravity, 9.806 65 m/s² by definition (3rd CGPM, 1901), to the three
/// figures the core has always used.
const double standardGravity = 9.81;

/// [standardGravity] as a vector, down the y axis. A fresh one each call: a
/// `Vector3` is mutable, and a shared one could be scaled in place.
Vector3 get standardGravityVector => Vector3(0.0, -standardGravity, 0.0);

/// The air's temperature in a world nobody has warmed or cooled, K: 20 °C,
/// the room a laboratory's tables are measured at.
const double standardAirTemperature = 293.15;

/// Dry air's density at [standardAirTemperature] and [standardAtmosphere],
/// kg/m³ (ρ = p M / R T, with M = 0.028 964 7 kg/mol).
const double standardAirDensity = 1.204;

/// How fast sound travels in dry air at [standardAirTemperature], m/s: 343,
/// from c = √(γ R T / M) with γ = 1.4. What a Doppler shift is reckoned
/// against when the listener's world says nothing else; [speedOfSoundAt]
/// gives it at another temperature.
const double standardSpeedOfSound = 343.0;

/// The air's pressure at sea level, Pa: one standard atmosphere, 101 325 Pa
/// by definition (10th CGPM, 1954).
const double standardAtmosphere = 101325.0;

/// How fast sound travels in dry air at [temperature], K, m/s.
///
/// An ideal gas's c = √(γ R T / M), which goes as √T: [standardSpeedOfSound]
/// scaled by √(T / [standardAirTemperature]), so the standard air gives the
/// standard speed to the bit, and air at 0 °C gives 331.09 (the textbook
/// 331.3 is for air that is 343.2 at 20 °C, not the rounded 343). Throws an
/// [ArgumentError] for a temperature that is not finite and positive.
double speedOfSoundAt(double temperature) {
  if (!(temperature.isFinite && temperature > 0.0)) {
    throw ArgumentError.value(temperature, 'temperature', 'not a temperature');
  }
  if (temperature == standardAirTemperature) return standardSpeedOfSound;
  return standardSpeedOfSound * math.sqrt(temperature / standardAirTemperature);
}

/// Dry air's density at [temperature], K, and [pressure], Pa, kg/m³.
///
/// The ideal gas's ρ = p M / R T, which goes as p / T: [standardAirDensity]
/// scaled by (p / [standardAtmosphere]) · ([standardAirTemperature] / T), so
/// the standard air gives the standard density to the bit. Throws an
/// [ArgumentError] for a value that is not finite and positive.
double airDensityAt(double temperature, double pressure) {
  if (!(temperature.isFinite && temperature > 0.0)) {
    throw ArgumentError.value(temperature, 'temperature', 'not a temperature');
  }
  if (!(pressure.isFinite && pressure > 0.0)) {
    throw ArgumentError.value(pressure, 'pressure', 'not a pressure');
  }
  if (temperature == standardAirTemperature && pressure == standardAtmosphere) {
    return standardAirDensity;
  }
  return standardAirDensity *
      (pressure / standardAtmosphere) *
      (standardAirTemperature / temperature);
}
