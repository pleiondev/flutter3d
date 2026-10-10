/// Prefabs and depth layers (the level format's version 2), and their ids
/// and id-path overrides (version 3).
///
///     dart test test/prefab_test.dart
@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter3d_foundation/flutter3d_foundation.dart' show Portable;
import 'package:flutter3d_sim/flutter3d_sim.dart';
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart';

Map<String, Object?> _fixture(int version) =>
    jsonDecode(
          File('test/fixtures/v$version/first.level.json').readAsStringSync(),
        )
        as Map<String, Object?>;

EntityDef _named(Level level, String name) =>
    level.entities.firstWhere((EntityDef e) => e.name == name);

Matcher _near(double x, double y, double z) => predicate<Vector3>(
  (Vector3 v) => (v - Vector3(x, y, z)).length < 1e-6,
  'near ($x, $y, $z)',
);

/// A level of [prefabs] with one instance of [placed].
Level _levelOf(
  Map<String, Object?> prefabs, {
  String placed = 'a',
  Map<String, Object?> overrides = const <String, Object?>{},
}) => Level.fromJson(<String, Object?>{
  'version': 2,
  'brushes': <Object?>[
    <String, Object?>{
      'at': <double>[0, -0.5, 0],
      'size': <double>[10, 1, 10],
    },
  ],
  'prefabs': prefabs,
  'entities': <Object?>[
    <String, Object?>{
      'type': 'prefab',
      'prefab': placed,
      'name': 'it',
      if (overrides.isNotEmpty) 'overrides': overrides,
    },
  ],
});

void main() {
  test('a yawed instance turns its entities with the portable sine', () {
    // The same level must expand to the same bits in the VM and in a
    // browser, from step 0. Mutation: `Matrix3.rotationY(yaw)` again — libm's
    // sine and cosine, rounded to Float32 in the matrix — and the places
    // differ from the portable ones in the last bits.
    for (final yaw in <double>[0.3, 1.1, 2.7, -0.9, 5.5]) {
      final level = expandPrefabs(
        Level.fromJson(<String, Object?>{
          'version': 2,
          'prefabs': <String, Object?>{
            'a': <String, Object?>{
              'entities': <Object?>[
                <String, Object?>{
                  'type': 'marker',
                  'name': 'm',
                  'at': <double>[3.1, 0.5, 7.3],
                },
              ],
            },
          },
          'entities': <Object?>[
            <String, Object?>{
              'type': 'prefab',
              'prefab': 'a',
              'name': 'it',
              'at': <double>[1.0, 0.0, -2.0],
              'yaw': yaw,
            },
          ],
        }),
      );
      final (:sin, :cos) = Portable.sinCos(yaw);
      final local = Vector3(3.1, 0.5, 7.3);
      final expected =
          Vector3(1.0, 0.0, -2.0) +
          Vector3(
            cos * local.x + sin * local.z,
            local.y,
            cos * local.z - sin * local.x,
          );
      expect(
        _named(level, 'it/m').position.storage,
        expected.storage,
        reason: 'at yaw $yaw',
      );
    }
  });

  group('the v2 fixture', () {
    test('reads, and the newest fixture writes back exactly as it arrived', () {
      final level = Level.fromJson(_fixture(2));

      expect(level.prefabs.keys, <String>['lamp', 'post']);
      expect(level.materials['paint']!.depthLayer, 1);
      expect(level.brushes.last.depthLayer, 2);
      // Mutation: drop `prefabs` from `toJson`, or write `depthLayer` always.
      final json = _fixture(Level.formatVersion);
      expect(jsonEncode(Level.fromJson(json).toJson()), jsonEncode(json));
      // The v3 one, lifted, is the same level at the newest version: only
      // the envelope's number moves, since it said nothing about the world.
      final lifted = Level.fromJson(_fixture(3)).toJson();
      expect(lifted['version'], Level.formatVersion);
      expect(
        jsonEncode(<String, Object?>{...lifted}..remove('version')),
        jsonEncode(_fixture(3)..remove('version')),
      );
    });

    test('expands its nested instance with the nearest override winning', () {
      final level = expandRecipes(Level.fromJson(_fixture(2)));

      expect(
        level.entities.where((EntityDef e) => e.type == EntityTypes.prefab),
        isEmpty,
      );
      expect(level.prefabs, isEmpty);
      final base = _named(level, 'gate/base');
      final bulb = _named(level, 'gate/top/bulb');
      // The level's override moved `base` half a metre along the prefab's z,
      // and the instance's quarter turn puts that along the level's x.
      expect(base.position, _near(2.5, 0.0, 1.0));
      expect(base.yaw, closeTo(1.5707963267948966, 1e-9));
      expect(bulb.position, _near(2.0, 3.0, 1.0));
      // The template says strength 1 and warm; the nested instance in `post`
      // says strength 2; the level says cold. Mutation: merge the other way
      // round in `mergePrefabOverrides` and the tint comes back warm.
      expect(bulb.properties['glow'], <String, Object?>{
        'strength': 2.0,
        'tint': 'cold',
      });
    });
  });

  group('a level without prefabs', () {
    test('is the very level once expanded', () {
      final level = Level.fromJson(_fixture(1));
      expect(identical(expandPrefabs(level), level), isTrue);
    });

    test('a version-1 document is written back as the newest, with ids', () {
      // Every level has ids, so every level is written at a version that
      // has them (3 and up); what the old document said is kept.
      final json = _fixture(1);
      final written = Level.fromJson(json).toJson();
      expect(written['version'], Level.formatVersion);
      expect(written['format'], 'f3d.level');
      expect(written['generatedBy'], json['generatedBy']);
      final rows = written['entities']! as List<Object?>;
      expect(
        rows.every((Object? r) => (r! as Map<String, Object?>)['id'] is String),
        isTrue,
      );
      expect(Level().toJson()['version'], Level.formatVersion);
    });
  });

  group('override paths', () {
    test('an unnamed entity is addressed by its index', () {
      final level = expandPrefabs(
        _levelOf(
          <String, Object?>{
            'a': <String, Object?>{
              'entities': <Object?>[
                <String, Object?>{'type': 'marker', 'size': 1},
              ],
            },
          },
          overrides: <String, Object?>{
            '#0': <String, Object?>{'size': 3},
          },
        ),
      );
      expect(level.entities.single.properties['size'], 3);
    });

    test('a null takes a key away, and the type cannot be overridden', () {
      final row = applyPrefabOverride(
        <String, Object?>{'id': 'm1', 'type': 'marker', 'size': 1},
        <String, Object?>{'size': null},
      );
      expect(row['type'], 'marker');
      // A property, so it is taken out of `props`; the row's own keys stay.
      expect(row['props'], <String, Object?>{});
      expect(row['id'], 'm1');
      expect(
        () => applyPrefabOverride(
          <String, Object?>{'type': 'marker'},
          <String, Object?>{'type': 'monster'},
        ),
        throwsA(isA<LevelFormatException>()),
      );
    });

    test('an override naming nothing is a warning, not a refusal', () {
      final level = _levelOf(
        <String, Object?>{
          'a': <String, Object?>{
            'entities': <Object?>[
              <String, Object?>{'type': 'marker', 'name': 'm'},
            ],
          },
        },
        overrides: <String, Object?>{
          'gone': <String, Object?>{'size': 3},
        },
      );
      expect(expandPrefabs(level).entities, hasLength(1));
      expect(
        prefabIssues(level).map((LevelIssue i) => i.message),
        contains(contains('"gone" names nothing')),
      );
    });
  });

  group('refusals', () {
    test('a prefab that contains itself is named, with the chain', () {
      final level = _levelOf(<String, Object?>{
        'a': <String, Object?>{
          'entities': <Object?>[
            <String, Object?>{'type': 'prefab', 'prefab': 'b'},
          ],
        },
        'b': <String, Object?>{
          'entities': <Object?>[
            <String, Object?>{'type': 'prefab', 'prefab': 'a'},
          ],
        },
      });
      expect(prefabCycle(level.prefabs), <String>['a', 'b', 'a']);
      // Mutation: drop the stack check in `_expand` and this never returns.
      expect(
        () => expandPrefabs(level),
        throwsA(
          isA<LevelFormatException>().having(
            (LevelFormatException e) => e.message,
            'message',
            contains('a → b → a'),
          ),
        ),
      );
    });

    test('an instance of a prefab the level lacks', () {
      final level = _levelOf(<String, Object?>{}, placed: 'nowhere');
      expect(() => expandPrefabs(level), throwsA(isA<LevelFormatException>()));
      expect(
        LevelValidator(registry: EntityRegistry(<EntityKind>[]))
            .validate(level)
            .where((LevelIssue i) => i.isError)
            .map((LevelIssue i) => i.message),
        contains(contains('"nowhere"')),
      );
    });
  });

  group('unpacking one level', () {
    test('keeps a nested instance linked, carrying what reached it', () {
      final level = Level.fromJson(_fixture(2));
      final gate = PrefabInstance.of(_named(level, 'gate'))!;
      final rows = expandPrefabInstance(gate, level.prefabs, deep: false);

      expect(rows.map((EntityDef e) => e.name), <String>[
        'gate/base',
        'gate/top',
      ]);
      final top = PrefabInstance.of(rows.last)!;
      expect(top.prefab, 'lamp');
      // Addressed by the bulb's id, which the v2 file's `bulb` became.
      final bulb = level.prefabs['lamp']!.entities.single.id;
      expect(top.overrides[bulb], <String, Object?>{
        'glow.strength': 2.0,
        'glow.tint': 'cold',
      });
    });
  });
}
