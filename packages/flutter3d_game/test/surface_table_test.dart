/// The word a level says, and what a game thinks it is worth.
///
///     flutter test test/surface_table_test.dart
///
/// Two genres had written this out: the platformer's `Surfaces` maps a word to
/// a whole `MovementTuning`, the racing game's `GripTable` maps it to one
/// number, and everything either of them did around the map was the same — the
/// fallback, the `knows`, the `names`, and the paragraph explaining why an
/// unknown word must change nothing.
library;

import 'package:flutter3d_game/flutter3d_game.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

void main() {
  group('a table of what surfaces are worth', () {
    const table = SurfaceTable<double>(<String, double>{
      'ice': 0.2,
      'gravel': 0.6,
    }, fallback: 1.0);

    test('answers with what it was told', () {
      expect(table.of('ice'), 0.2);
      expect(table.of('gravel'), 0.6);
    });

    test('and a word it has never heard of changes nothing', () {
      // **The load-bearing decision.** A level may name a surface for its
      // footstep sound or its tyre noise alone, and a table that answered
      // "nothing in particular" — or a zero — would turn a straight into an ice
      // rink the day somebody added a sound.
      expect(table.of('marble'), 1.0);
      expect(table.of(null), 1.0);
    });

    test(
      'and says whether it has an opinion, for a game that wants a sound',
      () {
        expect(table.knows('ice'), isTrue);
        expect(table.knows('marble'), isFalse);
        expect(table.names, containsAll(<String>['ice', 'gravel']));
      },
    );
  });

  group('what a body is standing on', () {
    test('is the word on the brush the collider came from', () {
      // The rule `LevelCollision` sets and both genres read: a brush becomes a
      // collider that carries the brush, and the brush carries the word.
      final level = Level(
        name: 'one floor',
        brushes: <Brush>[
          Brush(
            centre: Vector3.zero(),
            size: Vector3(10.0, 1.0, 10.0),
            material: 'stone',
            surface: 'ice',
          ),
        ],
      );
      final world = CollisionWorld();
      level.addTo(world);

      // Found the way a game finds it: a ray down onto the floor, which is
      // what the runner's feet and the car's tyre both do.
      final hit = RayHit();
      expect(
        world.raycast(
          Vector3(0.0, 2.0, 0.0),
          Vector3(0.0, -1.0, 0.0),
          5.0,
          hit,
        ),
        isTrue,
      );

      expect(surfaceUnder(hit.collider), 'ice');
    });

    test('and nothing, for a body standing on something else', () {
      // A car, a crate, a monster: all perfectly good things to be standing on
      // and none of them a surface. Null rather than a guess.
      final collider = Collider(
        shape: CollisionBox(Vector3(1.0, 1.0, 1.0)),
        position: Vector3.zero(),
      )..userData = 'a crate, say';

      expect(surfaceUnder(collider), isNull);
      expect(surfaceUnder(null), isNull);
    });
  });
}
