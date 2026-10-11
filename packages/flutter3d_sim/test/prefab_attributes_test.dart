/// What a source said about a placed thing beyond how it looks — a twin's
/// element id, a rated flow — carried on prefab rows and found again in the
/// expanded level.
///
///     dart test test/prefab_attributes_test.dart
library;

import 'package:flutter3d_sim/flutter3d_sim.dart';
import 'package:test/test.dart';

Level _plant() => Level.fromJson(<String, Object?>{
  'name': 'plant',
  'prefabs': <String, Object?>{
    'pump': <String, Object?>{
      'entities': <Object?>[
        <String, Object?>{
          'type': 'model',
          'id': 'body0001',
          'name': 'pump',
          'at': <double>[0, 0, 0],
          'props': <String, Object?>{
            'asset': 'models/pump.f3d',
            'nodeAttributes': <String, Object?>{
              'Pump': <String, Object?>{'twin:model': 'XP-200'},
            },
          },
        },
      ],
    },
    'plant': <String, Object?>{
      'entities': <Object?>[
        <String, Object?>{
          'type': 'model',
          'id': 'site0001',
          'name': 'plant',
          'at': <double>[0, 0, 0],
          'props': <String, Object?>{
            'asset': 'plant.f3d',
            'nodeAttributes': <String, Object?>{
              'Plant/Tank': <String, Object?>{'twin:id': 'T-1'},
              'Plant/Sensors/Temp7': <String, Object?>{
                'twin:id': 'TS-7',
                'twin:unit': 'degC',
              },
            },
          },
        },
        <String, Object?>{
          'type': 'prefab',
          'id': 'pump0001',
          'name': 'Pump01',
          'at': <double>[2, 0, 1],
          'props': <String, Object?>{
            'prefab': 'pump',
            'attributes': <String, Object?>{
              'twin:id': 'P-101',
              'twin:floor': 2,
              'twin:critical': true,
            },
          },
        },
        <String, Object?>{
          'type': 'prefab',
          'id': 'pump0002',
          'name': 'Pump02',
          'at': <double>[2, 0, -1],
          'props': <String, Object?>{
            'prefab': 'pump',
            'attributes': <String, Object?>{'twin:id': 'P-102'},
          },
        },
      ],
    },
  },
  'entities': <Object?>[
    <String, Object?>{
      'type': 'prefab',
      'id': 'root0001',
      'name': 'plant',
      'props': <String, Object?>{'prefab': 'plant'},
    },
  ],
});

void main() {
  test('a row reads its own attributes and its nodes\'', () {
    final plant = _plant().prefabs['plant']!;
    final site = PrefabAttributes.of(plant.entities[0]);
    expect(site.own, isEmpty);
    expect(site.nodes.keys, <String>['Plant/Tank', 'Plant/Sensors/Temp7']);
    expect(site.nodesWhere('twin:id', 'TS-7'), <String>['Plant/Sensors/Temp7']);

    final pump = PrefabAttributes.of(plant.entities[1]);
    expect(pump['twin:id'], 'P-101');
    expect(pump['twin:floor'], 2);
    expect(pump['twin:critical'], isTrue);
    expect(pump.nodes, isEmpty);
    expect(PrefabAttributes.of(EntityDef(type: 'prop')).isEmpty, isTrue);
  });

  test('the expanded level finds an element by its attribute, on an '
      'instance and on a node of a model', () {
    final level = expandPrefabs(_plant());
    final pump = findByAttribute(level.entities, 'twin:id', 'P-102');
    expect(pump, hasLength(1));
    // The instance is gone in the played level; its attributes are on
    // the rows it expanded to.
    expect(pump.single.entity.name, 'plant/Pump02/pump');
    expect(pump.single.node, isNull);

    final sensor = findByAttribute(level.entities, 'twin:id', 'TS-7');
    expect(sensor.single.entity.name, 'plant/plant');
    expect(sensor.single.node, 'Plant/Sensors/Temp7');

    // A number matches across int and double, as JSON does not tell them
    // apart.
    expect(findByAttribute(level.entities, 'twin:floor', 2.0), hasLength(1));
    // Both pumps' models carry the template's node attribute.
    expect(
      findByAttribute(level.entities, 'twin:model', 'XP-200'),
      hasLength(2),
    );
    expect(findByAttribute(level.entities, 'twin:id', 'nothing'), isEmpty);
  });

  test('an instance overrides one attribute of a template row by a dotted '
      'key, and the rest stay', () {
    final source = _plant().toJson();
    final entities = source['entities']! as List<Object?>;
    (entities.single! as Map<String, Object?>)['props'] = <String, Object?>{
      'prefab': 'plant',
      'overrides': <String, Object?>{
        'pump0001': <String, Object?>{'attributes.twin:id': 'P-101A'},
      },
    };
    final level = expandPrefabs(Level.fromJson(source));
    final pump = level.entities.firstWhere(
      (EntityDef e) => e.name == 'plant/Pump01/pump',
    );
    final attributes = PrefabAttributes.of(pump);
    expect(attributes['twin:id'], 'P-101A');
    expect(attributes['twin:floor'], 2);
  });

  test('attributes write back as the properties they were read from', () {
    const attributes = PrefabAttributes(
      own: <String, Object?>{'twin:id': 'P-1'},
      nodes: <String, Map<String, Object?>>{
        'A/B': <String, Object?>{'twin:id': 'B-1'},
      },
    );
    final row = EntityDef(type: 'model', properties: attributes.toProperties());
    final back = PrefabAttributes.of(EntityDef.fromJson(row.toJson()));
    expect(back.own, attributes.own);
    expect(back.nodes, attributes.nodes);
    expect(const PrefabAttributes().toProperties(), isEmpty);
  });

  test('attributes that are not an object are refused with the key', () {
    expect(
      () => PrefabAttributes.of(
        EntityDef(type: 'prop', properties: <String, Object?>{'attributes': 3}),
      ),
      throwsA(
        isA<LevelFormatException>().having(
          (LevelFormatException e) => e.message,
          'message',
          contains('"attributes"'),
        ),
      ),
    );
    expect(
      () => PrefabAttributes.of(
        EntityDef(
          type: 'model',
          properties: <String, Object?>{
            'nodeAttributes': <String, Object?>{'A': 'x'},
          },
        ),
      ),
      throwsA(isA<LevelFormatException>()),
    );
  });
}
