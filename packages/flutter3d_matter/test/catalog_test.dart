/// The engine's catalogue as a whole: its shape, its data, its ids in other
/// systems, and the groups 1.0 added.
///
///     dart test test/catalog_test.dart
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter3d_matter/flutter3d_matter.dart';
import 'package:test/test.dart';

void main() {
  test('the built-in catalogue holds its shape', () {
    expect(
      checkMaterialCatalog(MaterialCatalog.builtIn(), frictionForSolids: true),
      isEmpty,
    );
    expect(Materials.all.length, greaterThanOrEqualTo(200));
  });

  test('every entry and every value says how it was come by', () {
    for (final material in Materials.all) {
      expect(material.confidence, isNotNull, reason: material.id);
      for (final group in material.groups) {
        for (final MapEntry(key: name, value: law) in group.laws.entries) {
          expect(
            Confidence.values,
            contains(material.confidenceOf(law)),
            reason: '${material.id} ${group.name}.$name',
          );
        }
      }
    }
  });

  test("a law's value is the law at the entry's reference state", () {
    // Water's viscosity is a table and its density a formula; both give the
    // quoted number at 20 °C to the bit, and move away from it.
    final water = Materials.water;
    final viscosity = water.fluid!.viscosity!;
    final density = water.mechanical!.density!;
    expect(viscosity, isA<TableLaw>());
    expect(density, isA<FormulaLaw>());
    expect(viscosity.at(water.referenceState), viscosity.value);
    expect(density.at(water.referenceState), density.value);
    final hot = MatterState.at(temperature: 353.15);
    expect(viscosity.at(hot), lessThan(viscosity.value / 2));
    expect(density.at(hot), lessThan(density.value));
  });

  test('the catalogue is the verified data, value by value', () {
    final verified =
        jsonDecode(File('tool/data/catalog.verified.json').readAsStringSync())
            as Map<String, Object?>;
    final materials = verified['materials']! as Map<String, Object?>;
    expect(materials.keys, unorderedEquals(Materials.all.map((m) => m.id)));
    for (final material in Materials.all) {
      final entry = materials[material.id]! as Map<String, Object?>;
      expect(entry['confidence'], material.confidence!.name);
      for (final group in material.groups) {
        final values = entry[group.name] as Map<String, Object?>? ?? const {};
        for (final MapEntry(key: name, value: law) in group.laws.entries) {
          final said = values[name] as Map<String, Object?>?;
          final where = '${material.id} ${group.name}.$name';
          expect(said, isNotNull, reason: '$where is not in the data');
          expect(said!['value'], law.value, reason: where);
          expect(said['law'], law.kind, reason: where);
          expect(said['confidence'], law.confidence?.name, reason: where);
        }
      }
    }
  });

  test('every solid has a coefficient of friction, with its source', () {
    for (final material in Materials.all) {
      if (material.phase != MaterialPhase.solid &&
          material.phase != MaterialPhase.granular) {
        continue;
      }
      final mechanical = material.mechanical!;
      final friction = mechanical.friction!;
      expect(material.confidenceOf(friction), isNotNull, reason: material.id);
      expect(
        (friction.source ?? mechanical.source).trim(),
        isNotEmpty,
        reason: material.id,
      );
    }
    // Where no source measured it, the source says what the estimate is.
    final granite = Materials.granite.mechanical!.friction!;
    expect(granite.confidence, Confidence.estimate);
    expect(granite.source, contains("Byerlee's rule"));
  });

  test('a verified value names what verified it', () {
    final verified =
        jsonDecode(File('tool/data/catalog.verified.json').readAsStringSync())
            as Map<String, Object?>;
    // Mutation: leave the verification unapplied, and a value is still
    // "recalled", its source a memory rather than a page.
    var recalled = 0;
    for (final material
        in (verified['materials']! as Map<String, Object?>).values) {
      for (final group in (material! as Map<String, Object?>).values) {
        if (group is! Map<String, Object?>) continue;
        for (final value in group.values) {
          final v = value! as Map<String, Object?>;
          if (v['verification'] == 'recalled' && v['value'] is num) recalled++;
        }
      }
    }
    expect(recalled, 0);
    // A wood bends by its modulus along the grain.
    final oak = Materials.oak.mechanical!.youngsModulus!;
    expect(oak.value, 12.5e9);
    expect(oak.source, contains('along the grain'));
    // An ambiguous value is the grade proposed, its spread the interval,
    // the grade named.
    final yield4340 = Materials.steel4340.mechanical!.yieldStrength!;
    expect(yield4340.value, 938e6);
    expect(yield4340.interval, const PropertyInterval(470e6, 1165e6));
    expect(
      File('lib/src/materials/materials.g.dart').readAsStringSync(),
      contains(
        RegExp(r'4340.*Of the grades its name covers, its yieldStrength'),
      ),
    );
    // Water's bulk modulus is the adiabatic one, ethanol's heat at 20 °C.
    expect(Materials.water.fluid!.bulkModulus!.value, 2193400000.0);
    expect(Materials.ethanol.thermal!.specificHeat!.value, 2393.0);
  });

  test('a pair measured to bounce says so', () {
    final catalogue = MaterialCatalog.builtIn();
    final steel = catalogue.pairOf('f3d.steel', 'f3d.steel')!;
    expect(steel.restitution, 0.95);
    expect(steel.confidence, Confidence.measured);
    expect(steel.source, contains('Lifshitz'));
    // A pair the research trusts little goes in as an estimate.
    final onConcrete = catalogue.pairOf('f3d.steel', 'f3d.concrete')!;
    expect(onConcrete.restitution, 0.597);
    expect(onConcrete.confidence, Confidence.estimate);
    expect(
      catalogue.contact(Materials.steel, Materials.steel).restitution,
      0.95,
    );
  });

  test("a family's median is of measured frictions, never of estimates", () {
    final byId = <String, PhysicalMaterial>{
      for (final m in Materials.all) m.id: m,
    };
    var medians = 0;
    for (final material in Materials.all) {
      final friction = material.mechanical?.staticFriction;
      final source = friction?.source;
      if (source == null || !source.contains('the median')) continue;
      medians++;
      final named = RegExp(
        r'f3d\.\w+',
      ).allMatches(source).map((m) => m[0]!).toList();
      expect(named, isNotEmpty, reason: material.id);
      // Mutation: let an estimate made earlier in the loop into a later
      // one's median, and a neighbour named here is an estimate itself.
      for (final id in named) {
        final theirs = byId[id]!.mechanical!.staticFriction!;
        expect(
          byId[id]!.confidenceOf(theirs),
          isNot(Confidence.estimate),
          reason: '${material.id} takes $id',
        );
      }
    }
    expect(medians, greaterThan(0));
  });

  test('a law scaled onto the quoted value says by how much', () {
    var scaled = 0;
    for (final material in Materials.all) {
      for (final group in material.groups) {
        for (final law in group.laws.values) {
          if (law is! FormulaLaw) continue;
          final source = law.source ?? '';
          if (!source.contains('as published gives')) continue;
          scaled++;
          expect(source, matches(RegExp(r'scaled by [0-9.e-]+ onto')));
        }
      }
    }
    expect(scaled, greaterThan(0));
  });

  test('a material is found by the id another system knows it by', () {
    final catalog = MaterialCatalog.builtIn();
    expect(
      catalog.byExternal(ExternalIdSpace.cas, '7732-18-5'),
      Materials.water,
    );
    expect(
      catalog.byExternal(ExternalIdSpace.ifc, 'concrete'),
      Materials.concrete,
    );
    expect(catalog.byExternal(ExternalIdSpace.cas, '0-00-0'), isNull);
    final read = PhysicalMaterial.fromJson(
      jsonDecode(jsonEncode(Materials.water.toJson())) as Map<String, Object?>,
    );
    expect(read.externalIds, Materials.water.externalIds);
  });

  test('molten basalt has a thermal group, every value of it an estimate', () {
    final thermal = Materials.basaltMelt.thermal!;
    expect(thermal.specificHeat, isNotNull);
    expect(thermal.conductivity, isNotNull);
    for (final law in thermal.laws.values) {
      expect(law.confidence, Confidence.estimate);
      expect(law.interval, isNotNull);
    }
  });

  test('the inelastic group and its models survive the file', () {
    final steel = Materials.steel;
    expect(steel.inelastic?.lossFactor, isNotNull);
    expect(steel.inelastic?.plastic?.model, ConstitutiveModel.johnsonCook);
    expect(Materials.rubber.inelastic?.hyperelastic?.terms, isNotEmpty);
    for (final material in <PhysicalMaterial>[steel, Materials.rubber]) {
      final json = material.toJson();
      final read = PhysicalMaterial.fromJson(
        jsonDecode(jsonEncode(json)) as Map<String, Object?>,
      );
      expect(read.toJson(), json, reason: material.id);
    }
  });

  test('a glass knows its dielectric F0, a liquid takes it from its index', () {
    expect(Materials.glass.optical!.dielectricF0!.value, closeTo(0.0426, 1e-9));
    final n = Materials.water.optical!.refractiveIndex!.value;
    final r = (n - 1) / (n + 1);
    expect(Materials.water.optical!.f0, r * r);
  });

  test('a surface tension as small as liquid helium\'s is plausible', () {
    const helium = PhysicalMaterial(
      id: 'cryo.helium',
      name: 'helium',
      phase: MaterialPhase.liquid,
      mechanical: MechanicalProperties(
        density: ConstantLaw(125.0),
        source: 's',
      ),
      fluid: FluidProperties(
        viscosity: ConstantLaw(3.6e-6),
        surfaceTension: ConstantLaw(1.0e-4),
        source: 's',
      ),
    );
    expect(helium.problems(), isEmpty);
  });

  test('every built-in survives its file and reads back equal', () {
    for (final material in Materials.all) {
      final json = jsonDecode(jsonEncode(material.toJson()));
      final read = PhysicalMaterial.fromJson(json as Map<String, Object?>);
      expect(read.toJson(), material.toJson(), reason: material.id);
      for (final group in read.groups) {
        for (final MapEntry(key: name, value: law) in group.laws.entries) {
          expect(
            law.at(read.referenceState),
            law.value,
            reason: '${material.id} ${group.name}.$name',
          );
        }
      }
    }
  });

  test('the version-2 fixture reads, laws and all', () {
    final read = PhysicalMaterial.fromJson(
      jsonDecode(
            File('test/fixtures/v2/water.material.json').readAsStringSync(),
          )
          as Map<String, Object?>,
    );
    expect(read.id, 'f3d.water');
    expect(read.fluid!.viscosity, isA<TableLaw>());
    expect(read.externalIds[ExternalIdSpace.cas], '7732-18-5');
    expect(
      checkMaterialCatalog(
        MaterialCatalog(materials: <PhysicalMaterial>[read]),
      ),
      isEmpty,
    );
  });
}
