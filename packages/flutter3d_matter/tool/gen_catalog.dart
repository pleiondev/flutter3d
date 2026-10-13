/// Writes the engine's material catalogue from its data.
///
///     dart run tool/gen_catalog.dart          # write it
///     dart run tool/gen_catalog.dart --check  # exit 1 if it is out of date
///
/// **The data is the one place a number is written.** Three files under
/// `tool/data/sources/` hold it:
///
/// * `catalog_base.json`, the 33 entries the catalogue had before the
///   verified data, with their sources: their values at the reference state
///   stay as they were, because the C core's header and every recorded run
///   are made of them;
/// * `fluids.json` and `solids.json`, about 120 fluids and 120 solids, every
///   value with its source, its confidence and, where one was found, its law
///   in temperature (`SCHEMA.txt`).
///
/// It writes `lib/src/materials/materials.g.dart`, the `Materials` class,
/// and `tool/data/catalog.verified.json`, the same numbers as data, which
/// `test/catalog_verified_test.dart` holds the Dart to.
///
/// **How a value becomes a law.** A table in temperature becomes a
/// `TableLaw` with the value quoted at the reference state as one of its
/// points; a closed form (Andrade, Arrhenius, Vogel–Fulcher–Tammann, a
/// polynomial, a linear or exponential coefficient) becomes a `FormulaLaw`
/// anchored on that value, `value · (shape(T) / shape(T₀))`, so the law
/// gives the quoted value at the reference state to the bit. A law whose
/// shape is more than [_lawTolerance] off the quoted value there, or that is
/// in another variable (salinity, density, speed), is left out and the value
/// is a constant; the verified file says why.
///
/// **Friction for every solid.** A solid whose self-friction no source gave
/// takes an estimate, marked so, whose source says what it is: the median
/// of its family's measured self-pairs in this catalogue, a rule from the
/// literature for rock and grains, or the engine's default.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter3d_matter/flutter3d_matter.dart';

/// Where the Dart goes, from the package root.
const String dartPath = 'lib/src/materials/materials.g.dart';

/// Where the verified data goes, from the package root.
const String verifiedPath = 'tool/data/catalog.verified.json';

/// How far a law's shape may be off the quoted value at the reference state
/// before the law is left out: 10 %. A law kept within it is scaled onto the
/// quoted value, and its source says by how much.
const double _lawTolerance = 0.10;

/// How close the research's number and a base entry's must be to count as
/// the same number: half a percent, the last figure of a handbook's three
/// or four rounded either way (998.2 and 998 kg/m³ are one density; 0.0728
/// and 0.072 N/m are one surface tension). Closer, the research's confidence
/// and law are the base entry's; further, the base entry keeps its own
/// number, which every recorded run and the C core's header are made of.
const double _agreement = 0.005;

/// What a base entry's group holds beside its values.
/// `sourceOf` and `intervalOf` give a value its own source and spread where
/// they are not the group's.
const Set<String> _baseKeys = <String>{
  'source',
  'confidence',
  'confidenceOf',
  'sourceOf',
  'intervalOf',
};

const Map<String, List<String>> _groupProperties = <String, List<String>>{
  'mechanical': <String>[
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
  ],
  'fluid': <String>['viscosity', 'surfaceTension', 'bulkModulus'],
  'thermal': <String>[
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
  ],
  'acoustic': <String>['absorption', 'speedOfSound', 'impedance'],
  'optical': <String>[
    'refractiveIndex',
    'abbeNumber',
    'dielectricF0',
    'absorption',
    'metalReflectance',
    'roughnessMin',
    'roughnessMax',
  ],
  'electrical': <String>['resistivity'],
  'inelastic': <String>['lossFactor'],
};

const Map<String, String> _groupClass = <String, String>{
  'mechanical': 'MechanicalProperties',
  'fluid': 'FluidProperties',
  'thermal': 'ThermalProperties',
  'acoustic': 'AcousticProperties',
  'optical': 'OpticalProperties',
  'electrical': 'ElectricalProperties',
  'inelastic': 'InelasticProperties',
};

/// The list-valued properties, which stay lists at the reference state.
const Set<String> _lists = <String>{
  'acoustic.absorption',
  'optical.absorption',
  'optical.metalReflectance',
};

/// The external id spaces of the data, by the catalogue's name.
const Map<String, String> _spaces = <String, String>{
  'CAS': ExternalIdSpace.cas,
  'IFC4.Category': ExternalIdSpace.ifc,
  'MaterialX': ExternalIdSpace.materialX,
  'UNS': ExternalIdSpace.uns,
  'ISO1043': ExternalIdSpace.iso1043,
  'EN': ExternalIdSpace.en,
  'physicallybased.info': ExternalIdSpace.physicallyBased,
  'SCHOTT': 'SCHOTT',
  'ASTM': 'ASTM',
};

/// The families a solid's estimated self-friction is taken from.
const Map<String, List<String>> _families = <String, List<String>>{
  'metals': <String>[
    'iron', 'steel', 'aluminum', 'copper', 'gold', 'silver', 'lead', //
    'nickel', 'zinc', 'tin', 'titanium', 'tungsten', 'magnesium',
    'platinum', 'chromium', 'molybdenum', 'stainlessSteel304',
    'stainlessSteel316', 'castIron', 'titaniumTi6Al4V', 'aluminum6061T6',
    'aluminum7075T6', 'aluminum2024T3', 'brass', 'phosphorBronze',
    'aluminumBronze', 'constantan', 'nichrome', 'inconelX750', 'steel4340',
  ],
  'glasses and ceramics': <String>[
    'glass', 'borosilicateGlass', 'fusedSilica', 'crownGlassBK7', //
    'flintGlassF2', 'alumina', 'sapphire', 'porcelain', 'siliconCarbide',
    'diamond', 'graphite', 'quartz', 'glassCeramic', 'silicon',
    'siliconNitride', 'mica',
  ],
  'plastics': <String>[
    'polyethylene', 'polyethyleneLD', 'polypropylene', 'pvc', 'abs', //
    'pmma', 'polycarbonate', 'polystyrene', 'nylon66', 'ptfe', 'pet', 'pom',
    'epoxy', 'peek', 'bakelite', 'linoleum', 'carbonFiberComposite',
    'fiberglassComposite',
  ],
  'rubbers': <String>[
    'rubber', 'naturalRubber', 'siliconeRubber', 'neoprene', //
    'butylRubber', 'polybutadieneRubber',
  ],
  'woods': <String>[
    'oak', 'pine', 'pineEasternWhite', 'birch', 'maple', 'douglasFir', //
    'spruce', 'balsa', 'wood', 'hardwoodGeneric', 'softwoodGeneric',
    'hardboard', 'particleboard', 'cork', 'sawdust',
  ],
};

/// Rock on rock, and the rocks a building is made of.
const List<String> _rocks = <String>[
  'concrete', 'lightweightConcrete', 'brick', 'granite', 'basalt', //
  'sandstone', 'limestone', 'marble', 'slate', 'quartzite', 'cementMortar',
  'rockSalt', 'gypsumBoard', 'plaster',
];

/// Grains: a bed's friction is its internal friction.
const List<String> _grains = <String>[
  'sand', 'soil', 'soilDry', 'soilWet', 'clayDry', 'clayWet', //
];

/// The thermal group the data has none for: molten basalt's, so heat and
/// fire can read the lava they are given.
const Map<String, Object?> _basaltMeltThermal = <String, Object?>{
  'specificHeat': <String, Object?>{
    'value': 1480.0,
    'confidence': 'estimate',
    'interval': <double>[1200.0, 1600.0],
    'source':
        'a basaltic liquid\'s isobaric heat capacity, 1.2 to 1.6 kJ/(kg·K) '
        'across silicate melts (Lesher and Spera, "Thermodynamic and '
        'transport properties of silicate melts and magma", The Encyclopedia '
        'of Volcanoes, 2nd ed., 2015): an estimate inside that span, recalled '
        'and not re-read',
  },
  'conductivity': <String, Object?>{
    'value': 1.5,
    'confidence': 'estimate',
    'interval': <double>[1.0, 2.0],
    'source':
        'a silicate melt\'s thermal conductivity, about 1 to 2 W/(m·K) (Lesher '
        'and Spera, 2015): an estimate, recalled and not re-read; dense solid '
        'basalt\'s is 1.8 in this catalogue (f3d.basalt)',
  },
  'meltingPoint': <String, Object?>{
    'value': 1450.0,
    'confidence': 'estimate',
    'interval': <double>[1250.0, 1500.0],
    'source':
        'where it sets: solid basalt\'s melting range in this catalogue '
        '(f3d.basalt), 1250 to 1500 K, the value the engine\'s lava uses',
  },
  'latentHeatOfFusion': <String, Object?>{
    'value': 4.0e5,
    'confidence': 'estimate',
    'interval': <double>[3.5e5, 5.0e5],
    'source':
        'a basalt\'s heat of fusion, 350 to 500 kJ/kg as lava-flow models take '
        'it (Lesher and Spera, 2015): an estimate, recalled and not re-read',
  },
  'emissivity': <String, Object?>{
    'value': 0.9,
    'confidence': 'estimate',
    'interval': <double>[0.7, 0.95],
    'source':
        'an estimate for a molten basalt surface, between solid basalt\'s '
        '0.72 at room temperature in this catalogue and a black body; not a '
        'measurement',
  },
  'source':
      'estimates for a basaltic melt near 1200 °C, each with its own source; '
      'none is a measurement of this melt',
};

void main(List<String> args) {
  final root = File.fromUri(Platform.script).parent.parent.path;
  final catalogue = _Catalogue.read('$root/tool/data/sources');
  final dart = catalogue.dart();
  final verified =
      '${const JsonEncoder.withIndent('  ').convert(catalogue.verified())}\n';
  final dartFile = File('$root/$dartPath');
  final verifiedFile = File('$root/$verifiedPath');
  final readmeFile = File('$root/README.md');
  final readme = catalogue.readme(readmeFile.readAsStringSync());
  final scratch = Directory.systemTemp.createTempSync('gen_catalog');
  try {
    final formatted = File('${scratch.path}/materials.g.dart')
      ..writeAsStringSync(dart);
    // At the language version of this package's SDK floor, as the
    // repository's format check formats it; the SDK's own newer version
    // splits long strings differently.
    final floor = RegExp(
      r'sdk:\s*"?>=?\^?(\d+\.\d+)',
    ).firstMatch(File('$root/pubspec.yaml').readAsStringSync())!;
    final format = Process.runSync('dart', <String>[
      'format',
      '--language-version=${floor.group(1)}',
      formatted.path,
    ]);
    if (format.exitCode != 0) {
      stderr.writeln(format.stderr);
      exitCode = 1;
      return;
    }
    final text = formatted.readAsStringSync();
    if (args.contains('--check')) {
      String now(File file) => file.existsSync()
          ? file.readAsStringSync().replaceAll('\r\n', '\n')
          : '';
      if (now(dartFile) != text ||
          now(verifiedFile) != verified ||
          now(readmeFile) != readme) {
        stderr.writeln(
          '$dartPath or $verifiedPath is out of date: run `dart run '
          'tool/gen_catalog.dart` in flutter3d_matter',
        );
        exitCode = 1;
      }
      return;
    }
    dartFile.writeAsStringSync(text);
    verifiedFile.writeAsStringSync(verified);
    readmeFile.writeAsStringSync(readme);
    stdout.writeln(
      '${catalogue.entries.length} materials, '
      '${catalogue.pairs.length} pairs, ${catalogue.dropped.length} laws '
      'left out',
    );
  } finally {
    scratch.deleteSync(recursive: true);
  }
}

/// One value of an entry as the generator holds it.
final class _Value {
  _Value(
    this.value, {
    this.confidence,
    this.source,
    this.interval,
    this.verification,
  });

  /// A double, or a list of them.
  Object value;
  String? confidence;
  String? source;
  List<double>? interval;
  String? verification;

  /// The research's record of the value, whose law [_law] reads: kept so
  /// a law can be anchored again on a verified value.
  Map<String, Object?>? lawSpec;

  /// The law's Dart, once made: `ConstantLaw(…)`, `TableLaw(…)`, ….
  String? lawDart;
  String lawKind = 'constant';

  /// What was done to the law to make it give the quoted value at the
  /// reference state, for its source; null when nothing was.
  String? anchor;
}

/// One entry as the generator holds it.
final class _Entry {
  _Entry(this.id, this.name, this.phase);

  final String id;
  final String name;
  final String phase;
  double temperature = standardAirTemperature;
  double pressure = standardAtmosphere;
  String? description;
  final Map<String, String> externalIds = <String, String>{};
  final Map<String, Map<String, _Value>> groups =
      <String, Map<String, _Value>>{};
  final Map<String, String> groupSources = <String, String>{};
  final Map<String, Map<String, Object?>> models =
      <String, Map<String, Object?>>{};
  String? confidence;

  /// Whether it is one of the 33 the catalogue had before.
  bool base = false;

  /// For a base entry, each group's values' confidence as its data says it,
  /// by property.
  final Map<String, Map<String, String>> baseConfidences =
      <String, Map<String, String>>{};

  String get field => id.substring('f3d.'.length);
}

final class _Catalogue {
  _Catalogue(this.entries, this.pairs, this.dropped);

  factory _Catalogue.read(String dir) {
    Map<String, Object?> json(String name) =>
        jsonDecode(File('$dir/$name').readAsStringSync())
            as Map<String, Object?>;
    final base = json('catalog_base.json');
    final fluids = json('fluids.json');
    final solids = json('solids.json');
    final entries = <String, _Entry>{};
    final dropped = <String, String>{};

    for (final body
        in (base['materials']! as List).cast<Map<String, Object?>>()) {
      final entry =
          _Entry(
              body['id']! as String,
              body['name']! as String,
              body['phase']! as String,
            )
            ..base = true
            ..temperature = (body['temperature']! as num).toDouble()
            ..pressure = (body['pressure']! as num).toDouble();
      for (final group in _groupProperties.keys) {
        final g = body[group] as Map<String, Object?>?;
        if (g == null) continue;
        entry.groupSources[group] = g['source']! as String;
        // How the group's values were come by, as the data says: the
        // group's word, and a word of a value's own where it differs.
        final said = switch (g['confidence']) {
          final String word when Confidence.values.any((c) => c.name == word) =>
            word,
          final other => throw StateError(
            '${entry.id} $group: the base data names a confidence '
            '(measured, handbook or estimate), not $other',
          ),
        };
        final own = (g['confidenceOf'] as Map<String, Object?>?) ?? const {};
        entry.baseConfidences[group] = <String, String>{
          for (final key in g.keys)
            if (!_baseKeys.contains(key)) key: (own[key] as String?) ?? said,
        };
        final values = entry.groups.putIfAbsent(
          group,
          () => <String, _Value>{},
        );
        final sourceOf = (g['sourceOf'] as Map<String, Object?>?) ?? const {};
        final intervalOf =
            (g['intervalOf'] as Map<String, Object?>?) ?? const {};
        for (final MapEntry(:key, :value) in g.entries) {
          if (_baseKeys.contains(key) || value == null) continue;
          values[key] = _Value(
            value is num
                ? value.toDouble()
                : <double>[
                    for (final n in value as List) (n as num).toDouble(),
                  ],
            source: sourceOf[key] as String?,
            interval: switch (intervalOf[key]) {
              [final num low, final num high] => <double>[
                low.toDouble(),
                high.toDouble(),
              ],
              _ => null,
            },
          );
        }
      }
      entries[entry.id] = entry;
    }

    // A liquid metal shares its research id with the solid (`lead`): the
    // liquid is the melt, as `basaltMelt` is.
    final solidIds = <String>{
      for (final raw
          in (solids['entries']! as List).cast<Map<String, Object?>>())
        raw['id']! as String,
    };
    for (final data in <Map<String, Object?>>[fluids, solids]) {
      for (final raw
          in (data['entries']! as List).cast<Map<String, Object?>>()) {
        final melt = identical(data, fluids) && solidIds.contains(raw['id'])
            ? 'Melt'
            : '';
        final id = (raw['catalogId'] as String?) ?? 'f3d.${raw['id']}$melt';
        final entry = entries.putIfAbsent(
          id,
          () => _Entry(id, raw['name']! as String, raw['phase']! as String),
        );
        final reference = raw['referenceState']! as Map<String, Object?>;
        if (!entry.base) {
          entry
            ..temperature = (reference['temperature']! as num).toDouble()
            ..pressure = (reference['pressure']! as num).toDouble()
            ..description = raw['description'] as String?;
        }
        final ids =
            (raw['externalIds'] as Map<String, Object?>?) ??
            <String, Object?>{'CAS': raw['cas']};
        for (final MapEntry(:key, :value) in ids.entries) {
          if (value is String && value.isNotEmpty) {
            entry.externalIds[_spaces[key] ?? key] = value;
          }
        }
        final groups = raw['groups']! as Map<String, Object?>;
        for (final MapEntry(key: group, value: props) in groups.entries) {
          if (group == 'extra') continue;
          if (group == 'inelastic') {
            _inelastic(entry, props! as Map<String, Object?>);
            continue;
          }
          if (!_groupProperties.containsKey(group)) continue;
          for (final MapEntry(key: name, value: p)
              in (props! as Map<String, Object?>).entries) {
            if (p is! Map<String, Object?> || p['value'] == null) continue;
            if (!_groupProperties[group]!.contains(name)) continue;
            final values = entry.groups.putIfAbsent(
              group,
              () => <String, _Value>{},
            );
            final held = values[name];
            final research = _research(p);
            if (held == null) {
              values[name] = research;
              _law(entry, group, name, research, p, dropped);
            } else if (held.value is double &&
                research.value is double &&
                _close(
                  held.value as double,
                  research.value as double,
                  _agreement,
                )) {
              // The research agrees with the catalogue: its confidence and
              // its law, anchored on the catalogue's own number.
              final agreed = _Value(
                held.value,
                confidence: research.confidence,
                source: null,
                interval: research.interval,
                verification: research.verification,
              );
              values[name] = agreed;
              _law(entry, group, name, agreed, p, dropped);
            } else if (held.value is double) {
              // The catalogue's number stays; a law of another number's
              // shape is anchored on it only when they are close.
              if (research.value is double &&
                  _close(
                    held.value as double,
                    research.value as double,
                    _lawTolerance,
                  )) {
                _law(entry, group, name, held, p, dropped);
              } else {
                dropped['${entry.id} $group.$name'] =
                    'the catalogue keeps ${held.value}; the research has '
                    '${research.value}';
              }
            }
          }
        }
      }
    }

    // Molten basalt's heat.
    final basalt = entries['f3d.basaltMelt']!;
    final thermal = basalt.groups.putIfAbsent(
      'thermal',
      () => <String, _Value>{},
    );
    basalt.groupSources['thermal'] = _basaltMeltThermal['source']! as String;
    for (final MapEntry(:key, :value) in _basaltMeltThermal.entries) {
      if (value is! Map<String, Object?>) continue;
      thermal[key] = _Value(
        (value['value']! as num).toDouble(),
        confidence: value['confidence'] as String?,
        source: value['source'] as String?,
        interval: (value['interval'] as List?)?.cast<double>(),
      );
    }

    // The verification, over everything above: each value checked against
    // a source that was read.
    _verify(
      entries,
      json('verification.json'),
      json('verification_decisions.json'),
      solids,
      dropped,
    );

    // A liquid or a gas the data gives no density or viscosity for is left
    // out: everything that flows it reads both, and neither is invented.
    final list = <_Entry>[];
    for (final entry in entries.values) {
      final flows = entry.phase == 'liquid' || entry.phase == 'gas';
      final missing = <String>[
        if (entry.groups['mechanical']?['density'] == null) 'density',
        if (entry.groups['fluid']?['viscosity'] == null) 'viscosity',
      ];
      if (flows && missing.isNotEmpty) {
        dropped[entry.id] = 'left out: the data has no ${missing.join(' or ')}';
        continue;
      }
      list.add(entry);
    }
    _friction(list);
    for (final entry in list) {
      _finish(entry);
    }
    final pairs = _pairs(base, solids, entries);
    _restitution(
      pairs,
      json('restitution.json'),
      json('verification_decisions.json'),
      entries,
    );
    return _Catalogue(list, pairs, dropped);
  }

  final List<_Entry> entries;
  final List<Map<String, Object?>> pairs;
  final Map<String, String> dropped;

  static _Value _research(Map<String, Object?> p) {
    final raw = p['value']!;
    return _Value(
      raw is num
          ? raw.toDouble()
          : <double>[for (final n in raw as List) (n as num).toDouble()],
      confidence: p['confidence'] as String?,
      source: _sourceOf(p),
      interval: switch (p['range']) {
        [final num low, final num high] when low <= high => <double>[
          low.toDouble(),
          high.toDouble(),
        ],
        _ => null,
      },
      verification: p['verification'] as String?,
    );
  }

  static String? _sourceOf(Map<String, Object?> p) {
    final source = p['source'] as String?;
    if (source == null) return null;
    final note = p['note'] as String?;
    final url = p['sourceUrl'] as String?;
    return <String>[
      source,
      if (url != null && !source.contains(url)) url,
      if (note != null && note.isNotEmpty) note,
    ].join('; ');
  }

  static bool _close(double a, double b, double tolerance) =>
      a == b || (a - b).abs() <= tolerance * math.max(a.abs(), b.abs());

  static void _inelastic(_Entry entry, Map<String, Object?> props) {
    final damping = props['damping'] as Map<String, Object?>?;
    final loss = damping?['lossFactor'] as Map<String, Object?>?;
    if (loss != null && loss['value'] != null) {
      entry.groups.putIfAbsent(
        'inelastic',
        () => <String, _Value>{},
      )['lossFactor'] = _research(
        loss,
      );
      entry.groupSources['inelastic'] ??= loss['source']! as String;
    }
    for (final kind in <String>['hyperelastic', 'viscoelastic', 'plastic']) {
      final model = props[kind] as Map<String, Object?>?;
      if (model == null) continue;
      final name = model['model'] as String?;
      if (name == null) continue;
      String? source;
      String? confidence;
      final parameters = <String, double>{};
      final terms = <Map<String, double>>[];
      bool complete = true;
      void collect(Map<String, Object?> from, Map<String, double> into) {
        for (final MapEntry(:key, :value) in from.entries) {
          if (value is Map<String, Object?> && value.containsKey('value')) {
            final v = value['value'];
            if (v is num) {
              into[key] = v.toDouble();
              source ??= value['source'] as String?;
              confidence ??= value['confidence'] as String?;
            } else {
              complete = false;
            }
          } else if (value is num && key != 'model') {
            into[key] = value.toDouble();
          }
        }
      }

      collect(model, parameters);
      for (final term in (model['terms'] as List?) ?? const <Object?>[]) {
        final into = <String, double>{};
        collect(term! as Map<String, Object?>, into);
        terms.add(into);
      }
      if (!complete || (parameters.isEmpty && terms.isEmpty)) continue;
      entry.models[kind] = <String, Object?>{
        'model': name,
        'parameters': parameters,
        'terms': terms,
        'confidence': confidence,
        'source': source,
      };
      entry.groupSources['inelastic'] ??= source ?? 'see each model';
    }
  }

  /// The law of [value], from the research's [p], into [value.lawDart].
  static void _law(
    _Entry entry,
    String group,
    String name,
    _Value value,
    Map<String, Object?> p,
    Map<String, String> dropped,
  ) {
    if (value.value is! double) return;
    value.lawSpec = p;
    final laws = <Map<String, Object?>>[
      if (p['law'] case final Map<String, Object?> law) law,
      for (final law in (p['laws'] as List?) ?? const <Object?>[])
        law! as Map<String, Object?>,
    ];
    if (laws.isEmpty) return;
    final where = '${entry.id} $group.$name';
    final v = value.value as double;
    final reference = MatterState.at(
      temperature: entry.temperature,
      pressure: entry.pressure,
    );
    // A table where there is one: the measurements themselves.
    for (final law in laws) {
      final points = switch (law) {
        {'kind': 'table', 'points': final List points}
            when _inTemperature(law) =>
          points,
        {'tablePoints': final List points} => points,
        _ => null,
      };
      if (points == null) continue;
      final factor = '${law['valueIs'] ?? ''}'.contains('factor');
      final celsius = _celsius(law);
      final xs = <double>[], ys = <double>[];
      for (final point in points.cast<List>()) {
        xs.add((point[0] as num).toDouble() + (celsius ? zeroCelsius : 0.0));
        ys.add((point[1] as num).toDouble() * (factor ? v : 1.0));
      }
      final table = TableLaw(0, xs: xs, ys: ys);
      if (table.problems().isNotEmpty) {
        _drop(dropped, where, 'table: ${table.problems().join('; ')}');
        continue;
      }
      final shape = table.at(reference);
      if (!_close(shape, v, _lawTolerance)) {
        _drop(
          dropped,
          where,
          'table gives $shape at the reference state, quoted $v',
        );
        continue;
      }
      // The quoted value as a point of its own.
      final t = entry.temperature;
      final at = xs.indexWhere((x) => x >= t);
      if (at == -1) {
        xs.add(t);
        ys.add(v);
      } else if (xs[at] == t) {
        ys[at] = v;
      } else {
        xs.insert(at, t);
        ys.insert(at, v);
      }
      if (shape != v) {
        value.anchor =
            'the table alone gives ${_d(shape)} at the reference state; its '
            'point there is the quoted ${_d(v)}, ${_d(v / shape)} times it';
      }
      value
        ..lawKind = 'table'
        ..lawDart =
            'TableLaw(${_d(v)}, xs: <double>[${xs.map(_d).join(', ')}], '
            'ys: <double>[${ys.map(_d).join(', ')}]';
      return;
    }
    for (final law in laws) {
      final shape = _shape(law);
      if (shape == null) {
        _drop(
          dropped,
          where,
          'a ${law['kind']} law in ${law['variable'] ?? law['x'] ?? 'T'} '
          'the expression language is not given',
        );
        continue;
      }
      final range = (law['validRange'] as List?)?.cast<num>();
      final input = range == null
          ? LawInput.temperature
          : LawInput.temperature.within(
              range[0].toDouble(),
              range[1].toDouble(),
            );
      final probe = FormulaLaw(
        0,
        expression: shape,
        inputs: <String, LawInput>{'T': input},
      );
      final double c;
      try {
        if (!probe.dimension.isNone) throw StateError('not a pure shape');
        c = probe.at(reference);
      } on Object catch (e) {
        _drop(dropped, where, 'the shape "$shape" does not read: $e');
        continue;
      }
      // An anchored shape: the unanchored one is the value at the reference
      // state only when its fit is good there.
      final scale = _scaleOf(law, v);
      if (!c.isFinite || c == 0 || !_close(c * scale, v, _lawTolerance)) {
        _drop(
          dropped,
          where,
          '${law['kind']} gives ${c * scale} at the reference state, '
          'quoted $v',
        );
        continue;
      }
      final unit = propertyUnits['$group.$name']!.symbol;
      final head = unit == '1' ? _d(v) : '${_d(v)} [$unit]';
      final text = '$head * (($shape) / ${_d(c)})';
      final anchored = FormulaLaw(
        v,
        expression: text,
        inputs: <String, LawInput>{'T': input},
      );
      final at = anchored.at(reference);
      if (at != v) {
        _drop(dropped, where, 'the anchored formula gives $at, not $v');
        continue;
      }
      if (anchored.dimension != propertyUnits['$group.$name']!.dimension) {
        _drop(dropped, where, 'the formula measures ${anchored.dimension}');
        continue;
      }
      final published = c * scale;
      if (published != v) {
        value.anchor =
            'the ${law['kind']} law as published gives ${_d(published)} at '
            'the reference state; it is scaled by ${_d(v / published)} onto '
            'the quoted ${_d(v)}';
      }
      value
        ..lawKind = 'formula'
        ..lawDart =
            'FormulaLaw(${_d(v)}, expression: ${_s(text)}, '
            'inputs: <String, LawInput>{\'T\': ${_inputDart(input)}}'
            '';
      return;
    }
  }

  /// Records why the law of [where] was left out, after what was said of it
  /// already.
  static void _drop(Map<String, String> dropped, String where, String why) =>
      dropped[where] = switch (dropped[where]) {
        null => why,
        final said => '$said; then $why',
      };

  /// The kind of source a [citation] is: `handbook` for a handbook, a
  /// table, a standard or a maker's data sheet, `measured` for a paper that
  /// measured it.
  static String _kindOf(String citation) =>
      RegExp(
        r'[Hh]andbook|[Tt]able|[Dd]ata ?[Ss]heet|NIST|CRC|Kaye|Incropera|'
        r'Cengel|ASM|EN \d|ISO|ASTM|Guide|[Pp]roduct|ToolBox|MatWeb|Granta|'
        r'[Tt]ypical|OpenStax|Bulletin|[Mm]aterials? [Dd]atabase|eurocode|'
        r'Physical Tables',
      ).hasMatch(citation)
      ? 'handbook'
      : 'measured';

  /// The spread a research [note] gives around [value] — "spread 23 ..
  /// 30 MPa" — in the value's unit, or null when it gives none this reads.
  static List<double>? _spreadIn(String note, double value) {
    final match = RegExp(
      r'(?:[Ss]pread|spreads|span)\D{0,40}?(\d+(?:\.\d+)?(?:e[+-]?\d+)?)\s*'
      r'(?:\.\.|-|–| to )\s*(\d+(?:\.\d+)?(?:e[+-]?\d+)?)',
    ).firstMatch(note);
    if (match == null) return null;
    final low = double.parse(match[1]!), high = double.parse(match[2]!);
    for (final unit in const <double>[1.0, 1e9, 1e6, 1e3, 1e-3, 1e-2]) {
      if (low * unit <= value * 1.0001 && value <= high * unit * 1.0001) {
        return <double>[low * unit, high * unit];
      }
    }
    return null;
  }

  /// Applies the verification ([verification], `verification.json`) to
  /// [entries]' values and to [solids]' friction pairs, choosing where its
  /// records leave a choice as [decisions] says.
  ///
  /// A confirmed value keeps its number and takes the source that confirms
  /// it; a corrected one takes the source's number; an ambiguous one takes
  /// the grade the research proposed — along the grain for a wood's
  /// modulus — with the spread across grades as its interval and the grade
  /// named in the entry's description; an estimate stays one, its source
  /// saying what was searched. A value whose number changes has its law
  /// anchored again on the new one.
  static void _verify(
    Map<String, _Entry> entries,
    Map<String, Object?> verification,
    Map<String, Object?> decisions,
    Map<String, Object?> solids,
    Map<String, String> dropped,
  ) {
    final alongTheGrain = decisions['alongTheGrain']! as Map<String, Object?>;
    final atReference =
        decisions['atTheReferenceState']! as Map<String, Object?>;
    final spreads = decisions['spreads']! as Map<String, Object?>;
    final grades = <_Entry, List<String>>{};
    for (final r
        in (verification['values']! as List).cast<Map<String, Object?>>()) {
      final id = r['material']! as String;
      final [group, name] = (r['property']! as String).split('.');
      final entry = entries[id];
      final value = entry?.groups[group]?[name];
      // A colour is three numbers with no confidence of its own: a
      // confirmed one stands as it is.
      if (value?.value is List && r['status'] == 'confirmed') continue;
      if (entry == null || value == null || value.value is! double) {
        throw StateError(
          'the verification names $id ${r['property']}, which the '
          'catalogue does not hold',
        );
      }
      final key = '$id $group.$name';
      final status = r['status']! as String;
      // Null for an estimate, which no source gave.
      final source = (r['source_value'] as num?)?.toDouble() ?? double.nan;
      final was = value.value as double;
      var conditions = r['conditions']! as String;
      double? taken;
      String? why;
      switch (status) {
        case 'confirmed':
          if (atReference[key] case final String reason) {
            taken = source;
            why = reason;
          }
        case 'corrected':
          taken = source;
        case 'ambiguous':
          taken = source;
          (grades[entry] ??= <String>[]).add('$name for $conditions');
        case 'estimate':
          value
            ..confidence = 'estimate'
            ..verification = 'estimate'
            ..source =
                'estimate: no citable source was reached; searched: '
                '${r['note']}';
          continue;
        default:
          throw StateError('$key: a verification status "$status"');
      }
      // A wood's modulus is the one along the grain, whichever direction
      // the record measured: what a beam or a board of it bends by.
      if (group == 'mechanical' && name == 'youngsModulus') {
        if (alongTheGrain[id] case final Map<String, Object?> along) {
          taken = (along['value']! as num).toDouble();
          conditions = along['conditions']! as String;
          if (status != 'ambiguous') {
            (grades[entry] ??= <String>[]).add('$name for $conditions');
          }
        }
      }
      value
        ..confidence = _kindOf(r['citation']! as String)
        ..verification = status
        ..source = <String>[
          '${r['citation']}: $conditions (${r['url']})',
          ?why,
        ].join('; ');
      if (status == 'ambiguous') {
        final low = math.min(was, taken!), high = math.max(was, taken);
        value.interval = switch (spreads[key]) {
          [final num a, final num b] => <double>[a.toDouble(), b.toDouble()],
          _ => _spreadIn(r['note']! as String, taken) ?? <double>[low, high],
        };
      }
      if (taken != null && taken != was) {
        value
          ..value = taken
          ..lawDart = null
          ..lawKind = 'constant'
          ..anchor = null;
        if (value.interval case [
          final low,
          final high,
        ] when taken < low || taken > high) {
          value.interval = null;
        }
        if (value.lawSpec case final spec?) {
          dropped.remove(key);
          _law(entry, group, name, value, spec, dropped);
        }
      }
    }
    for (final MapEntry(key: entry, value: named) in grades.entries) {
      final what =
          entry.description ??
          '${entry.name[0].toUpperCase()}${entry.name.substring(1)}.';
      entry.description =
          '$what Of the grades its name covers, its '
          '${named.join('; its ')}.';
    }

    // The friction pairs, in the research data the catalogue's pairs are
    // made of.
    final raw = (solids['pairs']! as List).cast<Map<String, Object?>>();
    for (final r
        in (verification['frictionPairs']! as List)
            .cast<Map<String, Object?>>()) {
      final [a, b] = (r['material']! as String).split('|');
      final match = RegExp(
        r'^pair\.(\w+) \((\w+)\)$',
      ).firstMatch(r['property']! as String)!;
      final field = match[1]!, condition = match[2]!;
      bool sides(Map<String, Object?> p) =>
          ('f3d.${p['a']}' == a && 'f3d.${p['b']}' == b) ||
          ('f3d.${p['a']}' == b && 'f3d.${p['b']}' == a);
      final found =
          raw
              .where((p) => sides(p) && p['condition'] == condition)
              .firstOrNull ??
          raw
              .where(
                (p) =>
                    sides(p) &&
                    '${p['condition']}'.contains(condition) &&
                    !'${p['condition']}'.contains('tyre'),
              )
              .firstOrNull;
      final p = found?[field];
      if (p is! Map<String, Object?>) {
        throw StateError(
          'the verification names the pair $a|$b $field '
          '($condition), which the data does not hold',
        );
      }
      final status = r['status']! as String;
      final source = (r['source_value'] as num?)?.toDouble() ?? double.nan;
      p
        ..remove('note')
        ..remove('sourceUrl')
        ..['verification'] = status;
      if (status == 'estimate') {
        p
          ..['confidence'] = 'estimate'
          ..['source'] =
              'estimate: no citable source was reached; '
              'searched: ${r['note']}';
        continue;
      }
      p
        ..['confidence'] = _kindOf(r['citation']! as String)
        ..['source'] = '${r['citation']}: ${r['conditions']} (${r['url']})';
      if (status != 'confirmed') p['value'] = source;
      if (status == 'ambiguous') {
        p['range'] =
            _spreadIn(r['note']! as String, source) ??
            <double>[
              math.min(source, (r['catalog_value']! as num).toDouble()),
              math.max(source, (r['catalog_value']! as num).toDouble()),
            ];
      }
    }
  }

  /// Adds the measured coefficients of restitution ([data],
  /// `restitution.json`) to [pairs], one a pair of the catalogue's
  /// materials: the first record of the pair that gives a value, or the
  /// value its points give at the reference impact speed [decisions] names.
  /// A record the research marks of low reliability is an estimate. The
  /// coefficient is held at that one speed: a law in impact speed waits for
  /// a law input that is a contact's rather than a body's state, and the
  /// points stay in the data.
  static void _restitution(
    List<Map<String, Object?>> pairs,
    Map<String, Object?> data,
    Map<String, Object?> decisions,
    Map<String, _Entry> entries,
  ) {
    final rules = decisions['restitution']! as Map<String, Object?>;
    final speed = (rules['referenceSpeed']! as num).toDouble();
    final low = rules['estimateWhenNoteSays']! as String;
    final records = <String, List<Map<String, Object?>>>{};
    for (final r in (data['pairs']! as List).cast<Map<String, Object?>>()) {
      final a = r['a']! as String, b = r['b']! as String;
      if (!entries.containsKey(a) || !entries.containsKey(b)) continue;
      (records[MaterialPair.keyOf(a, b)] ??= <Map<String, Object?>>[]).add(r);
    }
    for (final MapEntry(:key, value: list) in records.entries) {
      double? e;
      Map<String, Object?>? from;
      String? at;
      for (final r in list) {
        if (r['restitution'] case final num given) {
          e = given.toDouble();
          from = r;
          at = '${r['impactSpeed']}';
          break;
        }
      }
      if (e == null) {
        for (final r in list) {
          final points = <List<double>>[
            for (final point in (r['points'] as List?) ?? const <Object?>[])
              <double>[for (final n in point! as List) (n! as num).toDouble()],
          ];
          if (points.length < 2) continue;
          e = TableLaw(
            0,
            xs: <double>[for (final p in points) p[0]],
            ys: <double>[for (final p in points) p[1]],
          ).interpolate(speed);
          from = r;
          at =
              '${_d(speed)} m/s, read between its points (${r['impactSpeed']})';
          break;
        }
      }
      if (e == null || from == null) continue;
      final estimate = '${from['note']}'.contains(low);
      final said =
          'restitution ${_d(e)} at $at: ${from['citation']}, '
          '${from['geometry']}; ${from['conditions']} (${from['url']})';
      final held = pairs.where((p) {
        return MaterialPair.keyOf(
              p['first']! as String,
              p['second']! as String,
            ) ==
            key;
      }).firstOrNull;
      final confidence = estimate ? 'estimate' : 'measured';
      if (held == null) {
        final [first, second] = key.split('|');
        pairs.add(<String, Object?>{
          'first': first,
          'second': second,
          'restitution': e,
          'confidence': confidence,
          'source': said,
        });
        continue;
      }
      held
        ..['restitution'] = e
        ..['source'] = 'friction: ${held['source']}; $said'
        ..['confidence'] = switch ((held['confidence'], confidence)) {
          ('estimate', _) || (_, 'estimate') => 'estimate',
          ('handbook', _) => 'handbook',
          _ => confidence,
        };
    }
  }

  static bool _inTemperature(Map<String, Object?> law) {
    final x = '${law['x'] ?? law['variable'] ?? 'T'}';
    return x == 'T' || x == 'theta' || x.startsWith('T (');
  }

  static bool _celsius(Map<String, Object?> law) {
    final x = '${law['x'] ?? law['variable'] ?? ''}';
    final unit = '${law['xUnit'] ?? law['unit'] ?? ''}';
    return x == 'theta' || x.contains('°C') || unit == 'C' || unit == '°C';
  }

  /// What the unanchored shape is multiplied by to give the property: the
  /// scale the law's own form carries, so its fit can be judged.
  static double _scaleOf(Map<String, Object?> law, double value) =>
      switch (law['kind']) {
        'linear' => value,
        'arrhenius' => switch (law['mu0']) {
          final num mu0 => mu0.toDouble(),
          _ => value,
        },
        _ => 1.0,
      };

  /// The law's form as a dimensionless expression in `T` (K); null when it
  /// is not one the generator writes.
  static String? _shape(Map<String, Object?> law) {
    const t = '(T / 1 [K])';
    const theta = '(T / 1 [K] - $zeroCelsius)';
    double? n(String key) => (law[key] as num?)?.toDouble();
    switch (law['kind']) {
      case 'andrade':
        final a = n('A'), b = n('B');
        if (a == null || b == null) return null;
        return 'exp(${_e(a)} + ${_e(b)} / $t)';
      case 'arrhenius':
        final ea = n('Ea'), b = n('B');
        if (ea != null) {
          final r = n('R') ?? molarGasConstant;
          return 'exp(${_e(ea)} / (${_e(r)} * $t))';
        }
        if (b != null) return 'exp(${_e(b)} / $t)';
        return null;
      case 'vft':
        final a = n('A'), b = n('B'), c = n('C');
        if (a == null || b == null || c == null) return null;
        return 'pow(10.0, ${_e(a)} + ${_e(b)} / ($t - ${_e(c)}))';
      case 'polynomial':
        final x = _celsius(law) ? theta : t;
        if (law['coefficients'] case final List coefficients
            when coefficients.every((c) => c is num)) {
          if (!_inTemperature(law) && law['variable'] != null) return null;
          return _horner(<double>[
            for (final c in coefficients) (c as num).toDouble(),
          ], x);
        }
        if (law['form'] case final String form
            when law['coefficients'] == null) {
          final coefficients = _polynomial(form, _celsius(law) ? 'theta' : 'T');
          return coefficients == null ? null : _horner(coefficients, x);
        }
        return null;
      case 'linear':
        // `x(T) = x20 * (1 + alpha * (T - T0))`, alpha named or written.
        final form = '${law['form'] ?? ''}';
        final written = RegExp(
          r'\(1 \+ ([0-9.eE+-]+|alpha) \*? ?\(T - [0-9.]+\)\)',
        ).firstMatch(form)?.group(1);
        final coefficients = law['coefficients'];
        final num? alpha = written == 'alpha'
            ? ((coefficients as Map?)?['alpha'] as num?)
            : written == null
            ? null
            : double.tryParse(written);
        final t0 = RegExp(r'T - ([0-9.]+)').firstMatch(form)?.group(1);
        if (alpha == null || t0 == null) return null;
        return '(1.0 + ${_e(alpha.toDouble())} * ($t - $t0))';
      case 'exponential':
        final match = RegExp(
          r'^([0-9.eE+-]+) exp\(([0-9.eE+-]+) T\)$',
        ).firstMatch('${law['form'] ?? ''}'.trim());
        if (match == null) return null;
        return '(${match.group(1)} * exp(${_e(double.parse(match.group(2)!))} '
            '* $t))';
      default:
        return null;
    }
  }

  /// The coefficients of a polynomial written `450 + 0.280 theta - 2.91e-4
  /// theta^2`, in [variable]; null when [form] is not one.
  static List<double>? _polynomial(String form, String variable) {
    final text = form.replaceAll(' ', '');
    final term = RegExp(
      '([+-]?)([0-9.]+(?:e[+-]?[0-9]+)?)(?:\\*?$variable(?:\\^([0-9]))?)?',
    );
    final coefficients = <int, double>{};
    var at = 0;
    for (final match in term.allMatches(text)) {
      if (match.start != at || match.group(0)!.isEmpty) return null;
      at = match.end;
      final sign = match.group(1) == '-' ? -1.0 : 1.0;
      final value = double.parse(match.group(2)!) * sign;
      final power = match.group(0)!.contains(variable)
          ? int.parse(match.group(3) ?? '1')
          : 0;
      coefficients[power] = (coefficients[power] ?? 0) + value;
    }
    if (at != text.length || coefficients.isEmpty) return null;
    final degree = coefficients.keys.reduce(math.max);
    return <double>[for (var i = 0; i <= degree; i++) coefficients[i] ?? 0.0];
  }

  static String _horner(List<double> coefficients, String x) {
    var text = _e(coefficients.last);
    for (var i = coefficients.length - 2; i >= 0; i--) {
      text = '(${_e(coefficients[i])} + $x * $text)';
    }
    return text;
  }

  /// [value] as the expression language writes a number.
  static String _e(double value) =>
      value.isNegative ? '(${_d(value)})' : _d(value);

  /// Every solid that says no friction of its own takes an estimate.
  ///
  /// **A family's median is of what was read, not of what was guessed**:
  /// the self-frictions it is taken over are the ones the data gives, before
  /// any estimate is made, and none the data marks as an estimate itself —
  /// so an estimate is never made of another, and the catalogue is the same
  /// whatever order its entries come in.
  static void _friction(List<_Entry> entries) {
    double? said(_Entry e) {
      final m = e.groups['mechanical'];
      final v = (m?['kineticFriction'] ?? m?['staticFriction'])?.value;
      return v is double ? v : null;
    }

    final read = <String, double>{
      for (final e in entries)
        if (e.groups['mechanical']?['staticFriction'] case final v?
            when v.value is double && v.confidence != 'estimate')
          e.field: v.value as double,
    };
    final needing = <_Entry>[
      for (final e in entries)
        if ((e.phase == 'solid' || e.phase == 'granular') && said(e) == null) e,
    ];
    for (final entry in needing) {
      final family = _families.entries
          .where((f) => f.value.contains(entry.field))
          .firstOrNull;
      // A family none of whose self-frictions was read gives no median: its
      // member takes the engine's default, as a solid of no family does.
      final known = family == null
          ? const <(String, double)>[]
          : (<(String, double)>[
              for (final field in family.value)
                if (field != entry.field)
                  if (read[field] case final v?) (field, v),
            ]..sort(
              (a, b) =>
                  a.$2 != b.$2 ? a.$2.compareTo(b.$2) : a.$1.compareTo(b.$1),
            ));
      final _Value estimate;
      if (family != null && known.isNotEmpty) {
        final mid = known.length ~/ 2;
        final median = known.length.isOdd
            ? known[mid].$2
            : (known[mid - 1].$2 + known[mid].$2) / 2;
        estimate = _Value(
          median,
          confidence: 'estimate',
          interval: <double>[known.first.$2, known.last.$2],
          source:
              'estimate: no measurement of it on itself was read; the median '
              'of the clean, dry self-friction of the ${family.key} in this '
              'catalogue (${known.map((k) => 'f3d.${k.$1}').join(', ')}), '
              'the spread their least and greatest',
        );
      } else if (_rocks.contains(entry.field)) {
        estimate = _Value(
          0.6,
          confidence: 'estimate',
          interval: const <double>[0.6, 0.85],
          source:
              "estimate: Byerlee's rule for rock sliding on rock, μ 0.6 to "
              '0.85 (Byerlee, "Friction of rocks", Pure and Applied '
              'Geophysics 116, 1978), its lower end; not a measurement of '
              'this stone',
        );
      } else if (_grains.contains(entry.field)) {
        estimate = _Value(
          0.6,
          confidence: 'estimate',
          interval: const <double>[0.6, 0.7],
          source:
              "estimate: a granular bed's internal friction, an angle of 30 "
              'to 35° (tan 0.6 to 0.7) for sands and soils, its lower end; '
              'not a measurement of this one',
        );
      } else {
        estimate = _Value(
          MaterialCatalog.defaultFriction,
          confidence: 'estimate',
          source:
              'estimate: no measurement of it on itself was read; the '
              "engine's default coefficient (MaterialCatalog.defaultFriction)",
        );
      }
      final mechanical = entry.groups.putIfAbsent(
        'mechanical',
        () => <String, _Value>{},
      );
      mechanical['staticFriction'] = estimate;
      entry.groupSources['mechanical'] ??= estimate.source!;
    }
  }

  /// Group sources, every value's law, and the entry's confidence.
  static void _finish(_Entry entry) {
    for (final MapEntry(key: group, value: values) in entry.groups.entries) {
      // The group's source: the one most of its values give.
      final sources = <String, int>{};
      for (final value in values.values) {
        if (value.source case final s?) sources[s] = (sources[s] ?? 0) + 1;
      }
      final common = sources.entries.isEmpty
          ? null
          : (sources.entries.toList()
                  ..sort((a, b) => b.value.compareTo(a.value)))
                .first
                .key;
      entry.groupSources[group] ??= common ?? 'see each value';
      for (final value in values.values) {
        if (value.source == entry.groupSources[group]) value.source = null;
        // A law scaled onto the quoted value says so, after where the value
        // is from.
        if (value.anchor case final anchor?) {
          value.source =
              '${value.source ?? entry.groupSources[group]}; '
              '$anchor';
        }
      }
    }
    // The base entries' values the research did not speak to: the
    // confidence their data gives. Every other value names its own.
    final counts = <String, int>{};
    for (final MapEntry(key: group, value: values) in entry.groups.entries) {
      for (final MapEntry(:key, :value) in values.entries) {
        if (value.value is! double) continue;
        if (value.confidence == null) {
          final said = entry.baseConfidences[group]?[key];
          if (!entry.base || said == null) {
            throw StateError(
              '${entry.id} $group.$key has no confidence in its data',
            );
          }
          values[key] =
              _Value(
                  value.value,
                  confidence: said,
                  source: value.source,
                  interval: value.interval,
                  verification: 'catalog',
                )
                ..lawDart = value.lawDart
                ..lawKind = value.lawKind;
        }
        final c = values[key]!.confidence!;
        counts[c] = (counts[c] ?? 0) + 1;
      }
    }
    entry.confidence =
        (counts.entries.toList()..sort((a, b) => b.value.compareTo(a.value)))
            .firstOrNull
            ?.key ??
        'handbook';
  }

  static List<Map<String, Object?>> _pairs(
    Map<String, Object?> base,
    Map<String, Object?> solids,
    Map<String, _Entry> entries,
  ) {
    final pairs = <String, Map<String, Object?>>{};
    for (final pair in (base['pairs']! as List).cast<Map<String, Object?>>()) {
      pairs[MaterialPair.keyOf(
        pair['first']! as String,
        pair['second']! as String,
      )] = switch (pair['confidence']) {
        final String word when Confidence.values.any((c) => c.name == word) =>
          pair,
        final other => throw StateError(
          'the base pair of ${pair['first']} and ${pair['second']} names a '
          'confidence (measured, handbook or estimate), not $other',
        ),
      };
    }
    for (final raw in (solids['pairs']! as List).cast<Map<String, Object?>>()) {
      final condition = '${raw['condition'] ?? ''}';
      if (!condition.contains('dry') || condition.contains('tyre')) continue;
      final a = 'f3d.${raw['a']}', b = 'f3d.${raw['b']}';
      if (!entries.containsKey(a) || !entries.containsKey(b)) continue;
      final key = MaterialPair.keyOf(a, b);
      if (pairs.containsKey(key)) continue;
      final p =
          (raw['kineticFriction'] ?? raw['staticFriction'])
              as Map<String, Object?>?;
      if (p == null || p['value'] == null) continue;
      pairs[key] = <String, Object?>{
        'first': a,
        'second': b,
        'friction': (p['value']! as num).toDouble(),
        'confidence': p['confidence'],
        'source':
            '${raw['kineticFriction'] == null ? 'static' : 'kinetic'} friction, '
            '$condition: ${_sourceOf(p)}',
      };
    }
    return pairs.values.toList();
  }

  // -------------------------------------------------------------- writing

  String dart() {
    final out = StringBuffer()
      ..writeln('// Generated by tool/gen_catalog.dart from tool/data/sources.')
      ..writeln('// Do not edit: change the data and run')
      ..writeln('// `dart run tool/gen_catalog.dart` in flutter3d_matter.')
      ..writeln()
      ..writeln("part of 'materials.dart';")
      ..writeln()
      ..writeln('/// The engine\'s built-in materials and the pairs measured')
      ..writeln('/// between them: what `MaterialCatalog.builtIn` holds.')
      ..writeln('///')
      ..writeln(
        '/// Values are at each entry\'s reference state (20 °C and one',
      )
      ..writeln('/// standard atmosphere unless its `temperature` says')
      ..writeln('/// otherwise), each with its confidence, and its law where')
      ..writeln('/// one is known: reference values for simulation, not for')
      ..writeln('/// design or safety calculations.')
      ..writeln('abstract final class Materials {');
    for (final entry in entries) {
      out
        ..writeln('  /// ${_doc(entry)}')
        ..writeln(
          '  static const PhysicalMaterial ${entry.field} = PhysicalMaterial(',
        )
        ..writeln("    id: '${entry.id}',")
        ..writeln('    name: ${_s(entry.name)},')
        ..writeln('    phase: ${_phase(entry.phase)},');
      if (entry.temperature != standardAirTemperature) {
        out.writeln('    temperature: ${_d(entry.temperature)},');
      }
      if (entry.pressure != standardAtmosphere) {
        out.writeln('    pressure: ${_d(entry.pressure)},');
      }
      out.writeln('    confidence: Confidence.${entry.confidence},');
      if (entry.externalIds.isNotEmpty) {
        final ids = entry.externalIds.keys.toList()..sort();
        out.writeln(
          '    externalIds: <String, String>{'
          '${ids.map((k) => '${_s(k)}: ${_s(entry.externalIds[k]!)}').join(', ')}},',
        );
      }
      for (final group in _groupProperties.keys) {
        final values = entry.groups[group];
        final models = group == 'inelastic' ? entry.models : const {};
        if ((values == null || values.isEmpty) && models.isEmpty) continue;
        out.writeln('    $group: ${_groupClass[group]}(');
        for (final name in _groupProperties[group]!) {
          final value = values?[name];
          if (value == null) continue;
          out.writeln('      $name: ${_valueDart(group, name, value)},');
        }
        for (final MapEntry(key: kind, value: model) in models.entries) {
          out.writeln('      $kind: ${_modelDart(model)},');
        }
        out
          ..writeln('      source: ${_s(entry.groupSources[group]!)},')
          ..writeln('    ),');
      }
      out
        ..writeln('  );')
        ..writeln();
    }
    out
      ..writeln('  /// Every built-in material, in the order the catalogue')
      ..writeln('  /// lists them.')
      ..writeln(
        '  static const List<PhysicalMaterial> all = <PhysicalMaterial>[',
      )
      ..writeln('    ${entries.map((e) => e.field).join(', ')},')
      ..writeln('  ];')
      ..writeln()
      ..writeln('  /// How the built-ins meet where a pair was measured, or')
      ..writeln('  /// where a liquid meets a wall.')
      ..writeln('  static const List<MaterialPair> pairs = <MaterialPair>[');
    for (final pair in pairs) {
      out.writeln(
        '    MaterialPair(${_s(pair['first']! as String)}, '
        '${_s(pair['second']! as String)}, '
        '${<String>[
          for (final key in <String>['friction', 'restitution', 'rollingResistance', 'contactAngle'])
            if (pair[key] case final num v) '$key: ${_d(v.toDouble())}',
          if (pair['confidence'] case final String c) 'confidence: Confidence.$c',
          'source: ${_s(pair['source']! as String)}',
        ].join(', ')}),',
      );
    }
    out
      ..writeln('  ];')
      ..writeln('}');
    return out.toString();
  }

  static String _doc(_Entry entry) {
    final what =
        entry.description ??
        '${entry.name[0].toUpperCase()}${entry.name.substring(1)}.';
    return what.replaceAll('\n', ' ');
  }

  static String _phase(String phase) => switch (phase) {
    'solid' || 'liquid' || 'gas' || 'granular' => 'MaterialPhase.$phase',
    _ => "MaterialPhase.named('$phase')",
  };

  static String _valueDart(String group, String name, _Value value) {
    if (_lists.contains('$group.$name')) {
      final list = value.value as List<double>;
      return group == 'optical'
          ? 'RgbValues(${list.map(_d).join(', ')})'
          : '<double>[${list.map(_d).join(', ')}]';
    }
    // The law's own arguments, then what is said of the value, which the
    // last pass over the entry may have settled after the law was made.
    return '${value.lawDart ?? 'ConstantLaw(${_d(value.value as double)}'}'
        '${_meta(value)})';
  }

  static String _meta(_Value value) => <String>[
    '',
    if (value.confidence case final c?) 'confidence: Confidence.$c',
    if (value.source case final s?) 'source: ${_s(s)}',
    if (value.interval case [final low, final high])
      'interval: PropertyInterval(${_d(low)}, ${_d(high)})',
  ].join(', ');

  static String _inputDart(LawInput input) => input.low == null
      ? 'LawInput.temperature'
      : 'LawInput(MatterState.temperatureId, unit: Unit.kelvin, '
            'low: ${_d(input.low!)}, high: ${_d(input.high!)})';

  static String _modelDart(Map<String, Object?> model) {
    final parameters = model['parameters']! as Map<String, double>;
    final terms = model['terms']! as List<Map<String, double>>;
    String map(Map<String, double> m) =>
        '<String, double>{${m.entries.map((e) => '${_s(e.key)}: ${_d(e.value)}').join(', ')}}';
    return 'ConstitutiveModel(${_s(model['model']! as String)}'
        '${parameters.isEmpty ? '' : ', parameters: ${map(parameters)}'}'
        '${terms.isEmpty ? '' : ', terms: <Map<String, double>>[${terms.map(map).join(', ')}]'}'
        '${model['confidence'] is String ? ', confidence: Confidence.${model['confidence']}' : ''}'
        '${model['source'] is String ? ', source: ${_s(model['source']! as String)}' : ''})';
  }

  /// [readme] with its coverage table between the markers rewritten: per
  /// entry, which properties carry a law in temperature and which are a
  /// constant at the reference state.
  String readme(String readme) {
    const start = '<!-- coverage:start -->', end = '<!-- coverage:end -->';
    final from = readme.indexOf(start), to = readme.indexOf(end);
    if (from < 0 || to < from) {
      throw StateError('README.md has no $start … $end markers');
    }
    final rows = StringBuffer()
      ..writeln(start)
      ..writeln()
      ..writeln(
        '| Material | Changes with temperature | Constant at the reference '
        'state |',
      )
      ..writeln('|---|---|---|');
    var laws = 0, constants = 0;
    for (final entry in entries) {
      final varying = <String>[], constant = <String>[];
      for (final group in _groupProperties.keys) {
        final values = entry.groups[group];
        if (values == null) continue;
        for (final name in _groupProperties[group]!) {
          final value = values[name];
          if (value == null || _lists.contains('$group.$name')) continue;
          (value.lawKind == 'constant' ? constant : varying).add(name);
        }
      }
      laws += varying.length;
      constants += constant.length;
      rows.writeln(
        '| `${entry.id}` | ${varying.isEmpty ? '—' : varying.join(', ')} | '
        '${constant.isEmpty ? '—' : constant.join(', ')} |',
      );
    }
    rows
      ..writeln()
      ..writeln(
        '$laws values of ${entries.length} materials change with '
        'temperature; $constants are constants at the reference state. '
        'No law in the catalogue reads pressure yet.',
      )
      ..writeln()
      ..write(end);
    return readme.replaceRange(from, to + end.length, rows.toString());
  }

  /// The verified data: every entry's values as the Dart holds them.
  Map<String, Object?> verified() => <String, Object?>{
    'about':
        'Generated by tool/gen_catalog.dart: every value of the built-in '
        'catalogue, as test/catalog_verified_test.dart holds the Dart to. '
        'Reference values for simulation, not for design or safety '
        'calculations.',
    'materials': <String, Object?>{
      for (final entry in entries)
        entry.id: <String, Object?>{
          'confidence': entry.confidence,
          if (entry.temperature != standardAirTemperature)
            'temperature': entry.temperature,
          for (final group in _groupProperties.keys)
            if (entry.groups[group] case final values? when values.isNotEmpty)
              group: <String, Object?>{
                for (final name in _groupProperties[group]!)
                  if (values[name] case final value?)
                    name: <String, Object?>{
                      'value': value.value,
                      'confidence': value.confidence,
                      'law': value.lawKind,
                      'verification': ?value.verification,
                    },
              },
        },
    },
    'pairs': <String, Object?>{
      for (final pair in pairs)
        MaterialPair.keyOf(
          pair['first']! as String,
          pair['second']! as String,
        ): <String, Object?>{
          for (final key in <String>[
            'friction',
            'restitution',
            'contactAngle',
            'confidence',
          ])
            if (pair[key] != null) key: pair[key],
        },
    },
    'lawsLeftOut': <String, Object?>{
      for (final key in dropped.keys.toList()..sort()) key: dropped[key],
    },
  };
}

/// [value] as a Dart double literal that reads back to the same double.
String _d(double value) {
  final text = value.toString();
  return text.contains('.') || text.contains('e') || text.contains('n')
      ? text
      : '$text.0';
}

/// [text] as a Dart string literal.
///
/// The word for molten rock in the data's notes is written as such: the
/// engine's packages name no game's genre, and a catalogue is not one.
String _s(String text) => _quoted(
  text.replaceAllMapped(
    RegExp(r'\b([Ll])avas?\b'),
    (m) => m[1] == 'L' ? 'Molten rock' : 'molten rock',
  ),
);

String _quoted(String text) =>
    "'${text.replaceAll(r'\', r'\\').replaceAll("'", r"\'").replaceAll(r'$', r'\$').replaceAll('\n', r'\n')}'";
