/// The material catalogue: the built-ins, their file, a plugin's own, and
/// how two materials meet.
///
///     dart test test/materials_test.dart
library;

import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter3d_matter/flutter3d_matter.dart';
import 'package:flutter3d_plugin_api/flutter3d_plugin_api.dart';
import 'package:test/test.dart';

final class _Scope extends PluginScope {
  _Scope(String id)
    : manifest = PluginManifest(
        id: id,
        apiVersion: const PluginApiVersion(1, 0),
      );

  @override
  final PluginManifest manifest;

  @override
  int get rank => 0;

  final List<Registration> registrations = <Registration>[];

  @override
  void track(Registration registration) => registrations.add(registration);
}

const PhysicalMaterial _plum = PhysicalMaterial(
  id: 'orchard.plumJam',
  name: 'plum jam',
  phase: MaterialPhase.liquid,
  mechanical: MechanicalProperties(
    density: ConstantLaw(1300.0),
    source: 'a test',
  ),
  fluid: FluidProperties(viscosity: ConstantLaw(30.0), source: 'a test'),
);

void main() {
  test('every built-in is plausible, cited and under f3d', () {
    final ids = <String>{};
    for (final material in Materials.all) {
      expect(material.problems(), isEmpty, reason: material.id);
      expect(material.id, startsWith('f3d.'));
      expect(ids.add(material.id), isTrue, reason: 'two ${material.id}');
      expect(material.namespace, 'f3d');
    }
    // The catalogue takes them all, which is the same check again through
    // the door a plugin uses.
    expect(MaterialCatalog.builtIn().materials, hasLength(ids.length));
  });

  test("the decided reference values are the catalogue's (decision 3)", () {
    final water = Materials.water;
    expect(water.density, 998.2);
    expect(water.fluid!.viscosity!.value, 1.002e-3);
    expect(water.fluid!.surfaceTension!.value, 0.0728);
    expect(water.thermal!.specificHeat!.value, 4182.0);
    // Mercury at 20 °C, not the 25 °C values it was labelled with.
    expect(Materials.mercury.density, 13546.0);
    expect(Materials.mercury.fluid!.viscosity!.value, 1.55e-3);
    expect(Materials.oliveOil.density, 911.0);
    expect(Materials.oliveOil.fluid!.viscosity!.value, 0.084);
    // The air's is the standard world's, not a second number.
    expect(Materials.air.density, standardAirDensity);
  });

  test('a material survives its file, unknown keys and all', () {
    final json = Materials.water.toJson()
      ..['magnetic'] = <String, Object?>{'susceptibility': -9.0e-6};
    (json['fluid']! as Map<String, Object?>)['compressibility'] = 4.59e-10;
    final read = PhysicalMaterial.fromJson(
      jsonDecode(jsonEncode(json)) as Map<String, Object?>,
    );
    expect(read.toJson(), json);
    expect(read.unknown.keys, <String>['magnetic']);
    expect(read.fluid!.unknown.keys, <String>['compressibility']);
  });

  test('the version-1 fixture reads', () {
    final fixture = File('test/fixtures/v1/water.material.json');
    final read = PhysicalMaterial.fromJson(
      jsonDecode(fixture.readAsStringSync()) as Map<String, Object?>,
    );
    expect(read.id, 'f3d.water');
    expect(read.density, 998.2);
  });

  test('a body as a data plugin lists it reads without the envelope', () {
    final read = PhysicalMaterial.fromJson(_plum.toBody());
    expect(read.id, _plum.id);
    expect(read.fluid!.viscosity!.value, 30.0);
  });

  test('a document is refused for a newer version, no source or a bad id', () {
    Map<String, Object?> water() =>
        jsonDecode(jsonEncode(Materials.water.toJson()))
            as Map<String, Object?>;
    expect(
      () => PhysicalMaterial.fromJson(water()..['version'] = 99),
      throwsA(isA<MaterialFormatException>()),
    );
    final unsourced = water();
    (unsourced['fluid']! as Map<String, Object?>).remove('source');
    expect(
      () => PhysicalMaterial.fromJson(unsourced),
      throwsA(
        isA<MaterialFormatException>().having(
          (MaterialFormatException e) => e.message,
          'message',
          contains('source'),
        ),
      ),
    );
    expect(
      () => PhysicalMaterial.fromJson(water()..['id'] = 'water'),
      throwsA(isA<MaterialFormatException>()),
    );
  });

  test('a number in the wrong unit is a problem', () {
    // Millinewtons per metre and per cent, the two usual slips.
    const slipped = PhysicalMaterial(
      id: 'orchard.slip',
      name: 'slip',
      phase: MaterialPhase.liquid,
      mechanical: MechanicalProperties(
        density: ConstantLaw(998.2),
        source: 'a slip',
      ),
      fluid: FluidProperties(
        viscosity: ConstantLaw(1.002e-3),
        surfaceTension: ConstantLaw(72.8),
        source: 'a slip',
      ),
      thermal: ThermalProperties(
        emissivity: ConstantLaw(96.0),
        source: 'a slip',
      ),
    );
    expect(slipped.problems(), hasLength(2));
    expect(
      () => MaterialCatalog().add(slipped),
      throwsA(isA<MaterialRegistrationException>()),
    );
  });

  test("a plugin adds its own, under its own id, and takes them away", () {
    final catalogue = MaterialCatalog.builtIn();
    final scope = _Scope('orchard');
    final added = <String>[];
    catalogue.watch((PhysicalMaterial m) => added.add(m.id));
    final mine = catalogue.forPlugin(scope)..add(_plum);
    expect(catalogue.require('orchard.plumJam'), same(_plum));
    expect(added, <String>['orchard.plumJam']);
    expect(
      () => mine.add(
        const PhysicalMaterial(
          id: 'f3d.jam',
          name: 'jam',
          phase: MaterialPhase.solid,
        ),
      ),
      throwsA(isA<MaterialRegistrationException>()),
    );
    expect(
      () => catalogue.add(_plum),
      throwsA(isA<MaterialRegistrationException>()),
    );
    for (final r in scope.registrations) {
      r.cancel();
    }
    expect(catalogue.byId('orchard.plumJam'), isNull);
  });

  test('an unknown material names the plugin it needs', () {
    expect(
      () => MaterialCatalog.builtIn().require('orchard.plumJam'),
      throwsA(
        isA<UnknownMaterialException>()
            .having(
              (UnknownMaterialException e) => e.plugin,
              'plugin',
              'orchard',
            )
            .having(
              (UnknownMaterialException e) => e.message,
              'message',
              contains('"orchard" plugin'),
            ),
      ),
    );
  });

  test('two materials meet by the rule, unless the pair was measured', () {
    final catalogue = MaterialCatalog.builtIn();
    final steelOnGlass = catalogue.contact(Materials.steel, Materials.glass);
    expect(steelOnGlass.friction, closeTo(math.sqrt(0.57 * 0.4), 1e-12));
    // Rubber on concrete was measured: the pair wins.
    expect(
      catalogue.contact(Materials.concrete, Materials.rubber).friction,
      0.8,
    );
    expect(catalogue.pairOf('f3d.glass', 'f3d.water')!.contactAngle, 0.35);
    // A material says nothing: the body's default.
    expect(
      catalogue.contact(Materials.honey, Materials.honey).friction,
      closeTo(MaterialCatalog.defaultFriction, 1e-12),
    );
  });

  test('a liquid on a solid says how far its edge holds, and reads back', () {
    // Water beads on PTFE and the bench's phenolic top and spreads on glass;
    // each edge holds over a spread of angles that keeps a small drop still.
    // Mutation: drop the key from the JSON, and the pair reads back without
    // its hysteresis.
    final catalogue = MaterialCatalog.builtIn();
    final glass = catalogue.pairOf('f3d.water', 'f3d.glass')!;
    final ptfe = catalogue.pairOf('f3d.water', 'f3d.ptfe')!;
    final bench = catalogue.pairOf('f3d.bakelite', 'f3d.water')!;
    expect(glass.contactAngleHysteresis, 0.17);
    expect(ptfe.contactAngle, greaterThan(math.pi / 2));
    expect(bench.contactAngle, greaterThan(glass.contactAngle!));
    expect(bench.contactAngleHysteresis, greaterThan(0.0));
    final read = MaterialPair.fromJson(bench.toJson());
    expect(read.contactAngleHysteresis, bench.contactAngleHysteresis);
    expect(read.contactAngle, bench.contactAngle);
    expect(
      MaterialPair(
        'f3d.water',
        'f3d.glass',
        contactAngleHysteresis: 4.0,
        source: 'a test',
      ).problems(),
      contains(contains('hysteresis')),
    );
    expect(Materials.pairs.every((p) => p.problems().isEmpty), isTrue);
  });

  test('a contact says how its friction was come by', () {
    final catalogue = MaterialCatalog.builtIn();
    // Mutation: drop the confidence, or take the pair's when the rule was
    // used, and an estimate reads as a measurement.
    final measured = catalogue.contact(Materials.concrete, Materials.rubber);
    final pair = catalogue.pairOf('f3d.concrete', 'f3d.rubber')!;
    expect(measured.confidence, pair.confidence);
    expect(measured.source, pair.source);
    // A material with an estimated friction makes any contact of it an
    // estimate, whatever the other side's.
    final guessed = Materials.all.firstWhere(
      (m) => m.mechanical?.friction?.confidence == Confidence.estimate,
    );
    expect(
      Materials.steel.mechanical!.friction!.confidence,
      isNot(Confidence.estimate),
    );
    final contact = catalogue.contact(guessed, Materials.steel);
    expect(contact.confidence, Confidence.estimate);
    expect(contact.source, contains(guessed.id));
    expect(contact.source, contains('f3d.steel'));
    // And a material that says none takes the default, an estimate.
    final none = catalogue.contact(Materials.honey, Materials.honey);
    expect(none.confidence, Confidence.estimate);
    expect(none.source, contains('defaultFriction'));
  });
}
