/// The word a level uses to ask for a reflection, and what it refuses.
///
///     dart test test/reflection_probe_kind_test.dart
///
/// A probe entity is pure data to the simulation, so the whole of what the
/// kind does is validate — and every number it refuses is one the renderer
/// would otherwise assert on at load, inside a frame, with the level half
/// built. The other claim worth holding is that the word is *asked for*: a
/// registry that does not speak it reads the entity as unknown, so a game
/// without probes is not quietly given one.
library;

import 'package:flutter3d_sim/flutter3d_sim.dart';
import 'package:test/test.dart';

/// One lit room with one probe in it, carrying [properties].
Level _room(Map<String, Object?> properties) =>
    Level.fromJson(<String, Object?>{
      'version': 1,
      'materials': <String, Object?>{
        'wall': <String, Object?>{
          'color': <double>[0.8, 0.8, 0.8],
        },
      },
      'brushes': <Object?>[
        <String, Object?>{
          'material': 'wall',
          'at': <double>[0.0, -0.5, 0.0],
          'size': <double>[10.0, 1.0, 10.0],
        },
      ],
      'lights': <Object?>[
        <String, Object?>{
          'type': 'point',
          'at': <double>[0.0, 2.0, 0.0],
          'color': <double>[1.0, 1.0, 1.0],
          'range': 8.0,
        },
      ],
      'entities': <Object?>[
        <String, Object?>{
          'type': EntityTypes.reflectionProbe,
          'at': <double>[0.0, 2.0, 0.0],
          ...properties,
        },
      ],
    });

List<LevelIssue> _errors(Map<String, Object?> properties) =>
    LevelValidator(
          registry: EntityRegistry(<EntityKind>[const ReflectionProbeKind()]),
        )
        .validate(_room(properties))
        .where((LevelIssue issue) => issue.isError)
        .toList();

void main() {
  test('a probe that says nothing is valid: every number has a default', () {
    expect(_errors(<String, Object?>{}), isEmpty);
  });

  test('and so is one that says everything', () {
    expect(
      _errors(<String, Object?>{
        'radius': 6.0,
        'intensity': 1.2,
        'faceSize': 32,
        'levels': 3,
        'near': 0.5,
        'far': 50.0,
      }),
      isEmpty,
    );
  });

  group('refuses', () {
    // Each of these is an assertion in `ReflectionProbeNode`'s constructor,
    // which is where a document that got past here would fail — at load,
    // with the scene half built. Mutation: drop any one check, and the
    // matching case below finds no error.
    final refused = <String, Map<String, Object?>>{
      'radius': <String, Object?>{'radius': -1.0},
      'intensity': <String, Object?>{'intensity': -0.5},
      'faces': <String, Object?>{'faceSize': 2},
      'levels': <String, Object?>{'levels': 0},
      'near': <String, Object?>{'near': 0.0},
      'far': <String, Object?>{'near': 1.0, 'far': 0.5},
    };
    for (final MapEntry(key: word, value: properties) in refused.entries) {
      test('a probe whose $word makes no sense', () {
        final errors = _errors(properties);
        expect(errors, hasLength(1), reason: errors.join('\n'));
        expect(errors.single.message, contains(word));
        expect(
          errors.single.where,
          contains(EntityTypes.reflectionProbe),
          reason: 'the issue says which entity it is about',
        );
      });
    }
  });

  test('spawns nothing: a probe is the renderer\'s to build', () {
    // A fixture revealed here would be a box in the middle of every room,
    // and a mechanism would be something the step visits for no reason.
    final world = CollisionWorld();
    final fixtures = <Fixture>[];
    final mechanisms = MechanismWorld(world);
    final entity = _room(<String, Object?>{}).entities.single;

    const ReflectionProbeKind().spawn(
      entity,
      SpawnContext(
        world: world,
        actors: ActorSystem(world: world, random: GameRandom(1)),
        mechanisms: mechanisms,
        onFixture: fixtures.add,
      ),
    );

    expect(fixtures, isEmpty);
    expect(mechanisms.all, isEmpty);
  });

  test('is a word a game has to ask for', () {
    // The registry seam, from the probe's side: a game that composes its
    // vocabulary without this kind reads the entity as an unknown type, and
    // is told so, rather than growing a reflection it did not ask for.
    final issues = LevelValidator(
      registry: EntityRegistry(<EntityKind>[]),
    ).validate(_room(<String, Object?>{}));

    expect(
      issues.where((LevelIssue issue) => issue.isError).single.message,
      contains('unknown type "${EntityTypes.reflectionProbe}"'),
    );
  });
}
