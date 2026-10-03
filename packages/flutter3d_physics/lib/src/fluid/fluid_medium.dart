import 'dart:math' as math;

import 'atmosphere.dart';

/// A liquid, by the properties that decide how it moves: how heavy it is,
/// how thick, how strongly its surface pulls, and how it meets a wall.
///
/// All in SI. The presets are at 20 °C and against clean glass, from the
/// usual handbook values; a liquid on another wall material differs only in
/// [contactAngle], which is a property of the pair, not of the liquid, and
/// so is a field a caller can change with [copyWith].
final class FluidMedium {
  const FluidMedium({
    required this.name,
    required this.density,
    required this.viscosity,
    required this.surfaceTension,
    this.contactAngle = 0.0,
    this.vapour,
  });

  /// Water: 998 kg/m³, 1.0 mPa·s, 72.8 mN/m, wetting glass at about 20°.
  static const FluidMedium water = FluidMedium(
    name: 'water',
    density: 998.2,
    viscosity: 1.002e-3,
    surfaceTension: 0.0728,
    contactAngle: 0.35,
    vapour: VapourCurve.water,
  );

  /// Glycerol: heavy and fourteen hundred times as viscous as water.
  static const FluidMedium glycerol = FluidMedium(
    name: 'glycerol',
    density: 1261.0,
    viscosity: 1.412,
    surfaceTension: 0.0634,
    contactAngle: 0.45,
  );

  /// Olive oil: lighter than water, which it floats on.
  static const FluidMedium oil = FluidMedium(
    name: 'oil',
    density: 911.0,
    viscosity: 0.084,
    surfaceTension: 0.032,
    contactAngle: 0.2,
  );

  /// Ethanol: wets glass completely and pulls weakly.
  static const FluidMedium ethanol = FluidMedium(
    name: 'ethanol',
    density: 789.0,
    viscosity: 1.2e-3,
    surfaceTension: 0.0223,
  );

  /// Mercury: does not wet glass, so its meniscus bulges and it sinks in a
  /// capillary rather than climbing it.
  static const FluidMedium mercury = FluidMedium(
    name: 'mercury',
    density: 13534.0,
    viscosity: 1.526e-3,
    surfaceTension: 0.485,
    contactAngle: 2.44,
  );

  final String name;

  /// Kilograms per cubic metre.
  final double density;

  /// Dynamic viscosity, pascal seconds.
  final double viscosity;

  /// Newtons per metre.
  final double surfaceTension;

  /// The angle the surface meets the wall at, through the liquid, radians:
  /// nought wets completely, past a quarter turn does not wet.
  final double contactAngle;

  /// How much vapour it gives off, for evaporating into an [Atmosphere];
  /// null for a liquid that is taken not to. Only water has one so far: the
  /// others' curves are not here yet, not nought.
  final VapourCurve? vapour;

  /// Kinematic viscosity, square metres per second: what the damping of
  /// waves and the thickness of a boundary layer go by, which
  /// [FreeSurface] reads.
  double get kinematicViscosity => viscosity / density;

  /// The capillary length √(σ / ρg) under gravity [g]: the size below which
  /// surface tension outweighs gravity — about 2.7 mm for water on Earth.
  double capillaryLength(double g) => math.sqrt(surfaceTension / (density * g));

  FluidMedium copyWith({
    String? name,
    double? density,
    double? viscosity,
    double? surfaceTension,
    double? contactAngle,
    VapourCurve? vapour,
  }) => FluidMedium(
    name: name ?? this.name,
    density: density ?? this.density,
    viscosity: viscosity ?? this.viscosity,
    surfaceTension: surfaceTension ?? this.surfaceTension,
    contactAngle: contactAngle ?? this.contactAngle,
    vapour: vapour ?? this.vapour,
  );

  @override
  String toString() => 'FluidMedium($name)';
}
