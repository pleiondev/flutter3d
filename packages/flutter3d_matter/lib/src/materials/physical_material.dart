/// What a substance is, physically: one entry of the material catalogue.
library;

import 'package:flutter3d_foundation/flutter3d_foundation.dart' show FormatSpec;

import '../standard_world.dart';
import 'material_json.dart';
import 'property_groups.dart';

/// What state a material is in at its quoted temperature and pressure.
///
/// **A class of constants rather than an enum**, so a plugin's material in a
/// state of its own — a plasma, a foam — names one with [MaterialPhase.named]
/// and breaks no switch written against these.
final class MaterialPhase {
  /// A phase of a plugin's own, by its [name].
  const MaterialPhase.named(this.name);

  static const MaterialPhase solid = MaterialPhase.named('solid');
  static const MaterialPhase liquid = MaterialPhase.named('liquid');
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
    this.unknown = const <String, Object?>{},
  });

  /// The material as a document: `f3d.physicalMaterial`, version 1.
  static const FormatSpec format = FormatSpec(
    id: 'f3d.physicalMaterial',
    version: formatVersion,
    suffixes: <String>['.material.json'],
    fixture: 'test/fixtures/v<N>/water.material.json',
  );

  /// The version [toJson] writes and the newest [PhysicalMaterial.fromJson]
  /// reads.
  static const int formatVersion = 1;

  /// `f3d.<name>` for the engine's, `<pluginId>.<name>` for a plugin's.
  final String id;

  /// What a person calls it.
  final String name;

  final MaterialPhase phase;

  /// The temperature its numbers are quoted at, K: 20 °C unless the entry
  /// says otherwise — molten rock's are at its eruption, ice's at its
  /// melting point.
  final double temperature;

  /// The pressure its numbers are quoted at, Pa: one standard atmosphere
  /// unless the entry says otherwise.
  final double pressure;

  final MechanicalProperties? mechanical;
  final FluidProperties? fluid;
  final ThermalProperties? thermal;
  final AcousticProperties? acoustic;
  final OpticalProperties? optical;
  final ElectricalProperties? electrical;

  /// The keys of its document this build did not read — a group a later
  /// version added — kept so they are written back.
  final Map<String, Object?> unknown;

  /// Its density, kg/m³: [mechanical]'s, or null.
  double? get density => mechanical?.density;

  /// The plugin that declares it: the id's part before its last dot —
  /// `f3d` for the engine's own.
  String get namespace {
    final dot = id.lastIndexOf('.');
    return dot <= 0 ? id : id.substring(0, dot);
  }

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
  };

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
    for (final MapEntry(:key, :value) in unknown.entries)
      if (!_knownKeys.contains(key)) key: value,
  };

  /// The entry as a document of its own, in the envelope.
  Map<String, Object?> toJson() => <String, Object?>{
    ...format.envelope(),
    ...toBody(),
  };

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
      unknown: <String, Object?>{
        for (final MapEntry(:key, :value) in body.entries)
          if (!_knownKeys.contains(key) &&
              !FormatSpec.envelopeKeys.contains(key))
            key: value,
      },
    );
  }

  static T _within<T>(String id, T Function() read) {
    try {
      return read();
    } on MaterialFormatException catch (e) {
      throw MaterialFormatException('material "$id": ${e.message}');
    }
  }

  static final RegExp _idShape = RegExp(
    // A plugin's id — lower case, digits, `_`, `.` and `-` — then a name.
    r'^[a-z][a-z0-9_.\-]*\.[a-z][A-Za-z0-9_]*$',
  );

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

    for (final (name, group) in <(String, PropertyGroup?)>[
      ('mechanical', mechanical),
      ('fluid', fluid),
      ('thermal', thermal),
      ('acoustic', acoustic),
      ('optical', optical),
      ('electrical', electrical),
    ]) {
      if (group != null && group.source.trim().isEmpty) {
        found.add('$id: its $name group names no source');
      }
    }
    range('temperature, K', temperature, 1.0, 1e4);
    range('pressure, Pa', pressure, 1e-3, 1e10);
    final m = mechanical;
    if (m != null) {
      range('density, kg/m³', m.density, 1e-3, 3e4);
      range("Young's modulus, Pa", m.youngsModulus, 1e3, 1.5e12);
      range("Poisson's ratio", m.poissonRatio, -1.0, 0.5);
      range('yield strength, Pa', m.yieldStrength, 1e3, 1e11);
      range('tensile strength, Pa', m.tensileStrength, 1e3, 1e11);
      range('hardness, Pa', m.hardness, 1e3, 2e11);
      range('static friction', m.staticFriction, 0.0, 5.0);
      range('kinetic friction', m.kineticFriction, 0.0, 5.0);
      range('restitution', m.restitution, 0.0, 1.0);
      range('rolling resistance', m.rollingResistance, 0.0, 1.0);
    }
    final f = fluid;
    if (f != null) {
      range('viscosity, Pa·s', f.viscosity, 1e-7, 1e12);
      range('surface tension, N/m', f.surfaceTension, 1e-4, 3.0);
      range('bulk modulus, Pa', f.bulkModulus, 1e3, 1e12);
    }
    if (phase.isFluid) {
      if (m?.density == null) found.add('$id: a ${phase.name} with no density');
      if (f?.viscosity == null) {
        found.add('$id: a ${phase.name} with no viscosity');
      }
    }
    final t = thermal;
    if (t != null) {
      range('specific heat, J/(kg·K)', t.specificHeat, 50.0, 2e4);
      range('conductivity, W/(m·K)', t.conductivity, 1e-3, 3000.0);
      range('volumetric expansion, 1/K', t.volumetricExpansion, -1e-3, 1e-2);
      range('melting point, K', t.meltingPoint, 1.0, 5000.0);
      range('boiling point, K', t.boilingPoint, 1.0, 7000.0);
      range('latent heat of fusion, J/kg', t.latentHeatOfFusion, 1e3, 1e7);
      range(
        'latent heat of vaporization, J/kg',
        t.latentHeatOfVaporization,
        1e4,
        5e7,
      );
      range('emissivity', t.emissivity, 0.0, 1.0);
      range('ignition temperature, K', t.ignitionTemperature, 300.0, 2000.0);
      range(
        'autoignition temperature, K',
        t.autoignitionTemperature,
        300.0,
        2000.0,
      );
      range('heat of combustion, J/kg', t.heatOfCombustion, 1e5, 1.5e8);
      range('radiant fraction', t.radiantFraction, 0.0, 1.0);
      final melts = t.meltingPoint, boils = t.boilingPoint;
      if (melts != null && boils != null && boils <= melts) {
        found.add('$id: boils at $boils K, not above its melting $melts K');
      }
    }
    final a = acoustic;
    if (a != null) {
      for (final share in a.absorption ?? const <double>[]) {
        range('absorption', share, 0.0, 1.0);
      }
      range('speed of sound, m/s', a.speedOfSound, 1.0, 2e4);
      range('impedance, Pa·s/m', a.impedance, 1.0, 1e9);
    }
    final o = optical;
    if (o != null) {
      range('refractive index', o.refractiveIndex, 1.0, 5.0);
      range('Abbe number', o.abbeNumber, 5.0, 150.0);
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
      range('roughness', o.roughnessMin, 0.0, 1.0);
      range('roughness', o.roughnessMax, 0.0, 1.0);
    }
    range('resistivity, Ω·m', electrical?.resistivity, 1e-9, 1e25);
    return found;
  }

  @override
  String toString() => 'PhysicalMaterial($id)';
}
