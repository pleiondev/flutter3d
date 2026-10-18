/// A level on the Earth and made of named substances: `geoOrigin` and
/// `physicalMaterial`, which format 5 reserved and this build reads.
///
///     dart test test/level_geo_material_test.dart
library;

import 'package:flutter3d_matter/flutter3d_matter.dart';
import 'package:flutter3d_sim/flutter3d_sim.dart';
import 'package:test/test.dart';

Level _level({String entity = 'f3d.oak', String prefab = 'f3d.granite'}) =>
    Level.fromJson(<String, Object?>{
      'format': 'f3d.level',
      'version': 5,
      'geoOrigin': <String, Object?>{
        'latitude': 59.9386,
        'longitude': 30.3141,
        'altitude': 12,
        'frame': 'enu',
      },
      'materials': <String, Object?>{
        'floor': <String, Object?>{'physicalMaterial': 'f3d.concrete'},
      },
      'brushes': <Object?>[
        <String, Object?>{
          'at': <double>[0, 0, 0],
          'size': <double>[4, 1, 4],
          'material': 'floor',
          'physicalMaterial': 'f3d.steel',
        },
      ],
      'entities': <Object?>[
        <String, Object?>{
          'type': 'crate',
          'id': 'crate',
          'physicalMaterial': entity,
        },
      ],
      'prefabs': <String, Object?>{
        'pillar': <String, Object?>{
          'entities': <Object?>[
            <String, Object?>{
              'type': 'column',
              'id': 'column',
              'physicalMaterial': prefab,
            },
          ],
        },
      },
    });

void main() {
  test('the ids a level names, its prefabs\' included, sorted', () {
    expect(_level().physicalMaterialIds, <String>[
      'f3d.concrete',
      'f3d.granite',
      'f3d.oak',
      'f3d.steel',
    ]);
    final crate = _level().entities.single;
    expect(crate.physicalMaterial, 'f3d.oak');
    expect(crate.properties, isEmpty);
    expect(EntityDef.fromJson(crate.toJson()).physicalMaterial, 'f3d.oak');
  });

  test(
    'a level of the engine\'s substances plays on the built-in catalogue',
    () {
      final catalog = MaterialCatalog.builtIn();
      for (final id in _level().physicalMaterialIds) {
        expect(catalog.byId(id), isNotNull, reason: id);
      }
      _level().requireMaterials(catalog);
    },
  );

  test('an unknown id is refused naming the plugin it belongs to, from a '
      'prefab too', () {
    expect(
      () => _level(
        entity: 'volcano.basalt',
      ).requireMaterials(MaterialCatalog.builtIn()),
      throwsA(
        isA<UnknownMaterialException>().having(
          (e) => e.plugin,
          'plugin',
          'volcano',
        ),
      ),
    );
    expect(
      () => _level(prefab: 'mine.ore').worldOver(
        WorldProperties.standard,
        materials: MaterialCatalog.builtIn(),
      ),
      throwsA(
        isA<UnknownMaterialException>().having(
          (e) => e.message,
          'message',
          contains('"mine" plugin'),
        ),
      ),
    );
  });

  test('the level\'s place on the Earth becomes its world\'s', () {
    final level = _level();
    final world = level.worldOver(WorldProperties.standard);
    expect(world.geoOrigin, level.geoOrigin);
    expect(world.geoOrigin!.altitude, 12);
    // Written back as it came, and digested with it.
    expect(level.toJson()['geoOrigin'], <String, Object?>{
      'latitude': 59.9386,
      'longitude': 30.3141,
      'altitude': 12,
      'frame': 'enu',
    });
    expect(Level.fromJson(level.toJson()).geoOrigin, level.geoOrigin);
  });

  test('a geo origin that does not read refuses the level, naming the key', () {
    expect(
      () => Level.fromJson(<String, Object?>{
        'version': 5,
        'geoOrigin': <String, Object?>{'latitude': 120, 'longitude': 0},
      }),
      throwsA(
        isA<LevelFormatException>().having(
          (e) => e.message,
          'message',
          contains('geoOrigin'),
        ),
      ),
    );
  });

  test('a level that names no substance and no place reads and digests as '
      'before', () {
    final plain = Level.fromJson(<String, Object?>{'version': 5});
    expect(plain.geoOrigin, isNull);
    expect(plain.physicalMaterialIds, isEmpty);
    expect(plain.toJson().containsKey('geoOrigin'), isFalse);
  });
}
