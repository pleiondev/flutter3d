import 'dart:math' as math;

import 'package:flutter3d_foundation/flutter3d_foundation.dart';
import 'package:flutter3d_matter/flutter3d_matter.dart';
import 'package:vector_math/vector_math.dart';

import 'buoyancy.dart' show sphereDrag;
import 'fluid_medium.dart';

/// The air round a world's liquids: how warm, at what pressure, how damp
/// and how it moves. What drops and streams fall through, and what liquid
/// left open evaporates into.
///
/// **Read from the world** ([FluidAir.of]): its temperature, pressure,
/// relative humidity and wind are the `WorldProperties`' own, so a bench on
/// a mountain or in a draught is that world's, said once. Every property
/// follows from those four:
///
/// - **Density**, moist air as an ideal gas mixture: the dry part at dry
///   air's molar mass, the vapour at water's, ρ = (p_d·M_d + p_v·M_v)/RT —
///   unless the world says its air's density outright, which is then what
///   it is.
/// - **Viscosity**, Sutherland's law for air: μ = 1.716×10⁻⁵ Pa·s at
///   0 °C, as (T/T₀)^1.5·(T₀ + 110.4)/(T + 110.4) (White, Viscous Fluid
///   Flow, 3rd ed., 2006, table 1-2).
/// - **Vapour diffusivity**, water vapour in air, 2.42×10⁻⁵ m²/s at 20 °C
///   and one atmosphere, as T^1.81/p (Marrero and Mason, J. Phys. Chem.
///   Ref. Data 1, 1972).
final class FluidAir {
  /// Air at [temperature] K and [pressure] Pa, [humidity] saturated (nought
  /// to one), moving at [wind] m/s; its density, kg/m³, said outright
  /// ([densityOverride]) or worked out from the rest. Throws an [ArgumentError] for a temperature
  /// or pressure that is not positive, or a humidity outside nought to one.
  FluidAir({
    required this.temperature,
    required this.pressure,
    required this.humidity,
    Vector3? wind,
    this.densityOverride,
  }) : _wind = wind?.clone() ?? Vector3.zero() {
    if (!(temperature > 0.0) || !(pressure > 0.0)) {
      throw ArgumentError('air at $temperature K and $pressure Pa');
    }
    if (!(humidity >= 0.0 && humidity <= 1.0)) {
      throw ArgumentError.value(humidity, 'humidity', 'not 0 to 1');
    }
  }

  /// The air of [world]: its temperature, pressure, humidity and wind, and
  /// its density where it says one.
  factory FluidAir.of(WorldProperties world) => FluidAir(
    temperature: world.airTemperature,
    pressure: world.airPressure,
    humidity: world.airHumidity,
    wind: world.wind,
    densityOverride: world.airDensityOverride,
  );

  /// The standard world's air: 20 °C, one atmosphere, half saturated,
  /// still.
  static final FluidAir standard = FluidAir.of(WorldProperties.standard);

  /// Kelvin.
  final double temperature;

  /// Pascals.
  final double pressure;

  /// Relative humidity, nought to one: water vapour against what the air
  /// holds saturated at [temperature].
  final double humidity;

  final Vector3 _wind;

  /// The air's density said outright, kg/m³, or null to work it out
  /// ([density]).
  final double? densityOverride;

  /// Water's molar mass, kg/mol, for the vapour's share of the air's
  /// density.
  static const double _waterMolar = 0.01801528;

  /// Sutherland's constants for air: its viscosity at 0 °C, Pa·s, and its
  /// temperature, K.
  static const double _sutherlandViscosity = 1.716e-5;
  static const double _sutherlandTemperature = 110.4;

  /// Marrero and Mason's diffusivity of water vapour in air at 20 °C and
  /// one atmosphere, m²/s: the state the standard air is in, which is what
  /// [vapourDiffusivity] scales from.
  static const double _diffusivity = 2.42e-5;

  /// The air's velocity at [point], m/s: the world's wind, the same
  /// everywhere. A fresh vector each call.
  Vector3 windAt(Vector3 point) => _wind.clone();

  /// The wind, m/s. A fresh vector each call.
  Vector3 get wind => _wind.clone();

  /// Partial pressure of water vapour, pascals.
  double get vapourPressure =>
      humidity * VapourCurve.water.saturationPressure(temperature);

  /// Kilograms per cubic metre: the world's own when it says one, moist air
  /// as an ideal gas otherwise.
  double get density {
    final said = densityOverride;
    if (said != null) return said;
    final vapour = math.min(vapourPressure, pressure);
    return ((pressure - vapour) * molarMassOfDryAir + vapour * _waterMolar) /
        (molarGasConstant * temperature);
  }

  /// Dynamic viscosity, pascal seconds.
  double get viscosity =>
      _sutherlandViscosity *
      Portable.pow(temperature / zeroCelsius, 1.5) *
      (zeroCelsius + _sutherlandTemperature) /
      (temperature + _sutherlandTemperature);

  /// How fast water vapour spreads through the air, square metres a second.
  double get vapourDiffusivity =>
      _diffusivity *
      Portable.pow(temperature / standardAirTemperature, 1.81) *
      (standardAtmosphere / pressure);

  /// The vapour of [medium] the air would take up, kilograms per cubic
  /// metre: saturated at the surface less what the air already holds far
  /// off. Nought for a liquid with no vapour curve ([VapourCurve.of]).
  double vapourDeficit(FluidMedium medium) {
    final curve = VapourCurve.of(medium);
    if (curve == null) return 0.0;
    final saturated = curve.saturationDensity(temperature);
    // The air's own damp is water's; another vapour is not in it.
    final held = curve.isWater ? humidity * saturated : 0.0;
    return math.max(saturated - held, 0.0);
  }

  /// The drag coefficient of a long cylinder crossways to the flow at
  /// Reynolds number [re]: White's fit, 1 + 10/Re^⅔, for Re from 1 to
  /// 2×10⁵ (White, Viscous Fluid Flow, 3rd ed., 2006, eq. 3-225).
  static double cylinderDrag(double re) {
    if (re <= 0.0) return 0.0;
    return 1.0 + 10.0 / Portable.pow(math.max(re, 1.0), 2.0 / 3.0);
  }

  /// The acceleration the air gives a sphere [diameter] across, of
  /// [density], moving at [velocity] at [point]: −¾·C_d·ρ_a·|u|·u/(ρ·d), u
  /// its velocity through the air and C_d the engine's sphere drag
  /// ([sphereDrag]). A fresh vector.
  Vector3 dragOnSphere(
    Vector3 velocity,
    Vector3 point,
    double diameter,
    double density,
  ) {
    final u = velocity - windAt(point);
    final speed = u.length;
    if (speed <= 0.0 || diameter <= 0.0) return Vector3.zero();
    final air = this.density;
    final re = air * speed * diameter / viscosity;
    final k = -0.75 * sphereDrag(re) * air * speed / (density * diameter);
    return u..scale(k);
  }

  /// The mass a sphere [diameter] across of [medium], moving at [speed]
  /// through the air, gives off a second, kg/s: π·d·D·Δc·Sh, with Ranz and
  /// Marshall's Sherwood number 2 + 0.6·Re^½·Sc^⅓ (Chem. Eng. Prog. 48,
  /// 1952). Nought for a liquid that does not evaporate.
  double sphereEvaporation(FluidMedium medium, double diameter, double speed) {
    final deficit = vapourDeficit(medium);
    if (deficit <= 0.0 || diameter <= 0.0) return 0.0;
    final d = vapourDiffusivity;
    final air = density;
    final re = air * speed * diameter / viscosity;
    final sc = viscosity / (air * d);
    final sherwood = 2.0 + 0.6 * math.sqrt(re) * Portable.pow(sc, 1.0 / 3.0);
    return math.pi * diameter * d * deficit * sherwood;
  }

  @override
  String toString() =>
      'FluidAir($temperature K, $pressure Pa, ${humidity * 100} %, '
      'wind ${_wind.storage.toList()})';
}

/// How much vapour a liquid gives off at a temperature: its saturation
/// pressure as the Magnus form p = a·exp(b·t/(c + t)), t in °C, and its
/// molar mass.
final class VapourCurve {
  /// A curve of Magnus constants [a] (Pa), [b] and [c] (°C) for a vapour of
  /// [molarMass] kg/mol; [isWater] for water's, which the air's humidity
  /// is.
  const VapourCurve({
    required this.a,
    required this.b,
    required this.c,
    required this.molarMass,
    this.isWater = false,
  });

  /// Water over a flat surface, Alduchov and Eskridge (J. Appl. Meteor. 35,
  /// 1996): within a tenth of a percent from −40 to 50 °C.
  static const VapourCurve water = VapourCurve(
    a: 610.94,
    b: 17.625,
    c: 243.04,
    molarMass: FluidAir._waterMolar,
    isWater: true,
  );

  /// The curve of [medium]: water's for water, null for a liquid whose
  /// curve is not here yet — taken not to evaporate, which is not the same
  /// as known not to.
  static VapourCurve? of(FluidMedium medium) =>
      medium.material?.id == Materials.water.id ? water : null;

  /// The saturation pressure at 0 °C, Pa.
  final double a;

  /// The curve's slope, no unit.
  final double b;

  /// The curve's offset, in degrees Celsius.
  final double c;

  /// Kilograms per mole.
  final double molarMass;

  /// Whether this is water's vapour, which the air's humidity is.
  final bool isWater;

  /// Pascals at [temperature] kelvin.
  double saturationPressure(double temperature) {
    final t = temperature - zeroCelsius;
    return a * Portable.exp(b * t / (c + t));
  }

  /// Kilograms per cubic metre of saturated vapour at [temperature].
  double saturationDensity(double temperature) =>
      saturationPressure(temperature) *
      molarMass /
      (molarGasConstant * temperature);
}
