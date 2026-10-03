import 'dart:math' as math;

import 'package:vector_math/vector_math.dart';

import '../portable_math.dart';
import 'fluid_medium.dart';

/// The air round the liquids: how warm, at what pressure, how damp, and how
/// it moves. What drops and streams fall through and what liquid left open
/// evaporates into.
///
/// Every property follows from the four it is made with:
///
/// - **Density**, moist air as an ideal gas: the dry part at 28.96 g/mol,
///   the vapour at 18.02, ρ = (p_d·M_d + p_v·M_v)/RT.
/// - **Viscosity**, Sutherland's law for air: μ = 1.716×10⁻⁵ Pa·s at
///   273.15 K, as (T/T₀)^1.5·(T₀ + 110.4)/(T + 110.4).
/// - **Vapour diffusivity**, water vapour in air, 2.42×10⁻⁵ m²/s at 20 °C
///   and an atmosphere, as T^1.81/p (Marrero and Mason, 1972).
final class Atmosphere {
  Atmosphere({
    this.temperature = 293.15,
    this.pressure = 101325.0,
    this.humidity = 0.5,
    Vector3? wind,
  }) : wind = wind ?? Vector3.zero();

  /// Air at 20 °C and one atmosphere, half saturated, still.
  factory Atmosphere.standard() => Atmosphere();

  /// Kelvin.
  final double temperature;

  /// Pascals.
  final double pressure;

  /// Relative humidity, nought to one: water vapour against what the air
  /// holds saturated at [temperature].
  final double humidity;

  /// Metres per second, everywhere: the air's velocity.
  final Vector3 wind;

  static const double _gas = 8.314462618;
  static const double _dryMolar = 0.0289644;
  static const double _waterMolar = 0.01801528;

  /// The air's velocity at [point]: a vector of the caller's own.
  Vector3 windAt(Vector3 point) => wind.clone();

  /// Partial pressure of water vapour, pascals.
  double get vapourPressure =>
      humidity * VapourCurve.water.saturationPressure(temperature);

  /// Kilograms per cubic metre.
  double get density {
    final vapour = math.min(vapourPressure, pressure);
    return ((pressure - vapour) * _dryMolar + vapour * _waterMolar) /
        (_gas * temperature);
  }

  /// Dynamic viscosity, pascal seconds.
  double get viscosity {
    const t0 = 273.15;
    const s = 110.4;
    return 1.716e-5 *
        Portable.pow(temperature / t0, 1.5) *
        (t0 + s) /
        (temperature + s);
  }

  /// How fast vapour spreads through the air, square metres per second.
  double get vapourDiffusivity =>
      2.42e-5 *
      Portable.pow(temperature / 293.15, 1.81) *
      (101325.0 / pressure);

  /// The vapour of [medium] the air would take up, kilograms per cubic
  /// metre: saturated at the surface less what the air already holds far
  /// off. Nought for a liquid that does not evaporate.
  double vapourDeficit(FluidMedium medium) {
    final curve = medium.vapour;
    if (curve == null) return 0.0;
    final saturated = curve.saturationDensity(temperature);
    // The air's own damp is water's; another vapour is not in it.
    final held = curve.isWater ? humidity * saturated : 0.0;
    return math.max(saturated - held, 0.0);
  }

  /// The drag coefficient of a sphere at Reynolds number [re]: Stokes's
  /// 24/Re with Schiller and Naumann's correction (1933), and Newton's
  /// 0.44 past a thousand.
  static double sphereDrag(double re) {
    if (re <= 0.0) return 0.0;
    if (re >= 1000.0) return 0.44;
    return 24.0 / re * (1.0 + 0.15 * Portable.pow(re, 0.687));
  }

  /// The drag coefficient of a long cylinder crossways to the flow at
  /// Reynolds number [re]: White's fit, 1 + 10/Re^(2/3), for 1 to 2×10⁵.
  static double cylinderDrag(double re) {
    if (re <= 0.0) return 0.0;
    return 1.0 + 10.0 / Portable.pow(math.max(re, 1.0), 2.0 / 3.0);
  }

  /// The acceleration the air gives a sphere [diameter] across of density
  /// [density] moving at [velocity] at [point]: −¾·C_d·ρ_a·|u|·u/(ρ·d), u
  /// its velocity through the air.
  Vector3 dragOnSphere(
    Vector3 velocity,
    Vector3 point,
    double diameter,
    double density,
  ) {
    final u = velocity - windAt(point);
    final speed = u.length;
    if (speed <= 0.0 || diameter <= 0.0) return Vector3.zero();
    final re = this.density * speed * diameter / viscosity;
    final k =
        -0.75 * sphereDrag(re) * this.density * speed / (density * diameter);
    return u..scale(k);
  }
}

/// How much vapour a liquid gives off at a temperature: its saturation
/// pressure as the Magnus form p = a·exp(b·t/(c + t)), t in °C, and its
/// molar mass.
final class VapourCurve {
  const VapourCurve({
    required this.a,
    required this.b,
    required this.c,
    required this.molarMass,
    this.isWater = false,
  });

  /// Water over a flat surface, Alduchov and Eskridge (1996): within a
  /// tenth of a percent from −40 to 50 °C.
  static const VapourCurve water = VapourCurve(
    a: 610.94,
    b: 17.625,
    c: 243.04,
    molarMass: 0.01801528,
    isWater: true,
  );

  final double a;
  final double b;
  final double c;

  /// Kilograms per mole.
  final double molarMass;

  /// Whether this is water's vapour, which the air's humidity is.
  final bool isWater;

  /// Pascals at [temperature] kelvin.
  double saturationPressure(double temperature) {
    final t = temperature - 273.15;
    return a * Portable.exp(b * t / (c + t));
  }

  /// Kilograms per cubic metre of saturated vapour at [temperature].
  double saturationDensity(double temperature) =>
      saturationPressure(temperature) * molarMass / (8.314462618 * temperature);
}
