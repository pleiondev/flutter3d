import 'dart:convert';

import 'package:flutter3d_game/src/level/brush_geometry.dart';
import 'package:flutter3d_game/src/level/level.dart';
import 'package:flutter3d_game/src/level/entity_kind.dart';
import 'package:flutter3d_game/src/level/level_collision.dart';
import 'package:flutter3d_game/src/level/level_validator.dart';
import 'package:flutter3d_physics/flutter3d_physics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

/// A level with nothing wrong with it, so a test can break one thing at a time.
Level _valid() => Level(
      name: 'test',
      materials: <String, LevelMaterial>{'stone': LevelMaterial()},
      brushes: <Brush>[
        Brush(
          centre: Vector3(0.0, -0.5, 0.0),
          size: Vector3(20.0, 1.0, 20.0),
          material: 'stone',
        ),
      ],
      lights: <LevelLight>[
        LevelLight(position: Vector3(0.0, 3.0, 0.0), intensity: 10.0, range: 12.0),
      ],
      entities: <EntityDef>[
        EntityDef(type: EntityTypes.playerSpawn, position: Vector3(0.0, 1.0, 0.0)),
        EntityDef(type: EntityTypes.exit, position: Vector3(5.0, 1.0, 0.0)),
      ],
    );

void main() {
  group('the document round-trips', () {
    test('writing and reading gives the same document', () {
      final level = _valid();
      final once = level.toJson();
      final twice = Level.fromJson(
        jsonDecode(jsonEncode(once)) as Map<String, Object?>,
      ).toJson();

      // Compared as encoded text: field order is stable and this catches a
      // value quietly changing type on the way through, which comparing
      // decoded maps would not.
      expect(jsonEncode(twice), jsonEncode(once));
    });

    test('unknown entity keys survive, so the format can grow', () {
      // An editor written against a later version must not silently strip the
      // properties it does not recognise out of a level it merely opened.
      final document = <String, Object?>{
        'brushes': <Object?>[
          <String, Object?>{
            'at': <double>[0.0, 0.0, 0.0],
            'size': <double>[1.0, 1.0, 1.0],
          },
        ],
        'entities': <Object?>[
          <String, Object?>{
            'type': 'monster',
            'at': <double>[1.0, 2.0, 3.0],
            'flavour': 'unheard of',
            'count': 3,
          },
        ],
      };

      final round = Level.fromJson(document).toJson();
      final entity =
          (round['entities']! as List<Object?>).first! as Map<String, Object?>;

      expect(entity['flavour'], 'unheard of');
      expect(entity['count'], 3);
    });

    test('defaults are not written out', () {
      // A document full of redundant defaults is a document whose diffs are
      // unreadable, which is most of the reason this format is JSON at all.
      final level = Level(
        brushes: <Brush>[
          Brush(centre: Vector3.zero(), size: Vector3.all(1.0)),
        ],
      );
      final brush =
          (level.toJson()['brushes']! as List<Object?>).first! as Map<String, Object?>;

      expect(brush.containsKey('material'), isFalse);
      expect(brush.containsKey('solid'), isFalse);
    });

    test('a newer format version is refused rather than half-read', () {
      expect(
        () => Level.fromJson(<String, Object?>{'version': 99}),
        throwsA(isA<LevelFormatException>()),
      );
    });

    test('a wrong type names the key it found it on', () {
      expect(
        () => Level.fromJson(<String, Object?>{
          'brushes': <Object?>[
            <String, Object?>{'at': 'over there', 'size': <double>[1, 1, 1]},
          ],
        }),
        throwsA(
          isA<LevelFormatException>().having(
            (LevelFormatException e) => e.message,
            'message',
            contains('at'),
          ),
        ),
      );
    });

    test('an entity with no type is refused', () {
      expect(
        () => Level.fromJson(<String, Object?>{
          'entities': <Object?>[<String, Object?>{'at': <double>[0, 0, 0]}],
        }),
        throwsA(isA<LevelFormatException>()),
      );
    });
  });

  group('the validator', () {
    List<String> errorsOf(Level level) => LevelValidator()
        .validate(level)
        .where((LevelIssue i) => i.isError)
        .map((LevelIssue i) => i.message)
        .toList();

    test('accepts a level with nothing wrong', () {
      expect(errorsOf(_valid()), isEmpty);
    });

    test('catches a missing player spawn', () {
      final level = Level(
        brushes: _valid().brushes,
        entities: <EntityDef>[EntityDef(type: EntityTypes.exit)],
      );

      expect(errorsOf(level).join(), contains('player_spawn'));
    });

    test('catches two player spawns, which nothing chooses between', () {
      final level = Level(
        brushes: _valid().brushes,
        entities: <EntityDef>[
          EntityDef(type: EntityTypes.playerSpawn),
          EntityDef(type: EntityTypes.playerSpawn, position: Vector3(5, 0, 0)),
        ],
      );

      expect(errorsOf(level).join(), contains('2 player_spawn'));
    });

    test('catches a door whose key is nowhere in the level', () {
      final level = Level(
        brushes: _valid().brushes,
        entities: <EntityDef>[
          EntityDef(type: EntityTypes.playerSpawn),
          EntityDef(
            type: EntityTypes.door,
            properties: <String, Object?>{'key': 'red'},
          ),
        ],
      );

      expect(errorsOf(level).join(), contains('"red" key'));
    });

    test('accepts the same door when the key exists', () {
      final level = Level(
        brushes: _valid().brushes,
        entities: <EntityDef>[
          EntityDef(type: EntityTypes.playerSpawn),
          EntityDef(
            type: EntityTypes.door,
            properties: <String, Object?>{
              'key': 'red',
              'travel': <double>[0.0, 4.0, 0.0],
              'size': <double>[2.0, 4.0, 0.3],
            },
          ),
          EntityDef(
            type: EntityTypes.key,
            properties: <String, Object?>{'color': 'red'},
          ),
        ],
      );

      expect(errorsOf(level), isEmpty);
    });

    test('catches a door with nowhere to open to', () {
      // The same rule as a lift, and it belongs to the door rather than to the
      // validator — which is the whole point of the kinds owning their checks.
      final level = Level(
        brushes: _valid().brushes,
        entities: <EntityDef>[
          EntityDef(type: EntityTypes.playerSpawn),
          EntityDef(type: EntityTypes.door),
        ],
      );

      expect(errorsOf(level).join(), contains('travel'));
    });

    test('each kind owns its own rules', () {
      // One entity of every kind, each missing exactly what it needs, so the
      // registry is exercised rather than a handful of favourites.
      final level = Level(
        brushes: _valid().brushes,
        entities: <EntityDef>[
          EntityDef(type: EntityTypes.playerSpawn),
          EntityDef(type: EntityTypes.monster),
          EntityDef(type: EntityTypes.pickup),
          EntityDef(type: EntityTypes.key),
          EntityDef(type: EntityTypes.note),
          EntityDef(type: EntityTypes.trigger),
        ],
      );

      final messages = errorsOf(level).join('\n');

      expect(messages, contains('"kind"'));
      expect(messages, contains('"gives"'));
      expect(messages, contains('"color"'));
      expect(messages, contains('"text"'));
      expect(messages, contains('"size"'));
    });

    test('a monster of an unknown kind is refused', () {
      final level = Level(
        brushes: _valid().brushes,
        entities: <EntityDef>[
          EntityDef(type: EntityTypes.playerSpawn),
          EntityDef(
            type: EntityTypes.monster,
            properties: <String, Object?>{'kind': 'wyvern'},
          ),
        ],
      );

      expect(errorsOf(level).join(), contains('wyvern'));
    });

    test('a registry that knows fewer kinds refuses the rest', () {
      // What lets a different game reuse the package with its own entities,
      // and what lets a test narrow the set deliberately.
      final registry = EntityRegistry(<EntityKind>[const PlayerSpawnKind()]);
      final level = Level(
        brushes: _valid().brushes,
        entities: <EntityDef>[
          EntityDef(type: EntityTypes.playerSpawn),
          EntityDef(type: EntityTypes.torch),
        ],
      );

      final errors = LevelValidator(registry: registry)
          .validate(level)
          .where((LevelIssue i) => i.isError)
          .map((LevelIssue i) => i.message)
          .join();

      expect(errors, contains('torch'));
    });

    test('catches a reference to a name nothing has', () {
      final level = Level(
        brushes: _valid().brushes,
        entities: <EntityDef>[
          EntityDef(type: EntityTypes.playerSpawn),
          EntityDef(
            type: EntityTypes.button,
            properties: <String, Object?>{'target': 'the_lift'},
          ),
        ],
      );

      expect(errorsOf(level).join(), contains('the_lift'));
    });

    test('catches a button wired to nothing', () {
      final level = Level(
        brushes: _valid().brushes,
        entities: <EntityDef>[
          EntityDef(type: EntityTypes.playerSpawn),
          EntityDef(type: EntityTypes.button),
        ],
      );

      expect(errorsOf(level).join(), contains('target'));
    });

    test('catches a lift with nowhere to go', () {
      final level = Level(
        brushes: _valid().brushes,
        entities: <EntityDef>[
          EntityDef(type: EntityTypes.playerSpawn),
          EntityDef(type: EntityTypes.lift, name: 'lift'),
        ],
      );

      expect(errorsOf(level).join(), contains('travel'));
    });

    test('catches two entities sharing a name', () {
      final level = Level(
        brushes: _valid().brushes,
        entities: <EntityDef>[
          EntityDef(type: EntityTypes.playerSpawn),
          EntityDef(type: EntityTypes.door, name: 'gate'),
          EntityDef(type: EntityTypes.door, name: 'gate'),
        ],
      );

      expect(errorsOf(level).join(), contains('already used'));
    });

    test('catches an entity type nothing can spawn', () {
      final level = Level(
        brushes: _valid().brushes,
        entities: <EntityDef>[
          EntityDef(type: EntityTypes.playerSpawn),
          EntityDef(type: 'dragon'),
        ],
      );

      expect(errorsOf(level).join(), contains('dragon'));
    });

    test('catches a brush with no volume', () {
      final level = Level(
        brushes: <Brush>[
          Brush(centre: Vector3.zero(), size: Vector3(1.0, 0.0, 1.0)),
        ],
        entities: <EntityDef>[EntityDef(type: EntityTypes.playerSpawn)],
      );

      expect(errorsOf(level).join(), contains('negative side'));
    });

    test('catches a level with no geometry at all', () {
      final level = Level(
        entities: <EntityDef>[EntityDef(type: EntityTypes.playerSpawn)],
      );

      expect(errorsOf(level).join(), contains('nothing to stand on'));
    });

    test('overlapping brushes are a warning, not a refusal', () {
      // Overlap is how anybody joins a wall to a floor. It costs z-fighting,
      // not correctness, so it must not stop the level loading.
      final level = _valid();
      level.brushes.add(
        Brush(centre: Vector3(0.0, 0.0, 0.0), size: Vector3(2.0, 2.0, 2.0)),
      );

      final issues = LevelValidator().validate(level);

      expect(issues.where((LevelIssue i) => i.isError), isEmpty);
      expect(
        issues.map((LevelIssue i) => i.message).join(),
        contains('z-fight'),
      );
    });

    test('brushes that merely share a face are not reported', () {
      final level = _valid();
      // Sitting exactly on the floor, touching and not overlapping.
      level.brushes.add(
        Brush(centre: Vector3(0.0, 1.0, 0.0), size: Vector3(2.0, 2.0, 2.0)),
      );

      expect(
        LevelValidator()
            .validate(level)
            .map((LevelIssue i) => i.message)
            .join(),
        isNot(contains('z-fight')),
      );
    });

    test('assertValid names every error at once', () {
      final level = Level(brushes: _valid().brushes);

      expect(
        () => LevelValidator().assertValid(level),
        throwsA(
          isA<LevelFormatException>().having(
            (LevelFormatException e) => e.message,
            'message',
            contains('player_spawn'),
          ),
        ),
      );
    });

    test('a warning alone does not stop a level loading', () {
      final level = _valid();
      level.entities.removeWhere((EntityDef e) => e.type == EntityTypes.exit);

      expect(() => LevelValidator().assertValid(level), returnsNormally);
    });
  });

  group('brush geometry', () {
    test('a lone brush becomes six faces', () {
      final level = Level(
        brushes: <Brush>[
          Brush(centre: Vector3.zero(), size: Vector3.all(2.0)),
        ],
      );

      final surfaces = const BrushGeometry().build(level);

      expect(surfaces, hasLength(1));
      expect(surfaces.single.triangleCount, 12);
      expect(surfaces.single.vertexCount, 24);
    });

    test('brushes are grouped by material', () {
      final level = Level(
        brushes: <Brush>[
          Brush(centre: Vector3.zero(), size: Vector3.all(2.0), material: 'a'),
          Brush(
            centre: Vector3(10.0, 0.0, 0.0),
            size: Vector3.all(2.0),
            material: 'b',
          ),
          Brush(
            centre: Vector3(20.0, 0.0, 0.0),
            size: Vector3.all(2.0),
            material: 'a',
          ),
        ],
      );

      final surfaces = const BrushGeometry().build(level);
      final byMaterial = <String, BrushSurface>{
        for (final s in surfaces) s.material: s,
      };

      expect(surfaces, hasLength(2));
      expect(byMaterial['a']!.triangleCount, 24);
      expect(byMaterial['b']!.triangleCount, 12);
    });

    test('a texture repeats per metre rather than stretching to fit', () {
      // The whole reason UVs come from world space: a wall twice as wide gets
      // twice as much texture, not the same texture stretched.
      final small = Level(
        brushes: <Brush>[
          Brush(centre: Vector3.zero(), size: Vector3(2.0, 2.0, 2.0)),
        ],
      );
      final large = Level(
        brushes: <Brush>[
          Brush(centre: Vector3.zero(), size: Vector3(8.0, 2.0, 2.0)),
        ],
      );

      double uSpan(Level level) {
        final uv = const BrushGeometry().build(level).single.texcoords;
        var min = double.infinity;
        var max = double.negativeInfinity;
        for (var i = 0; i < uv.length; i += 2) {
          if (uv[i] < min) min = uv[i];
          if (uv[i] > max) max = uv[i];
        }
        return max - min;
      }

      expect(uSpan(small), closeTo(2.0, 1e-6));
      expect(uSpan(large), closeTo(8.0, 1e-6));
    });

    test('texture density follows the material', () {
      final level = Level(
        materials: <String, LevelMaterial>{
          'dense': LevelMaterial(texelsPerMetre: 4.0),
        },
        brushes: <Brush>[
          Brush(
            centre: Vector3.zero(),
            size: Vector3.all(2.0),
            material: 'dense',
          ),
        ],
      );

      final uv = const BrushGeometry().build(level).single.texcoords;
      var max = double.negativeInfinity;
      for (var i = 0; i < uv.length; i += 2) {
        if (uv[i] > max) max = uv[i];
      }

      expect(max, closeTo(4.0, 1e-6));
    });

    test('faces buried inside another brush are dropped', () {
      final level = Level(
        brushes: <Brush>[
          Brush(centre: Vector3.zero(), size: Vector3.all(10.0)),
          // Entirely swallowed by the first.
          Brush(centre: Vector3.zero(), size: Vector3.all(2.0)),
        ],
      );

      final surfaces = const BrushGeometry().build(level);

      // Only the outer brush's six faces survive.
      expect(surfaces.single.triangleCount, 12);
    });

    test('a shared face is kept, because removing it could open a hole', () {
      final level = Level(
        brushes: <Brush>[
          Brush(centre: Vector3.zero(), size: Vector3.all(2.0)),
          Brush(centre: Vector3(2.0, 0.0, 0.0), size: Vector3.all(2.0)),
        ],
      );

      final surfaces = const BrushGeometry().build(level);

      expect(surfaces.single.triangleCount, 24);
    });

    test('culling can be switched off', () {
      final level = Level(
        brushes: <Brush>[
          Brush(centre: Vector3.zero(), size: Vector3.all(10.0)),
          Brush(centre: Vector3.zero(), size: Vector3.all(2.0)),
        ],
      );

      final surfaces =
          const BrushGeometry(cullHiddenFaces: false).build(level);

      expect(surfaces.single.triangleCount, 24);
    });

    test('every face winds outward', () {
      // A face wound the wrong way is culled as a back face, which reads as a
      // hole in the level rather than as a winding bug — so it is worth
      // checking arithmetically rather than by looking.
      final level = Level(
        brushes: <Brush>[
          Brush(centre: Vector3(3.0, 4.0, 5.0), size: Vector3(2.0, 4.0, 6.0)),
        ],
      );
      final surface = const BrushGeometry().build(level).single;
      final p = surface.positions;
      final n = surface.normals;

      for (var t = 0; t < surface.indices.length; t += 3) {
        final a = surface.indices[t] * 3;
        final b = surface.indices[t + 1] * 3;
        final c = surface.indices[t + 2] * 3;

        final edge1 = Vector3(p[b] - p[a], p[b + 1] - p[a + 1], p[b + 2] - p[a + 2]);
        final edge2 = Vector3(p[c] - p[a], p[c + 1] - p[a + 1], p[c + 2] - p[a + 2]);
        final wound = edge1.cross(edge2)..normalize();
        final declared = Vector3(n[a], n[a + 1], n[a + 2]);

        expect(
          wound.dot(declared),
          closeTo(1.0, 1e-5),
          reason: 'triangle $t winds against its own normal',
        );
      }
    });

    test('every vertex carries a full set of attributes', () {
      // The renderer takes its stride from the vertex shader, which declares
      // position, normal, texcoord, tangent and colour. A surface missing one
      // of those does not fail — the GPU reads at the stride it expects and
      // assembles vertices out of the neighbours, which draws garbage and no
      // error. Counting them here is cheap; noticing it on screen was not.
      final level = Level(
        brushes: <Brush>[
          Brush(centre: Vector3.zero(), size: Vector3.all(2.0)),
        ],
      );
      final surface = const BrushGeometry().build(level).single;

      expect(surface.positions.length, surface.vertexCount * 3);
      expect(surface.normals.length, surface.vertexCount * 3);
      expect(surface.texcoords.length, surface.vertexCount * 2);
      expect(surface.tangents.length, surface.vertexCount * 4);
    });

    test('the tangent follows glTF handedness', () {
      // glTF says bitangent = cross(normal, tangent.xyz) * w, and its bitangent
      // is minus dP/dv. Getting the sign backwards lights normal-mapped
      // surfaces from the wrong side, and only on mirrored UVs — which is a bug
      // this project has already paid for once.
      final level = Level(
        brushes: <Brush>[
          Brush(centre: Vector3.zero(), size: Vector3.all(2.0)),
        ],
      );
      final surface = const BrushGeometry().build(level).single;

      for (var i = 0; i < surface.vertexCount; i++) {
        final normal = Vector3(
          surface.normals[i * 3],
          surface.normals[i * 3 + 1],
          surface.normals[i * 3 + 2],
        );
        final tangent = Vector3(
          surface.tangents[i * 4],
          surface.tangents[i * 4 + 1],
          surface.tangents[i * 4 + 2],
        );
        final w = surface.tangents[i * 4 + 3];

        expect(tangent.length, closeTo(1.0, 1e-6));
        expect(normal.dot(tangent), closeTo(0.0, 1e-6));
        expect(w, -1.0);
      }
    });

    test('nothing is emitted for a level with no brushes', () {
      expect(const BrushGeometry().build(Level()), isEmpty);
    });
  });

  group('building the collision world', () {
    test('solid brushes become colliders and decorative ones do not', () {
      final level = Level(
        brushes: <Brush>[
          Brush(centre: Vector3.zero(), size: Vector3.all(2.0)),
          Brush(
            centre: Vector3(5.0, 0.0, 0.0),
            size: Vector3.all(2.0),
            solid: false,
          ),
        ],
      );

      final world = CollisionWorld();
      level.addTo(world);

      expect(world.staticCount, 1);
    });

    test('a collider remembers the brush it came from', () {
      final level = Level(
        brushes: <Brush>[
          Brush(
            centre: Vector3.zero(),
            size: Vector3.all(2.0),
            material: 'stone',
          ),
        ],
      );

      final world = CollisionWorld();
      level.addTo(world);

      final hit = RayHit();
      world.raycast(Vector3(0.0, 0.0, 10.0), Vector3(0.0, 0.0, -1.0), 50.0, hit);

      expect((hit.collider!.userData! as Brush).material, 'stone');
    });

    test('the spawn is found, with its facing', () {
      final level = Level(
        entities: <EntityDef>[
          EntityDef(
            type: EntityTypes.playerSpawn,
            position: Vector3(1.0, 2.0, 3.0),
            yaw: 1.5,
          ),
        ],
      );

      final start = level.playerStart;

      expect(start?.position, Vector3(1.0, 2.0, 3.0));
      expect(start?.yaw, 1.5);
    });

    test('no spawn reads as null rather than throwing', () {
      expect(Level().playerStart, isNull);
    });
  });
}
