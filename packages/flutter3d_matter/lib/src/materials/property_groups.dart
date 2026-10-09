/// What a material is, in groups: its mechanics, its flow, its heat, its
/// sound, its light and its current — each a small value of its own.
///
/// **A group per kind of question**, so a material says only what it knows —
/// glass has no viscosity a game asks for, water no yield strength — and a
/// group a later minor adds (magnetic, say) arrives as one more optional
/// field of `PhysicalMaterial` and one more key in its file, breaking
/// nobody. Every number is in SI, the unit in its doc; every group names
/// the [PropertyGroup.source] its numbers were read from, which a plugin's
/// material must give too.
library;

import 'material_json.dart';

/// What every group of a material's properties has: the source its numbers
/// were read from, and the keys of its file a later version wrote that this
/// one does not know, kept so they are written back.
///
/// **Not sealed**, so a group added in a minor breaks no switch over them.
abstract base class PropertyGroup {
  const PropertyGroup({
    required this.source,
    this.unknown = const <String, Object?>{},
  });

  /// Where the numbers come from: a handbook and its table, a paper, a
  /// datasheet — whatever a reader needs to check them. Required: a number
  /// nobody can check is a guess, and a guess says so here.
  final String source;

  /// The keys of this group's JSON this build did not read, as they were.
  final Map<String, Object?> unknown;

  /// This group as JSON: its numbers by their wire names, then [source], then
  /// [unknown]. A number left out is not known.
  Map<String, Object?> toJson();

  /// [known] with the source and [unknown] after it, nulls left out.
  Map<String, Object?> writeGroup(Map<String, Object?> known) =>
      <String, Object?>{
        for (final MapEntry(:key, :value) in known.entries) key: ?value,
        'source': source,
        for (final MapEntry(:key, :value) in unknown.entries)
          if (!known.containsKey(key) && key != 'source') key: value,
      };
}

/// How a material holds together and meets another: its density, its
/// stiffness and strength, and its contact.
///
/// **The contact numbers are the material against itself** — steel on steel,
/// ice on ice — because friction and bounce belong to a pair. Two materials
/// meeting combine by `MaterialCatalog.contact`'s rule (the geometric mean
/// of μ, the larger e), unless the catalogue holds a `MaterialPair` that says
/// otherwise.
final class MechanicalProperties extends PropertyGroup {
  const MechanicalProperties({
    this.density,
    this.youngsModulus,
    this.poissonRatio,
    this.yieldStrength,
    this.tensileStrength,
    this.hardness,
    this.staticFriction,
    this.kineticFriction,
    this.restitution,
    this.rollingResistance,
    required super.source,
    super.unknown,
  });

  /// Kilograms per cubic metre: the bulk density for a granular material, a
  /// pile's with its air.
  final double? density;

  /// Young's modulus, Pa: how hard it is to stretch. For an anisotropic
  /// material, the direction its doc names — wood's across the grain, which
  /// is what a contact presses.
  final double? youngsModulus;

  /// Poisson's ratio: how much it narrows as it stretches. No unit; 0.5 is
  /// incompressible.
  final double? poissonRatio;

  /// The stress it yields at, Pa: where it stops springing back.
  final double? yieldStrength;

  /// The stress it breaks at in tension, Pa.
  final double? tensileStrength;

  /// Its indentation hardness as a pressure, Pa (Vickers, HV × 9.807 MPa).
  final double? hardness;

  /// The coefficient of static friction against itself: the push, over the
  /// load, that starts it sliding. No unit.
  final double? staticFriction;

  /// The coefficient of kinetic friction against itself: the drag, over the
  /// load, while it slides. No unit.
  final double? kineticFriction;

  /// The coefficient of restitution against itself: the speed it parts at,
  /// over the speed it met at. No unit, nought to one.
  final double? restitution;

  /// The coefficient of rolling resistance: the force that holds back a
  /// wheel or a ball of it, over the load. No unit.
  final double? rollingResistance;

  /// **The one μ the engine's solvers use**, no unit: the kinetic
  /// coefficient, or the static where only that is known; null when neither
  /// is.
  ///
  /// The engine has a single coefficient of friction, not a static and a
  /// kinetic one (docs/CONTRACTS.md): a body sliding is what the solver
  /// limits, and a body at rest is held by the same μ. The static value is
  /// kept for whoever needs it — a tool that answers "will this slide at
  /// all" — and for the record.
  double? get friction => kineticFriction ?? staticFriction;

  @override
  Map<String, Object?> toJson() => writeGroup(<String, Object?>{
    'density': density,
    'youngsModulus': youngsModulus,
    'poissonRatio': poissonRatio,
    'yieldStrength': yieldStrength,
    'tensileStrength': tensileStrength,
    'hardness': hardness,
    'staticFriction': staticFriction,
    'kineticFriction': kineticFriction,
    'restitution': restitution,
    'rollingResistance': rollingResistance,
  });

  /// The group [json] holds. Throws a `MaterialFormatException` for a number
  /// that is not one, or no source.
  factory MechanicalProperties.fromJson(Map<String, Object?> json) {
    final read = GroupReader(json, 'mechanical', _keys);
    return MechanicalProperties(
      density: read.number('density'),
      youngsModulus: read.number('youngsModulus'),
      poissonRatio: read.number('poissonRatio'),
      yieldStrength: read.number('yieldStrength'),
      tensileStrength: read.number('tensileStrength'),
      hardness: read.number('hardness'),
      staticFriction: read.number('staticFriction'),
      kineticFriction: read.number('kineticFriction'),
      restitution: read.number('restitution'),
      rollingResistance: read.number('rollingResistance'),
      source: read.source,
      unknown: read.unknown,
    );
  }

  static const Set<String> _keys = <String>{
    'density',
    'youngsModulus',
    'poissonRatio',
    'yieldStrength',
    'tensileStrength',
    'hardness',
    'staticFriction',
    'kineticFriction',
    'restitution',
    'rollingResistance',
  };
}

/// How a liquid or a gas flows: its viscosity, its surface's pull and how
/// hard it is to squeeze. Its density is its [MechanicalProperties.density].
final class FluidProperties extends PropertyGroup {
  const FluidProperties({
    this.viscosity,
    this.surfaceTension,
    this.bulkModulus,
    required super.source,
    super.unknown,
  });

  /// Dynamic viscosity, Pa·s.
  final double? viscosity;

  /// Surface tension against air, N/m.
  final double? surfaceTension;

  /// Bulk modulus, Pa: the pressure it takes to squeeze it by its own volume
  /// — what the speed of sound in it goes by, c = √(K / ρ).
  final double? bulkModulus;

  @override
  Map<String, Object?> toJson() => writeGroup(<String, Object?>{
    'viscosity': viscosity,
    'surfaceTension': surfaceTension,
    'bulkModulus': bulkModulus,
  });

  /// The group [json] holds. Throws a `MaterialFormatException` for a number
  /// that is not one, or no source.
  factory FluidProperties.fromJson(Map<String, Object?> json) {
    final read = GroupReader(json, 'fluid', _keys);
    return FluidProperties(
      viscosity: read.number('viscosity'),
      surfaceTension: read.number('surfaceTension'),
      bulkModulus: read.number('bulkModulus'),
      source: read.source,
      unknown: read.unknown,
    );
  }

  static const Set<String> _keys = <String>{
    'viscosity',
    'surfaceTension',
    'bulkModulus',
  };
}

/// How a material takes heat, gives it off, changes phase and burns.
///
/// What the core's heat model reads of a body, a liquid's heat and a fire's
/// fuel is a view of this group (`NativeMaterial`, `NativeLiquidHeat`); the
/// rest of a fire's model — how a flame creeps, how its char grows — is the
/// fire model's own, in the core.
final class ThermalProperties extends PropertyGroup {
  const ThermalProperties({
    this.specificHeat,
    this.conductivity,
    this.volumetricExpansion,
    this.meltingPoint,
    this.boilingPoint,
    this.latentHeatOfFusion,
    this.latentHeatOfVaporization,
    this.emissivity,
    this.ignitionTemperature,
    this.autoignitionTemperature,
    this.heatOfCombustion,
    this.radiantFraction,
    required super.source,
    super.unknown,
  });

  /// Specific heat capacity at constant pressure, J/(kg·K).
  final double? specificHeat;

  /// Thermal conductivity, W/(m·K).
  final double? conductivity;

  /// The volumetric thermal expansion coefficient, 1/K: the fraction its
  /// volume grows by per kelvin — three times a solid's linear one.
  final double? volumetricExpansion;

  /// Where it melts at one standard atmosphere, K.
  final double? meltingPoint;

  /// Where it boils at one standard atmosphere, K.
  final double? boilingPoint;

  /// The heat that melts a kilogram at [meltingPoint], J/kg.
  final double? latentHeatOfFusion;

  /// The heat that boils a kilogram at [boilingPoint], J/kg.
  final double? latentHeatOfVaporization;

  /// Its surface's total hemispherical emissivity: the share of a black
  /// body's radiation it gives off at its temperature. No unit, nought to one.
  final double? emissivity;

  /// The surface temperature it catches at with a pilot flame, K.
  final double? ignitionTemperature;

  /// The temperature it catches at on its own, with no flame, K.
  final double? autoignitionTemperature;

  /// The heat a kilogram of it gives burning, J/kg: the effective heat of
  /// combustion a fire test measures, not the bomb calorimeter's gross one,
  /// where the source says so.
  final double? heatOfCombustion;

  /// The share of its flame's heat given off as radiation. No unit, nought to
  /// one.
  final double? radiantFraction;

  @override
  Map<String, Object?> toJson() => writeGroup(<String, Object?>{
    'specificHeat': specificHeat,
    'conductivity': conductivity,
    'volumetricExpansion': volumetricExpansion,
    'meltingPoint': meltingPoint,
    'boilingPoint': boilingPoint,
    'latentHeatOfFusion': latentHeatOfFusion,
    'latentHeatOfVaporization': latentHeatOfVaporization,
    'emissivity': emissivity,
    'ignitionTemperature': ignitionTemperature,
    'autoignitionTemperature': autoignitionTemperature,
    'heatOfCombustion': heatOfCombustion,
    'radiantFraction': radiantFraction,
  });

  /// The group [json] holds. Throws a `MaterialFormatException` for a number
  /// that is not one, or no source.
  factory ThermalProperties.fromJson(Map<String, Object?> json) {
    final read = GroupReader(json, 'thermal', _keys);
    return ThermalProperties(
      specificHeat: read.number('specificHeat'),
      conductivity: read.number('conductivity'),
      volumetricExpansion: read.number('volumetricExpansion'),
      meltingPoint: read.number('meltingPoint'),
      boilingPoint: read.number('boilingPoint'),
      latentHeatOfFusion: read.number('latentHeatOfFusion'),
      latentHeatOfVaporization: read.number('latentHeatOfVaporization'),
      emissivity: read.number('emissivity'),
      ignitionTemperature: read.number('ignitionTemperature'),
      autoignitionTemperature: read.number('autoignitionTemperature'),
      heatOfCombustion: read.number('heatOfCombustion'),
      radiantFraction: read.number('radiantFraction'),
      source: read.source,
      unknown: read.unknown,
    );
  }

  static const Set<String> _keys = <String>{
    'specificHeat',
    'conductivity',
    'volumetricExpansion',
    'meltingPoint',
    'boilingPoint',
    'latentHeatOfFusion',
    'latentHeatOfVaporization',
    'emissivity',
    'ignitionTemperature',
    'autoignitionTemperature',
    'heatOfCombustion',
    'radiantFraction',
  };
}

/// How a material meets sound: what a surface of it absorbs, band by band,
/// and how fast sound crosses it.
final class AcousticProperties extends PropertyGroup {
  const AcousticProperties({
    this.absorption,
    this.speedOfSound,
    this.impedance,
    required super.source,
    super.unknown,
  });

  /// The octave bands [absorption] is given in, by their centres, Hz.
  static const List<double> bands = <double>[
    125.0,
    250.0,
    500.0,
    1000.0,
    2000.0,
    4000.0,
  ];

  /// The random-incidence absorption coefficient of a surface of it in each
  /// of [bands]: the share of the sound falling on it that is not reflected.
  /// No unit, nought to one; six values, or null when not known.
  final List<double>? absorption;

  /// How fast sound crosses it, m/s: a solid's longitudinal bulk wave, a
  /// fluid's c = √(K / ρ).
  final double? speedOfSound;

  /// Its characteristic acoustic impedance, ρc, Pa·s/m (rayl); null to take
  /// it from the density and [speedOfSound].
  final double? impedance;

  @override
  Map<String, Object?> toJson() => writeGroup(<String, Object?>{
    'absorption': absorption,
    'speedOfSound': speedOfSound,
    'impedance': impedance,
  });

  /// The group [json] holds. Throws a `MaterialFormatException` for a number
  /// that is not one, an absorption that is not six of them, or no source.
  factory AcousticProperties.fromJson(Map<String, Object?> json) {
    final read = GroupReader(json, 'acoustic', _keys);
    return AcousticProperties(
      absorption: read.numbers('absorption', count: bands.length),
      speedOfSound: read.number('speedOfSound'),
      impedance: read.number('impedance'),
      source: read.source,
      unknown: read.unknown,
    );
  }

  static const Set<String> _keys = <String>{
    'absorption',
    'speedOfSound',
    'impedance',
  };
}

/// Three numbers for the red, green and blue of linear light: a reflectance,
/// or a coefficient per metre — the field that holds one says which.
final class RgbValues {
  const RgbValues(this.red, this.green, this.blue);

  /// The same value in all three.
  const RgbValues.all(double value) : this(value, value, value);

  final double red, green, blue;

  /// `[red, green, blue]`, as a file holds them.
  List<double> toJson() => <double>[red, green, blue];

  @override
  bool operator ==(Object other) =>
      other is RgbValues &&
      other.red == red &&
      other.green == green &&
      other.blue == blue;

  @override
  int get hashCode => Object.hash(red, green, blue);

  @override
  String toString() => 'RgbValues($red, $green, $blue)';
}

/// How a material meets light: what it bends, absorbs and reflects.
///
/// **Informative, for the renderer's materials to refer to**: a rendering
/// material (`RenderMaterial`, a `.fmat`) stays its own thing, with the
/// look an artist chose, and may be made from these — a glass's index, a
/// metal's F0 — rather than the other way round.
final class OpticalProperties extends PropertyGroup {
  const OpticalProperties({
    this.refractiveIndex,
    this.abbeNumber,
    this.absorption,
    this.metalReflectance,
    this.roughnessMin,
    this.roughnessMax,
    required super.source,
    super.unknown,
  });

  /// The refractive index at the sodium D line, 589 nm (n_D). No unit.
  final double? refractiveIndex;

  /// The Abbe number, (n_d − 1) / (n_F − n_C): how little it disperses. No
  /// unit; higher is less.
  final double? abbeNumber;

  /// The absorption coefficient for linear red, green and blue light, per
  /// metre: what Beer–Lambert's e^(−αd) takes through a depth d of it.
  final RgbValues? absorption;

  /// A metal's reflectance at normal incidence, F0, in linear red, green and
  /// blue (Hoffman, "Physics and Math of Shading", SIGGRAPH 2015 course, and
  /// Real-Time Rendering, 4th ed., table 9.2). No unit, nought to one.
  final RgbValues? metalReflectance;

  /// The least and most perceptual roughness its surfaces usually show, as a
  /// metallic–roughness material's roughness: a guide, not a measurement. No
  /// unit, nought to one.
  final double? roughnessMin, roughnessMax;

  @override
  Map<String, Object?> toJson() => writeGroup(<String, Object?>{
    'refractiveIndex': refractiveIndex,
    'abbeNumber': abbeNumber,
    'absorption': absorption?.toJson(),
    'metalReflectance': metalReflectance?.toJson(),
    'roughnessMin': roughnessMin,
    'roughnessMax': roughnessMax,
  });

  /// The group [json] holds. Throws a `MaterialFormatException` for a number
  /// that is not one, a colour that is not three of them, or no source.
  factory OpticalProperties.fromJson(Map<String, Object?> json) {
    final read = GroupReader(json, 'optical', _keys);
    RgbValues? rgb(String key) => switch (read.numbers(key, count: 3)) {
      null => null,
      final List<double> v => RgbValues(v[0], v[1], v[2]),
    };
    return OpticalProperties(
      refractiveIndex: read.number('refractiveIndex'),
      abbeNumber: read.number('abbeNumber'),
      absorption: rgb('absorption'),
      metalReflectance: rgb('metalReflectance'),
      roughnessMin: read.number('roughnessMin'),
      roughnessMax: read.number('roughnessMax'),
      source: read.source,
      unknown: read.unknown,
    );
  }

  static const Set<String> _keys = <String>{
    'refractiveIndex',
    'abbeNumber',
    'absorption',
    'metalReflectance',
    'roughnessMin',
    'roughnessMax',
  };
}

/// How a material carries a current.
final class ElectricalProperties extends PropertyGroup {
  const ElectricalProperties({
    this.resistivity,
    required super.source,
    super.unknown,
  });

  /// Electrical resistivity at the material's quoted temperature, in ohm
  /// metres (Ω·m).
  final double? resistivity;

  @override
  Map<String, Object?> toJson() =>
      writeGroup(<String, Object?>{'resistivity': resistivity});

  /// The group [json] holds. Throws a `MaterialFormatException` for a number
  /// that is not one, or no source.
  factory ElectricalProperties.fromJson(Map<String, Object?> json) {
    final read = GroupReader(json, 'electrical', _keys);
    return ElectricalProperties(
      resistivity: read.number('resistivity'),
      source: read.source,
      unknown: read.unknown,
    );
  }

  static const Set<String> _keys = <String>{'resistivity'};
}
