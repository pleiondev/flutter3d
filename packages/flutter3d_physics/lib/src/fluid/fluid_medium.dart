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
    this.material,
  });

  /// [material]'s density, viscosity and surface tension, meeting a wall at
  /// [contactAngle], radians — by default the angle the built-in pairs give
  /// it on glass ([Materials.pairs]), or nought. Throws an [ArgumentError]
  /// for a material that does not say all three.
  factory FluidMedium.of(PhysicalMaterial material, {double? contactAngle}) {
    final density = material.density;
    final viscosity = material.fluid?.viscosity?.value;
    final tension = material.fluid?.surfaceTension?.value;
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
      material: material,
    );
  }

  /// The material this medium is a view of, whose laws [at] reads; null
  /// for a medium given as numbers, or changed from one by [copyWith].
  final PhysicalMaterial? material;

  /// This medium at [state]: its [material]'s density, viscosity and
  /// surface tension as their laws give them there (`PropertyLaw.at`),
  /// the [contactAngle] kept. Water at 60 °C is a little lighter than at
  /// 20 and half as viscous, so a ball settles through it twice as fast.
  ///
  /// **The same numbers at the reference state**: a law at the state its
  /// value was quoted at answers that value, so a medium of the catalogue
  /// at `MatterState.standard` is this one. A medium with no [material]
  /// has no laws, and is itself at every state.
  FluidMedium at(MatterState state) {
    final m = material;
    if (m == null) return this;
    return FluidMedium(
      name: name,
      density: m.mechanical?.density?.at(state) ?? density,
      viscosity: m.fluid?.viscosity?.at(state) ?? viscosity,
      surfaceTension: m.fluid?.surfaceTension?.at(state) ?? surfaceTension,
      contactAngle: contactAngle,
      material: m,
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

  /// A copy with the given fields replaced. One that changes a density, a
  /// viscosity or a surface tension is no longer its [material]'s, and
  /// keeps none.
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
    material: density == null && viscosity == null && surfaceTension == null
        ? material
        : null,
  );

  @override
  String toString() => 'FluidMedium($name)';
}
