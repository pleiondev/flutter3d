/// What a material is, in groups: its mechanics, its flow, its heat, its
/// sound, its light, its current and how it gives way — each a small value
/// of its own.
///
/// **A group per kind of question**, so a material says only what it knows —
/// glass has no viscosity a game asks for, water no yield strength — and a
/// group a later minor adds (magnetic, say) arrives as one more optional
/// field of `PhysicalMaterial` and one more key in its file, breaking
/// nobody. Every number is in SI, the unit in its doc and in
/// [propertyUnits]; every group names the [PropertyGroup.source] its numbers
/// were read from, which a plugin's material must give too.
///
/// **Every scalar property is a [PropertyLaw]**: its value at the
/// material's reference state ([PropertyLaw.value]) and how it changes with
/// a body's state ([PropertyLaw.at]). A property nothing is known to change
/// is a [ConstantLaw]. Band and colour lists (an absorption per octave, a
/// metal's F0 in red, green and blue) stay lists of numbers at the
/// reference state.
library;

import 'package:flutter3d_foundation/flutter3d_foundation.dart'
    show Dimension, Unit;

import 'material_json.dart';
import 'property_law.dart';

/// What every group of a material's properties has: the source its numbers
/// were read from, and the keys of its file a later version wrote that this
/// one does not know, kept so they are written back.
///
/// **Not sealed**, so a group added in a minor breaks no switch over them.
abstract base class PropertyGroup {
  /// A group whose numbers come from [source], keeping the [unknown] keys
  /// of its JSON.
  const PropertyGroup({
    required this.source,
    this.unknown = const <String, Object?>{},
  });

  /// Where the numbers come from: a handbook and its table, a paper, a
  /// datasheet — whatever a reader needs to check them. Required: a number
  /// nobody can check is a guess, and a guess says so here. A value with a
  /// source of its own says it on its law ([PropertyLaw.source]).
  final String source;

  /// The keys of this group's JSON this build did not read, as they were.
  final Map<String, Object?> unknown;

  /// The group's word in a file: `mechanical`, `thermal`, ….
  String get name;

  /// Every scalar property the group holds, by its wire name.
  Map<String, PropertyLaw> get laws;

  /// This group as JSON: its numbers by their wire names, then [source], then
  /// [unknown]. A number left out is not known.
  Map<String, Object?> toJson();

  /// [known] with the source and [unknown] after it, nulls left out, laws
  /// as [PropertyLaw.toJson] writes them.
  Map<String, Object?> writeGroup(Map<String, Object?> known) =>
      <String, Object?>{
        for (final MapEntry(:key, :value) in known.entries)
          key: ?(value is PropertyLaw ? value.toJson() : value),
        'source': source,
        for (final MapEntry(:key, :value) in unknown.entries)
          if (!known.containsKey(key) && key != 'source') key: value,
      };
}

const Unit _kgPerM3 = Unit('kg/m³', Dimension(<String, int>{'kg': 1, 'm': -3}));
const Unit _perKelvin = Unit('1/K', Dimension(<String, int>{'K': -1}));
const Unit _jPerKgK = Unit(
  'J/(kg·K)',
  Dimension(<String, int>{'m': 2, 's': -2, 'K': -1}),
);
const Unit _wPerMK = Unit(
  'W/(m·K)',
  Dimension(<String, int>{'kg': 1, 'm': 1, 's': -3, 'K': -1}),
);
const Unit _jPerKg = Unit('J/kg', Dimension(<String, int>{'m': 2, 's': -2}));
const Unit _rayl = Unit(
  'Pa·s/m',
  Dimension(<String, int>{'kg': 1, 'm': -2, 's': -1}),
);
const Unit _ohmMeter = Unit(
  'Ω·m',
  Dimension(<String, int>{'kg': 1, 'm': 3, 's': -3, 'A': -2}),
);

/// The unit of every scalar property, by `<group>.<property>`: what its
/// [PropertyLaw] gives, and what a formula law's value must measure.
const Map<String, Unit> propertyUnits = <String, Unit>{
  'mechanical.density': _kgPerM3,
  'mechanical.youngsModulus': Unit.pascal,
  'mechanical.poissonRatio': Unit.one,
  'mechanical.yieldStrength': Unit.pascal,
  'mechanical.tensileStrength': Unit.pascal,
  'mechanical.hardness': Unit.pascal,
  'mechanical.staticFriction': Unit.one,
  'mechanical.kineticFriction': Unit.one,
  'mechanical.restitution': Unit.one,
  'mechanical.rollingResistance': Unit.one,
  'fluid.viscosity': Unit.pascalSecond,
  'fluid.surfaceTension': Unit.newtonPerMeter,
  'fluid.bulkModulus': Unit.pascal,
  'thermal.specificHeat': _jPerKgK,
  'thermal.conductivity': _wPerMK,
  'thermal.volumetricExpansion': _perKelvin,
  'thermal.meltingPoint': Unit.kelvin,
  'thermal.boilingPoint': Unit.kelvin,
  'thermal.latentHeatOfFusion': _jPerKg,
  'thermal.latentHeatOfVaporization': _jPerKg,
  'thermal.emissivity': Unit.one,
  'thermal.ignitionTemperature': Unit.kelvin,
  'thermal.autoignitionTemperature': Unit.kelvin,
  'thermal.heatOfCombustion': _jPerKg,
  'thermal.radiantFraction': Unit.one,
  'acoustic.speedOfSound': Unit.meterPerSecond,
  'acoustic.impedance': _rayl,
  'optical.refractiveIndex': Unit.one,
  'optical.abbeNumber': Unit.one,
  'optical.dielectricF0': Unit.one,
  'optical.roughnessMin': Unit.one,
  'optical.roughnessMax': Unit.one,
  'electrical.resistivity': _ohmMeter,
  'inelastic.lossFactor': Unit.one,
};

/// How a material holds together and meets another: its density, its
/// stiffness and strength, and its contact.
///
/// **The contact numbers are the material against itself** — steel on steel,
/// ice on ice — because friction and bounce belong to a pair. Two materials
/// meeting combine by `MaterialCatalog.contact`'s rule (the geometric mean
/// of μ, the larger e), unless the catalogue holds a `MaterialPair` that says
/// otherwise.
final class MechanicalProperties extends PropertyGroup {
  /// The group from [source]; a property left null is not known.
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

  /// The group [json] holds. Throws a `MaterialFormatException` for a value
  /// that is not a number or a law, or no source.
  factory MechanicalProperties.fromJson(Map<String, Object?> json) {
    final read = GroupReader(json, 'mechanical', _keys);
    return MechanicalProperties(
      density: read.law('density'),
      youngsModulus: read.law('youngsModulus'),
      poissonRatio: read.law('poissonRatio'),
      yieldStrength: read.law('yieldStrength'),
      tensileStrength: read.law('tensileStrength'),
      hardness: read.law('hardness'),
      staticFriction: read.law('staticFriction'),
      kineticFriction: read.law('kineticFriction'),
      restitution: read.law('restitution'),
      rollingResistance: read.law('rollingResistance'),
      source: read.source,
      unknown: read.unknown,
    );
  }

  /// Kilograms per cubic metre: the bulk density for a granular material, a
  /// pile's with its air.
  final PropertyLaw? density;

  /// Young's modulus, Pa: how hard it is to stretch. For an anisotropic
  /// material, the direction its doc names — wood's across the grain, which
  /// is what a contact presses.
  final PropertyLaw? youngsModulus;

  /// Poisson's ratio: how much it narrows as it stretches. No unit; 0.5 is
  /// incompressible.
  final PropertyLaw? poissonRatio;

  /// The stress it yields at, Pa: where it stops springing back.
  final PropertyLaw? yieldStrength;

  /// The stress it breaks at in tension, Pa.
  final PropertyLaw? tensileStrength;

  /// Its indentation hardness as a pressure, Pa (Vickers, HV × 9.807 MPa).
  final PropertyLaw? hardness;

  /// The coefficient of static friction against itself: the push, over the
  /// load, that starts it sliding. No unit.
  final PropertyLaw? staticFriction;

  /// The coefficient of kinetic friction against itself: the drag, over the
  /// load, while it slides. No unit.
  final PropertyLaw? kineticFriction;

  /// The coefficient of restitution against itself: the speed it parts at,
  /// over the speed it met at. No unit, nought to one.
  final PropertyLaw? restitution;

  /// The coefficient of rolling resistance: the force that holds back a
  /// wheel or a ball of it, over the load. No unit.
  final PropertyLaw? rollingResistance;

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

  /// **The one μ the engine's solvers use**, no unit: the kinetic
  /// coefficient, or the static where only that is known; null when neither
  /// is.
  ///
  /// The engine has a single coefficient of friction, not a static and a
  /// kinetic one (docs/CONTRACTS.md): a body sliding is what the solver
  /// limits, and a body at rest is held by the same μ. The static value is
  /// kept for whoever needs it — a tool that answers "will this slide at
  /// all" — and for the record.
  PropertyLaw? get friction => kineticFriction ?? staticFriction;

  @override
  String get name => 'mechanical';

  @override
  Map<String, PropertyLaw> get laws => <String, PropertyLaw>{
    'density': ?density,
    'youngsModulus': ?youngsModulus,
    'poissonRatio': ?poissonRatio,
    'yieldStrength': ?yieldStrength,
    'tensileStrength': ?tensileStrength,
    'hardness': ?hardness,
    'staticFriction': ?staticFriction,
    'kineticFriction': ?kineticFriction,
    'restitution': ?restitution,
    'rollingResistance': ?rollingResistance,
  };

  @override
  Map<String, Object?> toJson() => writeGroup(laws);
}

/// How a liquid or a gas flows: its viscosity, its surface's pull and how
/// hard it is to squeeze. Its density is its [MechanicalProperties.density].
final class FluidProperties extends PropertyGroup {
  /// The group from [source]; a property left null is not known.
  const FluidProperties({
    this.viscosity,
    this.surfaceTension,
    this.bulkModulus,
    required super.source,
    super.unknown,
  });

  /// The group [json] holds. Throws a `MaterialFormatException` for a value
  /// that is not a number or a law, or no source.
  factory FluidProperties.fromJson(Map<String, Object?> json) {
    final read = GroupReader(json, 'fluid', _keys);
    return FluidProperties(
      viscosity: read.law('viscosity'),
      surfaceTension: read.law('surfaceTension'),
      bulkModulus: read.law('bulkModulus'),
      source: read.source,
      unknown: read.unknown,
    );
  }

  /// Dynamic viscosity, Pa·s.
  final PropertyLaw? viscosity;

  /// Surface tension against air, N/m.
  final PropertyLaw? surfaceTension;

  /// Bulk modulus, Pa: the pressure it takes to squeeze it by its own volume
  /// — what the speed of sound in it goes by, c = √(K / ρ).
  final PropertyLaw? bulkModulus;

  static const Set<String> _keys = <String>{
    'viscosity',
    'surfaceTension',
    'bulkModulus',
  };

  @override
  String get name => 'fluid';

  @override
  Map<String, PropertyLaw> get laws => <String, PropertyLaw>{
    'viscosity': ?viscosity,
    'surfaceTension': ?surfaceTension,
    'bulkModulus': ?bulkModulus,
  };

  @override
  Map<String, Object?> toJson() => writeGroup(laws);
}

/// How a material takes heat, gives it off, changes phase and burns.
///
/// What the core's heat model reads of a body, a liquid's heat and a fire's
/// fuel is a view of this group (`NativeMaterial`, `NativeLiquidHeat`); the
/// rest of a fire's model — how a flame creeps, how its char grows — is the
/// fire model's own, in the core.
final class ThermalProperties extends PropertyGroup {
  /// The group from [source]; a property left null is not known.
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
    this.glowTemperature,
    this.heatOfCombustion,
    this.effectiveHeatOfCombustion,
    this.radiantFraction,
    required super.source,
    super.unknown,
  });

  /// The group [json] holds. Throws a `MaterialFormatException` for a value
  /// that is not a number or a law, or no source.
  factory ThermalProperties.fromJson(Map<String, Object?> json) {
    final read = GroupReader(json, 'thermal', _keys);
    return ThermalProperties(
      specificHeat: read.law('specificHeat'),
      conductivity: read.law('conductivity'),
      volumetricExpansion: read.law('volumetricExpansion'),
      meltingPoint: read.law('meltingPoint'),
      boilingPoint: read.law('boilingPoint'),
      latentHeatOfFusion: read.law('latentHeatOfFusion'),
      latentHeatOfVaporization: read.law('latentHeatOfVaporization'),
      emissivity: read.law('emissivity'),
      ignitionTemperature: read.law('ignitionTemperature'),
      autoignitionTemperature: read.law('autoignitionTemperature'),
      glowTemperature: read.law('glowTemperature'),
      heatOfCombustion: read.law('heatOfCombustion'),
      effectiveHeatOfCombustion: read.law('effectiveHeatOfCombustion'),
      radiantFraction: read.law('radiantFraction'),
      source: read.source,
      unknown: read.unknown,
    );
  }

  /// Specific heat capacity at constant pressure, J/(kg·K).
  final PropertyLaw? specificHeat;

  /// Thermal conductivity, W/(m·K).
  final PropertyLaw? conductivity;

  /// The volumetric thermal expansion coefficient, 1/K: the fraction its
  /// volume grows by per kelvin — three times a solid's linear one.
  final PropertyLaw? volumetricExpansion;

  /// Where it melts at one standard atmosphere, K; for a melt, where it
  /// sets solid.
  final PropertyLaw? meltingPoint;

  /// Where it boils at one standard atmosphere, K.
  final PropertyLaw? boilingPoint;

  /// The heat that melts a kilogram at [meltingPoint], J/kg.
  final PropertyLaw? latentHeatOfFusion;

  /// The heat that boils a kilogram at [boilingPoint], J/kg.
  final PropertyLaw? latentHeatOfVaporization;

  /// Its surface's total hemispherical emissivity: the share of a black
  /// body's radiation it gives off at its temperature. No unit, nought to one.
  final PropertyLaw? emissivity;

  /// The surface temperature it catches at with a pilot flame, K.
  final PropertyLaw? ignitionTemperature;

  /// The temperature it catches at on its own, with no flame, K.
  final PropertyLaw? autoignitionTemperature;

  /// The coolest surface it glows on at by itself, with no flame, K: for a
  /// solid that burns at its surface rather than in a flame over it — a
  /// charcoal, a smouldering char — where the heat of the rate oxygen
  /// reaches it pays for what the surface loses. Null for a material whose
  /// fire is a flame, where [ignitionTemperature] says where it catches. A
  /// fire model reads this before [ignitionTemperature] when both are known.
  final PropertyLaw? glowTemperature;

  /// The heat a kilogram of it gives burning, J/kg, as its source gives it:
  /// a bomb calorimeter's gross heat, or the effective heat a fire test
  /// measures, the source and its description say which.
  final PropertyLaw? heatOfCombustion;

  /// The heat a kilogram of it gives in a fire, J/kg: what a fire test
  /// measures (a cone calorimeter, a furniture or pile calorimeter), below
  /// [heatOfCombustion] by the share a sooty flame leaves unburnt. Given
  /// where the catalogue's [heatOfCombustion] is the gross one; a fire model
  /// reads it before [heatOfCombustion] when both are known.
  final PropertyLaw? effectiveHeatOfCombustion;

  /// The share of its flame's heat given off as radiation. No unit, nought to
  /// one.
  final PropertyLaw? radiantFraction;

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
    'glowTemperature',
    'heatOfCombustion',
    'effectiveHeatOfCombustion',
    'radiantFraction',
  };

  @override
  String get name => 'thermal';

  @override
  Map<String, PropertyLaw> get laws => <String, PropertyLaw>{
    'specificHeat': ?specificHeat,
    'conductivity': ?conductivity,
    'volumetricExpansion': ?volumetricExpansion,
    'meltingPoint': ?meltingPoint,
    'boilingPoint': ?boilingPoint,
    'latentHeatOfFusion': ?latentHeatOfFusion,
    'latentHeatOfVaporization': ?latentHeatOfVaporization,
    'emissivity': ?emissivity,
    'ignitionTemperature': ?ignitionTemperature,
    'autoignitionTemperature': ?autoignitionTemperature,
    'glowTemperature': ?glowTemperature,
    'heatOfCombustion': ?heatOfCombustion,
    'effectiveHeatOfCombustion': ?effectiveHeatOfCombustion,
    'radiantFraction': ?radiantFraction,
  };

  @override
  Map<String, Object?> toJson() => writeGroup(laws);
}

/// How a material meets sound: what a surface of it absorbs, band by band,
/// and how fast sound crosses it.
final class AcousticProperties extends PropertyGroup {
  /// The group from [source]; a property left null is not known.
  const AcousticProperties({
    this.absorption,
    this.speedOfSound,
    this.impedance,
    required super.source,
    super.unknown,
  });

  /// The group [json] holds. Throws a `MaterialFormatException` for a value
  /// that is not a number or a law, an absorption that is not six numbers,
  /// or no source.
  factory AcousticProperties.fromJson(Map<String, Object?> json) {
    final read = GroupReader(json, 'acoustic', _keys);
    return AcousticProperties(
      absorption: read.numbers('absorption', count: bands.length),
      speedOfSound: read.law('speedOfSound'),
      impedance: read.law('impedance'),
      source: read.source,
      unknown: read.unknown,
    );
  }

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
  final PropertyLaw? speedOfSound;

  /// Its characteristic acoustic impedance, ρc, Pa·s/m (rayl); null to take
  /// it from the density and [speedOfSound].
  final PropertyLaw? impedance;

  static const Set<String> _keys = <String>{
    'absorption',
    'speedOfSound',
    'impedance',
  };

  @override
  String get name => 'acoustic';

  @override
  Map<String, PropertyLaw> get laws => <String, PropertyLaw>{
    'speedOfSound': ?speedOfSound,
    'impedance': ?impedance,
  };

  @override
  Map<String, Object?> toJson() =>
      writeGroup(<String, Object?>{'absorption': absorption, ...laws});
}

/// Three numbers for the red, green and blue of linear light: a reflectance,
/// or a coefficient per metre — the field that holds one says which.
final class RgbValues {
  /// The values [red], [green] and [blue].
  const RgbValues(this.red, this.green, this.blue);

  /// The same value in all three.
  const RgbValues.all(double value) : this(value, value, value);

  /// The value for each channel of linear light, in the unit the field
  /// holding it gives: a reflectance fraction or a coefficient per metre.
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
/// dielectric's F0, a metal's — rather than the other way round.
final class OpticalProperties extends PropertyGroup {
  /// The group from [source]; a property left null is not known.
  const OpticalProperties({
    this.refractiveIndex,
    this.abbeNumber,
    this.dielectricF0,
    this.absorption,
    this.metalReflectance,
    this.roughnessMin,
    this.roughnessMax,
    required super.source,
    super.unknown,
  });

  /// The group [json] holds. Throws a `MaterialFormatException` for a value
  /// that is not a number or a law, a colour that is not three numbers, or
  /// no source.
  factory OpticalProperties.fromJson(Map<String, Object?> json) {
    final read = GroupReader(json, 'optical', _keys);
    RgbValues? rgb(String key) => switch (read.numbers(key, count: 3)) {
      null => null,
      final List<double> v => RgbValues(v[0], v[1], v[2]),
    };
    return OpticalProperties(
      refractiveIndex: read.law('refractiveIndex'),
      abbeNumber: read.law('abbeNumber'),
      dielectricF0: read.law('dielectricF0'),
      absorption: rgb('absorption'),
      metalReflectance: rgb('metalReflectance'),
      roughnessMin: read.law('roughnessMin'),
      roughnessMax: read.law('roughnessMax'),
      source: read.source,
      unknown: read.unknown,
    );
  }

  /// The refractive index at the sodium D line, 589 nm (n_D). No unit.
  final PropertyLaw? refractiveIndex;

  /// The Abbe number, (n_d − 1) / (n_F − n_C): how little it disperses. No
  /// unit; higher is less.
  final PropertyLaw? abbeNumber;

  /// A dielectric's reflectance at normal incidence from air, F0 = ((n −
  /// 1) / (n + 1))², what a metallic–roughness material's specular is for a
  /// non-metal of it. No unit, nought to one. [f0] gives it from
  /// [refractiveIndex] where it is not said.
  final PropertyLaw? dielectricF0;

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
  final PropertyLaw? roughnessMin, roughnessMax;

  static const Set<String> _keys = <String>{
    'refractiveIndex',
    'abbeNumber',
    'dielectricF0',
    'absorption',
    'metalReflectance',
    'roughnessMin',
    'roughnessMax',
  };

  /// The dielectric F0 at the reference state: [dielectricF0]'s, or ((n −
  /// 1) / (n + 1))² from [refractiveIndex]; null when neither is known.
  double? get f0 {
    if (dielectricF0 case final said?) return said.value;
    final n = refractiveIndex?.value;
    if (n == null) return null;
    final r = (n - 1.0) / (n + 1.0);
    return r * r;
  }

  @override
  String get name => 'optical';

  @override
  Map<String, PropertyLaw> get laws => <String, PropertyLaw>{
    'refractiveIndex': ?refractiveIndex,
    'abbeNumber': ?abbeNumber,
    'dielectricF0': ?dielectricF0,
    'roughnessMin': ?roughnessMin,
    'roughnessMax': ?roughnessMax,
  };

  @override
  Map<String, Object?> toJson() => writeGroup(<String, Object?>{
    'refractiveIndex': refractiveIndex,
    'abbeNumber': abbeNumber,
    'dielectricF0': dielectricF0,
    'absorption': absorption?.toJson(),
    'metalReflectance': metalReflectance?.toJson(),
    'roughnessMin': roughnessMin,
    'roughnessMax': roughnessMax,
  });
}

/// How a material carries a current.
final class ElectricalProperties extends PropertyGroup {
  /// The group from [source]; a [resistivity] left null is not known.
  const ElectricalProperties({
    this.resistivity,
    required super.source,
    super.unknown,
  });

  /// The group [json] holds. Throws a `MaterialFormatException` for a value
  /// that is not a number or a law, or no source.
  factory ElectricalProperties.fromJson(Map<String, Object?> json) {
    final read = GroupReader(json, 'electrical', _keys);
    return ElectricalProperties(
      resistivity: read.law('resistivity'),
      source: read.source,
      unknown: read.unknown,
    );
  }

  /// Electrical resistivity, in ohm metres (Ω·m).
  final PropertyLaw? resistivity;

  static const Set<String> _keys = <String>{'resistivity'};

  @override
  String get name => 'electrical';

  @override
  Map<String, PropertyLaw> get laws => <String, PropertyLaw>{
    'resistivity': ?resistivity,
  };

  @override
  Map<String, Object?> toJson() => writeGroup(laws);
}

/// A constitutive model of how a material gives way past the elastic: its
/// [model]'s name and its parameters, as the paper that fitted it gives
/// them.
///
/// **A named model with named parameters, not a class per model**, so a
/// model a later minor or a plugin adds is one more name. The engine's own
/// names and their parameters:
///
/// * [ogden], hyperelastic: [terms], each `mu` (Pa) and `alpha` (no unit),
///   W = Σ (2 μ_p / α_p²)(λ₁^α + λ₂^α + λ₃^α − 3);
/// * [prony], viscoelastic: `longTermModulus` (Pa) in [parameters], and
///   [terms] each `modulus` (Pa) and `relaxationTime` (s);
/// * [johnsonCook], plastic: `A`, `B` (Pa), `n`, `C`, `m` (no unit),
///   `meltTemperature`, `roomTemperature` (K) and `referenceStrainRate`
///   (1/s), σ = (A + B εⁿ)(1 + C ln ε̇*)(1 − T*ᵐ).
final class ConstitutiveModel {
  /// The model named [model], with no parameters or terms unless given.
  const ConstitutiveModel(
    this.model, {
    this.parameters = const <String, double>{},
    this.terms = const <Map<String, double>>[],
    this.confidence,
    this.source,
  });

  /// The model [json] holds. Throws a `MaterialFormatException` for one
  /// that is not.
  factory ConstitutiveModel.fromJson(Object? json, String where) {
    if (json is! Map<String, Object?>) {
      throw MaterialFormatException('"$where" must be an object, not $json');
    }
    Map<String, double> numbers(Object? map, String what) => switch (map) {
      null => const <String, double>{},
      final Map<String, Object?> m
          when m.values.every((v) => v is num && v.isFinite) =>
        Map<String, double>.unmodifiable(<String, double>{
          for (final MapEntry(:key, :value) in m.entries)
            key: (value! as num).toDouble(),
        }),
      final other => throw MaterialFormatException(
        '"$where.$what" must map names to finite numbers, not $other',
      ),
    };
    return ConstitutiveModel(
      switch (json['model']) {
        final String name when name.isNotEmpty => name,
        final other => throw MaterialFormatException(
          '"$where.model" must be a model\'s name, not $other',
        ),
      },
      parameters: numbers(json['parameters'], 'parameters'),
      terms: switch (json['terms']) {
        null => const <Map<String, double>>[],
        final List<Object?> list => List<Map<String, double>>.unmodifiable(
          <Map<String, double>>[for (final t in list) numbers(t, 'terms')],
        ),
        final other => throw MaterialFormatException(
          '"$where.terms" must be a list, not $other',
        ),
      },
      confidence: switch (json['confidence']) {
        final String name => Confidence.named(name),
        _ => null,
      },
      source: switch (json['source']) {
        final String said => said,
        _ => null,
      },
    );
  }

  /// Ogden's hyperelastic model of a rubber.
  static const String ogden = 'ogden';

  /// A Prony series of relaxing moduli.
  static const String prony = 'prony';

  /// Johnson and Cook's flow stress of a metal.
  static const String johnsonCook = 'johnsonCook';

  /// The model's name.
  final String model;

  /// Its scalar parameters, by name, in SI.
  final Map<String, double> parameters;

  /// Its repeated terms, each a map of parameters by name, in SI.
  final List<Map<String, double>> terms;

  /// How the parameters were come by; null when the source does not say.
  final Confidence? confidence;

  /// Where the fit comes from, when it is not the group's source.
  final String? source;

  /// The model as a file holds it.
  Map<String, Object?> toJson() => <String, Object?>{
    'model': model,
    if (parameters.isNotEmpty) 'parameters': parameters,
    if (terms.isNotEmpty) 'terms': terms,
    'confidence': ?confidence?.name,
    'source': ?source,
  };

  @override
  String toString() => 'ConstitutiveModel($model)';
}

/// How a material gives way past the elastic: how much of a vibration it
/// turns to heat each cycle, and the models of its large strains, its
/// creep and its flow.
///
/// **Read by what bends and breaks**: a joint's damping, a ragdoll's soft
/// limits, a rubber's large stretch, a metal's dent. A model is data with
/// its source; which solver uses which is the solver's.
final class InelasticProperties extends PropertyGroup {
  /// The group from [source]; a loss factor or a model left null is not
  /// known.
  const InelasticProperties({
    this.lossFactor,
    this.hyperelastic,
    this.viscoelastic,
    this.plastic,
    required super.source,
    super.unknown,
  });

  /// The group [json] holds. Throws a `MaterialFormatException` for a value
  /// that is not a number or a law, a model that is not one, or no source.
  factory InelasticProperties.fromJson(Map<String, Object?> json) {
    final read = GroupReader(json, 'inelastic', _keys);
    ConstitutiveModel? model(String key) => json[key] == null
        ? null
        : ConstitutiveModel.fromJson(json[key], 'inelastic.$key');
    return InelasticProperties(
      lossFactor: read.law('lossFactor'),
      hyperelastic: model('hyperelastic'),
      viscoelastic: model('viscoelastic'),
      plastic: model('plastic'),
      source: read.source,
      unknown: read.unknown,
    );
  }

  /// The loss factor η, twice the damping ratio: the share of a cycle's
  /// elastic energy lost to heat, over 2π. No unit.
  ///
  /// What a contact damps by: in a world whose profile is not bit-exact,
  /// both physics cores bounce a contact with no more of its approach than
  /// a spring and dashpot of damping ratio η/2 gives back
  /// (`restitutionOfLossFactor` in `flutter3d_physics`), and a ragdoll's
  /// joints damp their give by it.
  final PropertyLaw? lossFactor;

  /// Its large elastic strains: a [ConstitutiveModel.ogden], say.
  final ConstitutiveModel? hyperelastic;

  /// How it relaxes under a held strain: a [ConstitutiveModel.prony].
  final ConstitutiveModel? viscoelastic;

  /// How it flows past its yield: a [ConstitutiveModel.johnsonCook].
  final ConstitutiveModel? plastic;

  static const Set<String> _keys = <String>{
    'lossFactor',
    'hyperelastic',
    'viscoelastic',
    'plastic',
  };

  @override
  String get name => 'inelastic';

  @override
  Map<String, PropertyLaw> get laws => <String, PropertyLaw>{
    'lossFactor': ?lossFactor,
  };

  @override
  Map<String, Object?> toJson() => writeGroup(<String, Object?>{
    'lossFactor': lossFactor,
    'hyperelastic': hyperelastic?.toJson(),
    'viscoelastic': viscoelastic?.toJson(),
    'plastic': plastic?.toJson(),
  });
}
