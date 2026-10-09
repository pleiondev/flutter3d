import 'dart:math' as math;

import 'package:flutter3d_matter/flutter3d_matter.dart';

/// A liquid, by the properties that decide how it moves: how heavy it is,
/// how thick, how strongly its surface pulls, and how it meets a wall.
///
/// All in SI. **A view of a material in the catalogue** ([FluidMedium.of]):
/// the presets are the built-ins' entries ([Materials]) at 20 °C, against
/// clean glass as the catalogue's `MaterialPair`s with `f3d.glass` measure
/// it; a liquid on another wall material differs only in [contactAngle],
/// which is a property of the pair, not of the liquid, and so is a field a
/// caller can change with [copyWith].
final class FluidMedium {
  const FluidMedium({
    required this.name,
    required this.density,
    required this.viscosity,
    required this.surfaceTension,
    this.contactAngle = 0.0,
  });

  /// [material]'s density, viscosity and surface tension, meeting a wall at
  /// [contactAngle], radians — by default the angle the built-in pairs give
  /// it on glass ([Materials.pairs]), or nought. Throws an [ArgumentError]
  /// for a material that does not say all three.
  factory FluidMedium.of(PhysicalMaterial material, {double? contactAngle}) {
    final density = material.density;
    final viscosity = material.fluid?.viscosity;
    final tension = material.fluid?.surfaceTension;
    if (density == null || viscosity == null || tension == null) {
      throw ArgumentError.value(
        material.id,
        'material',
        'says no density, viscosity or surface tension',
      );
    }
    return FluidMedium(
      name: material.name,
      density: density,
      viscosity: viscosity,
      surfaceTension: tension,
      contactAngle: contactAngle ?? _onGlass(material.id) ?? 0.0,
    );
  }

  /// The angle the built-in pairs give [id] on glass, or null.
  static double? _onGlass(String id) {
    final key = MaterialPair.keyOf(id, Materials.glass.id);
    for (final pair in Materials.pairs) {
      if (pair.key == key) return pair.contactAngle;
    }
    return null;
  }

  /// Water ([Materials.water]): 998.2 kg/m³, 1.002 mPa·s, 72.8 mN/m, wetting
  /// glass at about 20°.
  static final FluidMedium water = FluidMedium.of(Materials.water);

  /// Glycerol ([Materials.glycerol]): heavy and fourteen hundred times as
  /// viscous as water.
  static final FluidMedium glycerol = FluidMedium.of(Materials.glycerol);

  /// Olive oil ([Materials.oliveOil]): lighter than water, which it floats
  /// on.
  static final FluidMedium oliveOil = FluidMedium.of(Materials.oliveOil);

  /// [oliveOil], by the name it had.
  @Deprecated(
    'Use FluidMedium.oliveOil, the catalogue\'s f3d.oliveOil. '
    'Deprecated in 1.0.0, removed in 2.0.0.',
  )
  static FluidMedium get oil => oliveOil;

  /// Ethanol ([Materials.ethanol]): wets glass completely and pulls weakly.
  static final FluidMedium ethanol = FluidMedium.of(Materials.ethanol);

  /// Mercury at 20 °C ([Materials.mercury]): 13 546 kg/m³, 1.55 mPa·s. It
  /// does not wet glass, so its meniscus bulges and it sinks in a capillary
  /// rather than climbing it.
  static final FluidMedium mercury = FluidMedium.of(Materials.mercury);

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
  }) => FluidMedium(
    name: name ?? this.name,
    density: density ?? this.density,
    viscosity: viscosity ?? this.viscosity,
    surfaceTension: surfaceTension ?? this.surfaceTension,
    contactAngle: contactAngle ?? this.contactAngle,
  );

  @override
  String toString() => 'FluidMedium($name)';
}
