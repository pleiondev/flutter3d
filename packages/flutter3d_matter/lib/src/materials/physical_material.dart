/// What a substance is, physically: one entry of the material catalogue.
library;

import 'package:flutter3d_foundation/flutter3d_foundation.dart' show FormatSpec;

import '../standard_world.dart';
import 'material_json.dart';
import 'material_state.dart';
import 'property_groups.dart';
import 'property_law.dart';

/// What state a material is in at its quoted temperature and pressure.
///
/// **A class of constants rather than an enum**, so a plugin's material in a
/// state of its own — a plasma, a foam — names one with [MaterialPhase.named]
/// and breaks no switch written against these.
final class MaterialPhase {
  /// A phase of a plugin's own, by its [name].
  const MaterialPhase.named(this.name);

  /// Holds its shape: steel, wood, ice.
  static const MaterialPhase solid = MaterialPhase.named('solid');

  /// Flows and keeps its volume: water, oil, molten rock. [isFluid].
  static const MaterialPhase liquid = MaterialPhase.named('liquid');

  /// Flows and fills what holds it: air, steam. [isFluid].
  static const MaterialPhase gas = MaterialPhase.named('gas');

  /// Grains that pour and pile: sand, soil, gravel.
  static const MaterialPhase granular = MaterialPhase.named('granular');

  /// Its word in a file and a message.
  final String name;

  /// Whether it flows as a fluid does: a liquid or a gas.
  bool get isFluid => this == liquid || this == gas;

  @override
  bool operator ==(Object other) =>
      other is MaterialPhase && other.name == name;

  @override
  int get hashCode => name.hashCode;

  @override
  String toString() => 'MaterialPhase.$name';
}

/// The spaces of ids other systems know a substance by
/// ([PhysicalMaterial.externalIds]), by their names as a material's
/// document writes them.
///
/// **Names, not an enumeration**: a space is any string, and a converter
/// for a system the engine does not name here uses that system's own.
abstract final class ExternalIdSpace {
  /// A Chemical Abstracts Service registry number: `7732-18-5` for water.
  static const String cas = 'CAS';

  /// An IFC material category (IFC4 `IfcMaterial.Category`): `concrete`,
  /// `steel`, `wood`.
  static const String ifc = 'IFC';

  /// A MaterialX library's material name.
  static const String materialX = 'MaterialX';

  /// A metal or alloy's Unified Numbering System designation: `S30400`.
  static const String uns = 'UNS';

  /// A plastic's ISO 1043 abbreviation: `PMMA`, `PE-HD`.
  static const String iso1043 = 'ISO1043';

  /// A European standard's designation (EN 10027 and the like).
  static const String en = 'EN';

  /// The name physicallybased.info gives the material.
  static const String physicallyBased = 'physicallybased.info';
}

/// A substance and what is known of it: its density, stiffness and contact,
/// its flow, its heat, its sound, its light and its current, each a group
/// that may be absent, each naming its source.
///
/// **One entry, read by everything.** A liquid's preset
/// (`FluidMedium.water`, `NativeLiquidProperties.water`), the core's heat
/// presets (`NativeMaterial.oak`), a world's medium
/// (`WorldProperties.medium`), a collider's material
/// (`Collider.material`) are views of an entry of the `MaterialCatalog`,
/// so a number is written once — in `Materials`, for the engine's own — and
/// a plugin adds a substance the same way.
///
/// **Ids are namespaced**: `f3d.<name>` for the engine's, `<pluginId>.<name>`
/// for a plugin's, as a format's are.
///
/// **A versioned JSON codec** ([format], [toJson], [PhysicalMaterial.fromJson]),
/// in the format envelope, keeping the keys it does not know, so a file —
/// a level, a `.f3d` section, a data plugin — can hold one.
final class PhysicalMaterial {
  /// The material [id], quoted at 20 °C and one standard atmosphere unless
  /// [temperature] and [pressure] say otherwise, with every group absent
  /// unless given.
  ///
  /// Checks nothing: [problems] judges the numbers, and
  /// [PhysicalMaterial.fromJson] the id.
  const PhysicalMaterial({
    required this.id,
    required this.name,
    required this.phase,
    this.temperature = standardAirTemperature,
    this.pressure = standardAtmosphere,
    this.mechanical,
    this.fluid,
    this.thermal,
    this.acoustic,
    this.optical,
    this.electrical,
    this.inelastic,
    this.externalIds = const <String, String>{},
    this.confidence,
    this.unknown = const <String, Object?>{},
  });

  /// The material [json] describes: a document in the envelope, or a bare
  /// body as a data plugin's `physicalMaterials` list holds one.
  ///
  /// Throws a [MaterialFormatException] for a document of another format or
  /// a newer version, an id that is not `<namespace>.<name>`, a phase that is
  /// not a word, a number that is not one or a group with no source. It does
  /// not judge whether the numbers are plausible: [problems] does.
  factory PhysicalMaterial.fromJson(Map<String, Object?> json) {
    final body = json.containsKey('format')
        ? format.open(json, refuse: MaterialFormatException.new)
        : json;
    final id = switch (body['id']) {
      final String said when _idShape.hasMatch(said) => said,
      final other => throw MaterialFormatException(
        '"id" must be "<namespace>.<name>", not $other',
      ),
    };
    final phase = switch (body['phase']) {
      final String said when said.isNotEmpty => MaterialPhase.named(said),
      final other => throw MaterialFormatException(
        'material "$id": "phase" must be a word, not $other',
      ),
    };
    double quoted(String key, double fallback) => switch (body[key]) {
      null => fallback,
      final num value when value.isFinite && value > 0 => value.toDouble(),
      final other => throw MaterialFormatException(
        'material "$id": "$key" must be a positive number, not $other',
      ),
    };
    T? group<T>(String key, T Function(Map<String, Object?>) read) =>
        switch (body[key]) {
          null => null,
          final Map<String, Object?> map => _within(id, () => read(map)),
          final other => throw MaterialFormatException(
            'material "$id": "$key" must be an object, not $other',
          ),
        };
    return PhysicalMaterial(
      id: id,
      name: switch (body['name']) {
        final String said => said,
        null => id.substring(id.lastIndexOf('.') + 1),
        final other => throw MaterialFormatException(
          'material "$id": "name" must be a string, not $other',
        ),
      },
      phase: phase,
      temperature: quoted('temperature', standardAirTemperature),
      pressure: quoted('pressure', standardAtmosphere),
      mechanical: group('mechanical', MechanicalProperties.fromJson),
      fluid: group('fluid', FluidProperties.fromJson),
      thermal: group('thermal', ThermalProperties.fromJson),
      acoustic: group('acoustic', AcousticProperties.fromJson),
      optical: group('optical', OpticalProperties.fromJson),
      electrical: group('electrical', ElectricalProperties.fromJson),
      inelastic: group('inelastic', InelasticProperties.fromJson),
      externalIds: switch (body['externalIds']) {
        null => const <String, String>{},
        final Map<String, Object?> ids
            when ids.values.every((v) => v is String && v.isNotEmpty) =>
          Map<String, String>.unmodifiable(ids.cast<String, String>()),
        final other => throw MaterialFormatException(
          'material "$id": "externalIds" must map a space to an id, not '
          '$other',
        ),
      },
      confidence: switch (body['confidence']) {
        null => null,
        final String name when name.isNotEmpty => Confidence.named(name),
        final other => throw MaterialFormatException(
          'material "$id": "confidence" must be a word, not $other',
        ),
      },
      unknown: <String, Object?>{
        for (final MapEntry(:key, :value) in body.entries)
          if (!_knownKeys.contains(key) &&
              !FormatSpec.envelopeKeys.contains(key))
            key: value,
      },
    );
  }

  /// The material as a document: `f3d.physicalMaterial`, version 2.
  ///
  /// Version 2 lets a property be a law (`PropertyLaw.toJson`) where
  /// version 1 had a number, and adds `inelastic`, `externalIds` and
  /// `confidence`; a version 1 document reads as it always did, each number
  /// a constant law.
  static const FormatSpec format = FormatSpec(
    id: 'f3d.physicalMaterial',
    version: formatVersion,
    suffixes: <String>['.material.json'],
    fixture: 'test/fixtures/v<N>/water.material.json',
  );

  /// The version [toJson] writes and the newest [PhysicalMaterial.fromJson]
  /// reads.
  static const int formatVersion = 2;

  /// `f3d.<name>` for the engine's, `<pluginId>.<name>` for a plugin's.
  final String id;

  /// What a person calls it.
  final String name;

  /// The state it is in at [temperature] and [pressure]: a solid, a liquid,
  /// a gas, grains, or a phase a plugin names.
  final MaterialPhase phase;

  /// The temperature its numbers are quoted at, K: 20 °C unless the entry
  /// says otherwise — molten rock's are at its eruption, ice's at its
  /// melting point.
  final double temperature;

  /// The pressure its numbers are quoted at, Pa: one standard atmosphere
  /// unless the entry says otherwise.
  final double pressure;

  /// Its density, stiffness and contact with itself; null when unknown.
  final MechanicalProperties? mechanical;

  /// How it flows, for a liquid or a gas; null when unknown or solid.
  final FluidProperties? fluid;

  /// How it takes heat, changes phase and burns; null when unknown.
  final ThermalProperties? thermal;

  /// What a surface of it absorbs of sound and how fast sound crosses it;
  /// null when unknown.
  final AcousticProperties? acoustic;

  /// What it bends, absorbs and reflects of light; null when unknown.
  final OpticalProperties? optical;

  /// How it carries a current; null when unknown.
  final ElectricalProperties? electrical;

  /// How it loses energy as it bends, creeps and flows; null when unknown.
  final InelasticProperties? inelastic;

  /// The ids other systems know it by, by the space they are in:
  /// [ExternalIdSpace.cas] `7732-18-5`, [ExternalIdSpace.ifc] `concrete`,
  /// [ExternalIdSpace.materialX] a library's material name. What
  /// `MaterialCatalog.byExternal` looks it up by, and what a converter binds
  /// an imported model's materials with.
  final Map<String, String> externalIds;

  /// How the entry as a whole was come by, where its values do not each
  /// say ([PropertyLaw.confidence]): what a value with none of its own is
  /// taken to have. Null when nothing is said.
  final Confidence? confidence;

  /// The keys of its document this build did not read — a group a later
  /// version added — kept so they are written back.
  final Map<String, Object?> unknown;

  /// The top-level keys [PhysicalMaterial.fromJson] reads.
  static const Set<String> _knownKeys = <String>{
    'id',
    'name',
    'phase',
    'temperature',
    'pressure',
    'mechanical',
    'fluid',
    'thermal',
    'acoustic',
    'optical',
    'electrical',
    'inelastic',
    'externalIds',
    'confidence',
  };

  static final RegExp _idShape = RegExp(
    // A plugin's id — lower case, digits, `_`, `.` and `-` — then a name.
    r'^[a-z][a-z0-9_.\-]*\.[a-z][A-Za-z0-9_]*$',
  );

  /// Its density at its reference state, kg/m³: [mechanical]'s, or null.
  double? get density => mechanical?.density?.value;

  /// The state its numbers are quoted at: its [temperature] and [pressure],
  /// in its [phase]. Every law of the entry gives its value there.
  MatterState get referenceState => MatterState.at(
    temperature: temperature,
    pressure: pressure,
    phase: phase,
  );

  /// Every group it has, in the order a document writes them.
  List<PropertyGroup> get groups => <PropertyGroup>[
    ?mechanical,
    ?fluid,
    ?thermal,
    ?acoustic,
    ?optical,
    ?electrical,
    ?inelastic,
  ];

  /// The confidence of [law] of this entry: its own, or the entry's.
  Confidence? confidenceOf(PropertyLaw law) => law.confidence ?? confidence;

  /// The plugin that declares it: the id's part before its last dot —
  /// `f3d` for the engine's own.
  String get namespace {
    final dot = id.lastIndexOf('.');
    return dot <= 0 ? id : id.substring(0, dot);
  }

  /// The entry's fields without the envelope: what a data plugin's
  /// `physicalMaterials` list holds, and what [toJson] puts after the envelope.
  Map<String, Object?> toBody() => <String, Object?>{
    'id': id,
    'name': name,
    'phase': phase.name,
    'temperature': temperature,
    'pressure': pressure,
    'mechanical': ?mechanical?.toJson(),
    'fluid': ?fluid?.toJson(),
    'thermal': ?thermal?.toJson(),
    'acoustic': ?acoustic?.toJson(),
    'optical': ?optical?.toJson(),
    'electrical': ?electrical?.toJson(),
    'inelastic': ?inelastic?.toJson(),
    if (externalIds.isNotEmpty) 'externalIds': externalIds,
    'confidence': ?confidence?.name,
    for (final MapEntry(:key, :value) in unknown.entries)
      if (!_knownKeys.contains(key)) key: value,
  };

  /// The entry as a document of its own, in the envelope.
  Map<String, Object?> toJson() => <String, Object?>{
    ...format.envelope(),
    ...toBody(),
  };

  static T _within<T>(String id, T Function() read) {
    try {
      return read();
    } on MaterialFormatException catch (e, stackTrace) {
      Error.throwWithStackTrace(
        MaterialFormatException('material "$id": ${e.message}'),
        stackTrace,
      );
    }
  }

  /// What is implausible about this entry, one sentence each; empty when
  /// nothing is.
  ///
  /// **SI ranges, wide enough for anything real** — a density from a gas's
  /// to osmium's, a viscosity from hydrogen's to pitch's — so a number in
  /// the wrong unit (grams per cubic centimetre, centipoise, °C) is caught
  /// and a real substance is not. A source per group is required, and read
  /// already; a liquid or a gas must say its density and viscosity, which
  /// everything that flows it reads. What a data plugin's materials and the
  /// conformance suite hold every entry to.
  List<String> problems() {
    final found = <String>[];
    void range(String what, double? value, double low, double high) {
      if (value == null) return;
      if (!(value >= low && value <= high)) {
        found.add('$id: $what $value is outside $low…$high');
      }
    }

    for (final group in groups) {
      if (group.source.trim().isEmpty) {
        found.add('$id: its ${group.name} group names no source');
      }
    }
    range('temperature, K', temperature, 1.0, 1e4);
    range('pressure, Pa', pressure, 1e-3, 1e10);
    final m = mechanical;
    if (m != null) {
      range('density, kg/m³', m.density?.value, 1e-3, 3e4);
      range("Young's modulus, Pa", m.youngsModulus?.value, 1e3, 1.5e12);
      range("Poisson's ratio", m.poissonRatio?.value, -1.0, 0.5);
      range('yield strength, Pa', m.yieldStrength?.value, 1e3, 1e11);
      range('tensile strength, Pa', m.tensileStrength?.value, 1e3, 1e11);
      range('hardness, Pa', m.hardness?.value, 1e3, 2e11);
      range('static friction', m.staticFriction?.value, 0.0, 5.0);
      range('kinetic friction', m.kineticFriction?.value, 0.0, 5.0);
      range('restitution', m.restitution?.value, 0.0, 1.0);
      range('rolling resistance', m.rollingResistance?.value, 0.0, 1.0);
    }
    final f = fluid;
    if (f != null) {
      range('viscosity, Pa·s', f.viscosity?.value, 1e-7, 1e12);
      // Down to a cryogenic liquid's: liquid helium pulls with 0.1 mN/m.
      range('surface tension, N/m', f.surfaceTension?.value, 1e-5, 3.0);
      range('bulk modulus, Pa', f.bulkModulus?.value, 1e3, 1e12);
    }
    if (phase.isFluid) {
      if (m?.density == null) found.add('$id: a ${phase.name} with no density');
      if (f?.viscosity == null) {
        found.add('$id: a ${phase.name} with no viscosity');
      }
    }
    final t = thermal;
    if (t != null) {
      range('specific heat, J/(kg·K)', t.specificHeat?.value, 50.0, 2e4);
      range('conductivity, W/(m·K)', t.conductivity?.value, 1e-3, 3000.0);
      // Up to a cryogenic liquid's: liquid helium grows by 7 % a kelvin.
      range(
        'volumetric expansion, 1/K',
        t.volumetricExpansion?.value,
        -1e-3,
        0.1,
      );
      range('melting point, K', t.meltingPoint?.value, 1.0, 5000.0);
      range('boiling point, K', t.boilingPoint?.value, 1.0, 7000.0);
      range(
        'latent heat of fusion, J/kg',
        t.latentHeatOfFusion?.value,
        1e3,
        1e7,
      );
      range(
        'latent heat of vaporization, J/kg',
        t.latentHeatOfVaporization?.value,
        1e4,
        5e7,
      );
      range('emissivity', t.emissivity?.value, 0.0, 1.0);
      range(
        'ignition temperature, K',
        t.ignitionTemperature?.value,
        300.0,
        2000.0,
      );
      range(
        'autoignition temperature, K',
        t.autoignitionTemperature?.value,
        300.0,
        2000.0,
      );
      range('glow temperature, K', t.glowTemperature?.value, 300.0, 2000.0);
      range('heat of combustion, J/kg', t.heatOfCombustion?.value, 1e5, 1.5e8);
      range(
        'effective heat of combustion, J/kg',
        t.effectiveHeatOfCombustion?.value,
        1e5,
        1.5e8,
      );
      final gross = t.heatOfCombustion?.value;
      final effective = t.effectiveHeatOfCombustion?.value;
      if (gross != null && effective != null && effective > gross) {
        found.add(
          '$id: an effective heat of combustion of $effective J/kg is more '
          'than the whole $gross',
        );
      }
      range('radiant fraction', t.radiantFraction?.value, 0.0, 1.0);
      final melts = t.meltingPoint?.value, boils = t.boilingPoint?.value;
      if (melts != null && boils != null && boils <= melts) {
        found.add('$id: boils at $boils K, not above its melting $melts K');
      }
    }
    final a = acoustic;
    if (a != null) {
      for (final share in a.absorption ?? const <double>[]) {
        range('absorption', share, 0.0, 1.0);
      }
      range('speed of sound, m/s', a.speedOfSound?.value, 1.0, 2e4);
      range('impedance, Pa·s/m', a.impedance?.value, 1.0, 1e9);
    }
    final o = optical;
    if (o != null) {
      range('refractive index', o.refractiveIndex?.value, 1.0, 5.0);
      range('Abbe number', o.abbeNumber?.value, 5.0, 150.0);
      range('dielectric F0', o.dielectricF0?.value, 0.0, 1.0);
      for (final c in <double?>[
        o.absorption?.red,
        o.absorption?.green,
        o.absorption?.blue,
      ]) {
        range('absorption, 1/m', c, 0.0, 1e9);
      }
      for (final c in <double?>[
        o.metalReflectance?.red,
        o.metalReflectance?.green,
        o.metalReflectance?.blue,
      ]) {
        range('metal reflectance', c, 0.0, 1.0);
      }
      range('roughness', o.roughnessMin?.value, 0.0, 1.0);
      range('roughness', o.roughnessMax?.value, 0.0, 1.0);
    }
    range('resistivity, Ω·m', electrical?.resistivity?.value, 1e-9, 1e25);
    range('loss factor', inelastic?.lossFactor?.value, 0.0, 2.0);
    for (final group in groups) {
      for (final MapEntry(key: name, value: law) in group.laws.entries) {
        if (law is TableLaw) {
          for (final problem in law.problems()) {
            found.add('$id: ${group.name}.$name: $problem');
          }
        }
      }
    }
    return found;
  }

  @override
  String toString() => 'PhysicalMaterial($id)';
}
