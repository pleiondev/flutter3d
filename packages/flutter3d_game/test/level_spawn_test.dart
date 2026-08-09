import 'dart:convert';

import 'package:flutter3d_game/flutter3d_game.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

/// A level with one brush to stand on and whatever entities a test wants.
Level _level(List<Map<String, Object?>> entities) => Level.fromJson(
      jsonDecode(
        jsonEncode(<String, Object?>{
          'name': 'spawn',
          'brushes': <Object?>[
            <String, Object?>{
              'at': <double>[0.0, -0.5, 0.0],
              'size': <double>[40.0, 1.0, 80.0],
              'material': 'stone',
            },
          ],
          'materials': <String, Object?>{
            'stone': <String, Object?>{
              'baseColor': <double>[0.5, 0.5, 0.5, 1.0],
            },
          },
          'entities': entities,
        }),
      ) as Map<String, Object?>,
    );

({CollisionWorld world, MonsterSystem monsters, List<Monster> seen}) _spawn(
  Level level,
) {
  final world = CollisionWorld();
  level.addTo(world);
  final monsters = MonsterSystem(
    world: world,
    projectiles: ProjectileSystem(world: world),
  );
  final seen = <Monster>[];
  level.spawnInto(
    SpawnContext(
      world: world,
      monsters: monsters,
      onMonsterSpawned: seen.add,
    ),
  );
  return (world: world, monsters: monsters, seen: seen);
}

void main() {
  group('spawning a level', () {
    test('every monster entity becomes a monster', () {
      final result = _spawn(
        _level(<Map<String, Object?>>[
          <String, Object?>{
            'type': 'monster',
            'kind': 'runner',
            'position': <double>[2.0, 0.0, 0.0],
          },
          <String, Object?>{
            'type': 'monster',
            'kind': 'tank',
            'position': <double>[-2.0, 0.0, 4.0],
          },
        ]),
      );

      expect(result.monsters.aliveCount, 2);
      expect(
        result.monsters.monsters.map((Monster m) => m.def.name),
        <String>['runner', 'tank'],
      );
    });

    test('the hook is told about each one', () {
      final result = _spawn(
        _level(<Map<String, Object?>>[
          <String, Object?>{
            'type': 'monster',
            'kind': 'shooter',
            'position': <double>[0.0, 0.0, 3.0],
          },
        ]),
      );

      expect(result.seen, hasLength(1));
      expect(result.seen.single.def.name, 'shooter');
    });

    test('an entity authored at the floor stands on it', () {
      // The document places feet, because that is what an author can see in an
      // editor; the body is positioned by its centre. Getting this wrong buries
      // a monster to the waist or floats it.
      final result = _spawn(
        _level(<Map<String, Object?>>[
          <String, Object?>{
            'type': 'monster',
            'kind': 'runner',
            'position': <double>[0.0, 0.0, 0.0],
          },
        ]),
      );

      final monster = result.monsters.monsters.single;
      expect(monster.position.y, closeTo(monster.def.height / 2.0, 1e-6));

      // And a step of simulation does not drop it, which is what would happen
      // if it had been spawned inside the floor and pushed out.
      // Far away, so nothing chases and the only thing acting on the body is
      // gravity and the floor.
      final player = Collider(
        shape: CollisionCapsule(radius: 0.35, halfHeight: 0.55),
        position: Vector3(0.0, 0.9, 30.0),
        layer: CollisionLayers.player,
      );
      for (var i = 0; i < 30; i++) {
        result.monsters.step(
          1.0 / 60.0,
          playerEye: Vector3(0.0, 1.6, 30.0),
          playerCollider: player,
        );
      }
      expect(monster.position.y, closeTo(monster.def.height / 2.0, 0.05));
    });

    test('yaw carries across', () {
      final result = _spawn(
        _level(<Map<String, Object?>>[
          <String, Object?>{
            'type': 'monster',
            'kind': 'runner',
            'position': <double>[0.0, 0.0, 0.0],
            // Radians, as the document format stores them.
            'yaw': 1.5,
          },
        ]),
      );

      expect(result.monsters.monsters.single.yaw, closeTo(1.5, 1e-6));
    });

    test('kinds with nothing to spawn spawn nothing', () {
      final result = _spawn(
        _level(<Map<String, Object?>>[
          <String, Object?>{
            'type': 'player_spawn',
            'position': <double>[0.0, 0.0, 0.0],
          },
          <String, Object?>{
            'type': 'torch',
            'position': <double>[1.0, 2.0, 1.0],
          },
        ]),
      );

      expect(result.monsters.aliveCount, 0);
      expect(result.seen, isEmpty);
    });

    test('an unknown type is skipped rather than fatal', () {
      // An editor has to be able to load a document written by a newer build.
      expect(
        () => _spawn(
          _level(<Map<String, Object?>>[
            <String, Object?>{
              'type': 'teleporter',
              'position': <double>[0.0, 0.0, 0.0],
            },
          ]),
        ),
        returnsNormally,
      );
    });

    test('a monster naming a kind that does not exist is skipped', () {
      // Already an error from the validator, so a level like this never
      // reaches a player — but spawning from it must not throw.
      final result = _spawn(
        _level(<Map<String, Object?>>[
          <String, Object?>{
            'type': 'monster',
            'kind': 'dragon',
            'position': <double>[0.0, 0.0, 0.0],
          },
        ]),
      );

      expect(result.monsters.aliveCount, 0);
    });

    test('a registry can be narrowed', () {
      // A test harness, or a build that wants no monsters in an editor
      // preview, passes its own set.
      final level = _level(<Map<String, Object?>>[
        <String, Object?>{
          'type': 'monster',
          'kind': 'runner',
          'position': <double>[0.0, 0.0, 0.0],
        },
      ]);
      final world = CollisionWorld();
      level.addTo(world);
      final monsters = MonsterSystem(
        world: world,
        projectiles: ProjectileSystem(world: world),
      );

      level.spawnInto(
        SpawnContext(world: world, monsters: monsters),
        registry: EntityRegistry(<EntityKind>[const PlayerSpawnKind()]),
      );

      expect(monsters.aliveCount, 0);
    });
  });
}
