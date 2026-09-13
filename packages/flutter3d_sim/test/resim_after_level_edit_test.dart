/// `rp-03`'s first half: a snapshot restored into a level that has been
/// edited since it was taken continues by the new geometry, rather than
/// crashing or dragging the old geometry along with it.
///
///     flutter test test/resim_after_level_edit_test.dart
///
/// **Why static geometry needs no remapping at all, and an actor does.** A
/// [Snapshot] never names a brush — `Level.addTo` rebuilds every collider
/// fresh from whichever document is loaded, and a [CharacterController]'s own
/// state is a position and a velocity, neither of which is *about* a
/// particular wall. So the half of `rp-03` this file measures — "a wall
/// moved, and the run keeps going by the new geometry" — turns out to
/// already hold, by construction, once it is actually asked. What remains
/// unbuilt is the other half, named in `doc/tooling-plan.md`'s write-up
/// rather than here: an actor removed from the level is an entity gone from
/// `EcsWorld`, which restores components by raw index today
/// (`_generations`/`_free`/`value.key`) rather than by the name
/// `EntityDef.name` already carries — a level edited to remove or reorder an
/// entity would restore a *different* entity's state onto whatever now
/// happens to sit at the old index, silently, rather than naming what it
/// could not find a home for. Fixing that is a change to `EcsWorld`'s own
/// identity scheme, not a wrapper this file could add around it.
library;

import 'package:flutter3d_sim/flutter3d_sim.dart';
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart';

Level _withWallAt(double? wallX) => Level(
  brushes: <Brush>[
    Brush(centre: Vector3(0.0, -0.5, 0.0), size: Vector3(40.0, 1.0, 4.0)),
    if (wallX != null)
      Brush(centre: Vector3(wallX, 2.0, 0.0), size: Vector3(1.0, 6.0, 4.0)),
  ],
);

CollisionWorld _worldFrom(Level level) {
  final world = CollisionWorld();
  level.addTo(world);
  return world;
}

void main() {
  test(
    'a wall moved between two loads does not crash a restored run, and the '
    'run is stopped or not stopped by whichever wall is actually there',
    () {
      // The level as it was played: a wall at x=5 the runner cannot cross.
      final playedIn = _worldFrom(_withWallAt(5.0));
      var body = CharacterController(
        world: playedIn,
        position: Vector3(0.0, 1.0, 0.0),
      );
      const dt = 1.0 / 60.0;
      final forward = Vector3(1.0, 0.0, 0.0);
      for (var step = 0; step < 300; step++) {
        body.step(dt, wishDirection: forward);
        playedIn.update();
      }
      final stoppedAtWall = body.position.x;
      expect(
        stoppedAtWall,
        lessThan(5.0),
        reason: 'the wall should have stopped the runner before it',
      );
      expect(
        stoppedAtWall,
        greaterThan(3.5),
        reason: 'and the runner should have reached it, not started there',
      );
      final snapshot = Snapshot(body.save());

      // The level edited since: the wall moved out of the way entirely.
      final editedIn = _worldFrom(_withWallAt(null));
      body = CharacterController(world: editedIn, position: Vector3.zero());
      body.restore(snapshot.data);

      // The run continues — this must not throw, wherever the new geometry
      // puts the collider.
      for (var step = 0; step < 300; step++) {
        body.step(dt, wishDirection: forward);
        editedIn.update();
      }

      expect(
        body.position.x,
        greaterThan(stoppedAtWall + 1.0),
        reason:
            'the wall that stopped the original run is gone in the edited '
            'level, so the same forward input should carry the runner well '
            'past where it used to stop — proving the step reads the new '
            'geometry rather than the old collider or nothing at all',
      );
    },
  );

  test(
    'a wall newly placed under a restored runner is respected on the very '
    'next step',
    () {
      final playedIn = _worldFrom(_withWallAt(null));
      var body = CharacterController(
        world: playedIn,
        position: Vector3(0.0, 1.0, 0.0),
      );
      const dt = 1.0 / 60.0;
      final forward = Vector3(1.0, 0.0, 0.0);
      for (var step = 0; step < 120; step++) {
        body.step(dt, wishDirection: forward);
        playedIn.update();
      }
      final withoutWall = body.position.x;
      final snapshot = Snapshot(body.save());

      // Edited to add a wall a little ahead of where the run already is.
      final editedIn = _worldFrom(_withWallAt(withoutWall + 1.0));
      body = CharacterController(world: editedIn, position: Vector3.zero());
      body.restore(snapshot.data);

      for (var step = 0; step < 300; step++) {
        body.step(dt, wishDirection: forward);
        editedIn.update();
      }

      expect(
        body.position.x,
        lessThan(withoutWall + 1.0),
        reason: 'a wall placed in the edited level should stop the runner '
            'even though nothing in the snapshot ever knew it existed',
      );
    },
  );
}
