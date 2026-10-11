// A twin's USD export: primitives and meshes, UsdPreviewSurface and
// MaterialX materials, a hierarchy with referenced equipment, and the
// custom attributes a twin binds its elements by, carried into prefabs and
// the level, with a report of what did not come along.
import 'dart:io';

import 'package:flutter3d_core/formats.dart';
import 'package:flutter3d_sim/flutter3d_sim.dart';
import 'package:test/test.dart';

import 'convert_support.dart';

const String _plant = '$fixtures/usd/twin/plant.usda';

Map<String, Object?> _props(Map<String, Object?> row) =>
    (row['props'] as Map<String, Object?>?) ?? row;

void main() {
  late Directory scratch;
  setUp(() => scratch = Directory.systemTemp.createTempSync('f3d_usd_twin_'));
  tearDown(() => scratch.deleteSync(recursive: true));

  test('custom attributes ride the rows: an instance\'s on its row, a '
      'model\'s prims\' by node path', () async {
    final run = await convert(<String>[_plant], output: scratch);
    expect(run.code, 0, reason: run.text);

    final rows = run.rows('plant.level.json', 'plant');
    Map<String, Object?> named(String name) =>
        rows.firstWhere((Map<String, Object?> r) => r['name'] == name);

    final pump = named('Pump01');
    expect(pump['prefab'], 'pump');
    expect(pump['attributes'], <String, Object?>{
      'twin:id': 'P-101',
      'twin:ratedFlow': 12.5,
      'twin:floor': 2,
      'twin:critical': true,
      'twin:system': 'cooling',
      'twin:datasheet': 'docs/xp-200.pdf',
    });
    expect(
      (pump['attributes']! as Map<String, Object?>)['twin:floor'],
      isA<int>(),
    );
    expect(named('Pump02')['attributes'], <String, Object?>{
      'twin:id': 'P-102',
      'twin:ratedFlow': 12.5,
    });

    final model = named('plant');
    expect(model['asset'], 'plant.f3d');
    expect(model['nodeAttributes'], <String, Object?>{
      'Plant': <String, Object?>{
        'twin:id': 'PLANT-N',
        'customData:site': 'North yard',
      },
      'Plant/Pumps/Pump01/Gauge': <String, Object?>{'twin:id': 'PG-101'},
      'Plant/Tank': <String, Object?>{
        'twin:id': 'T-1',
        'twin:capacity': 25.0,
        'twin:level': 0.4,
        'twin:nozzles': <Object?>[1, 2, 3],
        // Not rounded to the six decimals a placement is.
        'twin:tolerance': 0.0000025,
      },
      'Plant/Pipe': <String, Object?>{'userProperties:line': 'L-300'},
      'Plant/Sensors/Temp7': <String, Object?>{
        'twin:id': 'TS-7',
        'twin:unit': 'degC',
        'twin:range': <Object?>[-20.0, 120.0],
      },
    });

    final pumpRows = run.rows('plant.level.json', 'pump');
    expect(_props(pumpRows.single)['nodeAttributes'], <String, Object?>{
      'Pump': <String, Object?>{'twin:model': 'XP-200'},
      'Pump/Body': <String, Object?>{'twin:part': 'housing'},
    });
  });

  test('the level finds an element by its twin id once expanded', () async {
    final run = await convert(<String>[_plant], output: scratch);
    final level = expandPrefabs(
      Level.fromJson(run.readJson('plant.level.json')! as Map<String, Object?>),
    );
    final p101 = findByAttribute(level.entities, 'twin:id', 'P-101');
    expect(p101, hasLength(1));
    // The pump's model row, expanded from the instance, carries both what
    // the plant said about the pump and what the pump's file said.
    final attributes = PrefabAttributes.of(p101.single.entity);
    expect(attributes['twin:floor'], 2);
    expect(attributes.nodesWhere('twin:model', 'XP-200'), <String>['Pump']);

    final sensor = findByAttribute(level.entities, 'twin:id', 'TS-7');
    expect(sensor.single.node, 'Plant/Sensors/Temp7');
    expect(
      findByAttribute(level.entities, 'twin:model', 'XP-200'),
      hasLength(3),
    );

    // The spare is scaled, so it is written as the pump's rows rather than
    // an instance; they carry its attributes all the same.
    final spare = findByAttribute(level.entities, 'twin:id', 'P-103');
    expect(spare, hasLength(1));
    expect(
      PrefabAttributes.of(
        spare.single.entity,
      ).nodesWhere('twin:part', 'housing'),
      <String>['Pump/Body'],
    );
  });

  test('the hierarchy: every prim a node of the layer\'s model, new prims '
      'under a referencing one kept beside its instance', () async {
    final run = await convert(<String>[_plant], output: scratch);
    final model = F3dDocument.parse(
      File('${scratch.path}/plant.f3d').readAsBytesSync(),
    );
    final names = <String?>{for (final node in model.nodes) node.name};
    expect(
      names,
      containsAll(<String>[
        'Plant',
        'Slab',
        'Pumps',
        'Pump01',
        'Gauge',
        'Dial',
        'Tank',
        'Hopper',
        'Filter',
        'Pipe',
        'Sensors',
        'Temp7',
      ]),
    );
    // The referenced pumps are their own prefab, placed twice, not drawn
    // into the plant's model.
    expect(names, isNot(contains('Body')));
    final report = run.report('plant.usda');
    expect(
      report['mapped'],
      contains(contains('Pump01: 1 prim defined under the reference')),
    );
  });

  test('UsdPreviewSurface and MaterialX surfaces, the latter in either '
      'vocabulary', () async {
    await convert(<String>[_plant], output: scratch);
    SurfaceMaterial surface(String name) => readFmat(
      File('${scratch.path}/materials/$name.fmat').readAsBytesSync(),
    ).surface;

    final steel = surface('plant_Steel');
    expect(steel.metallic, closeTo(1.0, 1e-6));
    expect(steel.roughness, closeTo(0.4, 1e-6));

    final paint = surface('plant_Paint');
    expect(paint.roughness, closeTo(0.35, 1e-6));
    expect(paint.baseColor.r, closeTo(0.8, 1e-3));

    // A MaterialX graph that wraps UsdPreviewSurface reads as one.
    final housing = surface('pump_Housing');
    expect(housing.roughness, closeTo(0.5, 1e-6));
    expect(housing.metallic, closeTo(0.2, 1e-6));
  });

  test('the report says what did not come along, and why', () async {
    final run = await convert(<String>[_plant], output: scratch);
    final report = run.report('plant.usda');
    final dropped = (report['dropped']! as List<Object?>).cast<String>();
    final warnings = (report['warnings']! as List<Object?>).cast<String>();
    final mapped = (report['mapped']! as List<Object?>).cast<String>();

    expect(
      dropped,
      contains(
        allOf(
          contains('/Plant/Pumps/Pump01.twin:feeds'),
          contains('relationship'),
        ),
      ),
    );
    expect(
      dropped,
      contains(
        allOf(contains('/Plant/Sensors/Temp7.twin:note'), contains('no value')),
      ),
    );
    expect(dropped, contains(contains('Camera')));
    expect(dropped, contains(contains('PointInstancer')));
    expect(dropped, contains(allOf(contains('Pump01'), contains('opinions'))));
    expect(
      warnings,
      contains(allOf(contains('/Plant/Tank.twin:level'), contains('first'))),
    );
    expect(
      mapped,
      contains(
        contains('plant: 12 custom attributes on 5 prims -> nodeAttributes'),
      ),
    );
    expect(
      mapped,
      contains(
        contains('plant: 9 custom attributes on 3 instances -> attributes'),
      ),
    );
  });

  test('a bundle carries the attributes in its prefab section', () async {
    final run = await convert(<String>[_plant], output: scratch, bundle: true);
    expect(run.code, 0, reason: run.text);
    final bundle = F3dDocument.parse(
      File('${scratch.path}/plant.f3d').readAsBytesSync(),
    );
    final level = Level.fromJson(bundle.prefabs['plant']!);
    final rows = level.prefabs['plant']!.entities;
    final pump = rows.firstWhere((EntityDef e) => e.name == 'Pump01');
    expect(PrefabAttributes.of(pump)['twin:id'], 'P-101');
    final model = rows.firstWhere((EntityDef e) => e.name == 'plant');
    expect(PrefabAttributes.of(model).nodesWhere('twin:id', 'T-1'), <String>[
      'Plant/Tank',
    ]);
  });
}
