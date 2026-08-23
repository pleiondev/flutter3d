/// The order the world is stepped in, and the two things that go wrong when it
/// is not.
///
///     flutter test test/world_step_test.dart
///
/// **`WorldStep` had no test in the package that holds it.** SPEC §3.3 asked for
/// two — the order moved out of three games and into one class, and its tests
/// did not come with it. What kept it honest was a single line in
/// `flutter3d_game_shooter/test/simulation_test.dart`, which is a test of a
/// shooter that happens to notice; delete this class and rewrite it wrongly and
/// only the other package would say so.
///
/// The class's own doc names exactly two claims a test can catch, and they are
/// the two here. The third ordering it documents — `reindex` before the bodies —
/// says plainly that it is argument rather than measurement, so nothing here
/// pretends otherwise.
library;

import 'package:flutter3d_game/flutter3d_game.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

const double _dt = 1.0 / 60.0;

/// A platform that slides sideways, and the step that drives it.
({
  WorldStep step,
  CollisionWorld world,
  MovingPlatform platform,
}) _worldWithASlidingPlatform() {
  final world = CollisionWorld();
  final mechanisms = MechanismWorld(world);

  final platform = mechanisms.add(
    MovingPlatform(
      collider: world.add(
        Collider(
          shape: CollisionBox(Vector3(1.5, 0.125, 1.5)),
          position: Vector3(0.0, 1.0, 0.0),
          kind: ColliderKind.kinematic,
        ),
      ),
      // Sideways on purpose. A *rising* lift carries its passenger whether or
      // not anything reads the delta — it penetrates the capsule and the
      // controller pushes it out, upwards — so a vertical platform proves
      // nothing about the ordering this file is here for.
      travel: Vector3(8.0, 0.0, 0.0),
      speed: 2.0,
      wait: 0.0,
    ),
  );

  world.update();
  return (
    step: WorldStep(collision: world, mechanisms: mechanisms),
    world: world,
    platform: platform,
  );
}

void main() {
  test('a rider is carried by a platform that moved this step', () {
    // **The one ordering here that a test will catch**, in the class's own
    // words. A platform moving *sideways* carries whatever stands on it only
    // through the kinematic delta, and the delta is cleared at the end of
    // `settle` — after the game's bodies have read it.
    //
    // Mutation: call `collision.clearKinematicDeltas()` inside `index` instead,
    // before the bodies move. The rider is then left standing while the floor
    // departs.
    final it = _worldWithASlidingPlatform();

    var offered = 0.0;
    for (var i = 0; i < 30; i++) {
      it.step.movers(_dt);
      it.step.index(_dt);

      // Where a character controller reads it: after the movers have moved and
      // before `settle` clears it. This is the whole window, and `settle` is
      // what closes it.
      offered += it.platform.collider.delta.x;

      it.step.settle();
      it.step.publish();
    }

    expect(it.platform.collider.position.x, greaterThan(0.5),
        reason: 'the platform did not move, so this test proves nothing');
    expect(offered, closeTo(it.platform.collider.position.x, 1e-6),
        reason: 'a passenger was offered less of the platform\'s travel than '
            'the platform made — the delta was cleared before anything read it');
  });

  test('and the delta is gone once the step has settled', () {
    // The other end of the same window, and the reason `settle` clears at all:
    // a delta that survived its step would carry a passenger twice.
    //
    // Mutation: drop `clearKinematicDeltas()` from `settle`.
    final it = _worldWithASlidingPlatform();

    it.step.movers(_dt);
    it.step.index(_dt);
    expect(it.platform.collider.delta.x, greaterThan(0.0),
        reason: 'nothing moved, so the next assertion proves nothing');

    it.step.settle();
    expect(it.platform.collider.delta.x, 0.0);
    it.step.publish();
  });

  test('and a step that never publishes is caught rather than shipped', () {
    // **This shipped.** `PlatformerSimulation.step` moved its mechanisms and
    // never published them, so nothing a mechanism did was ever reported: no
    // sound on a coin, no message, no gate. The purse still filled, which is why
    // it went unnoticed, and no test could see it because every test read the
    // simulation rather than what the simulation announced.
    //
    // Mutation: delete the assert in `movers`, and the second step below runs
    // happily with the first step's events still unread.
    final it = _worldWithASlidingPlatform();

    it.step.movers(_dt);
    it.step.index(_dt);
    it.step.settle();
    // No publish().

    expect(
      () => it.step.movers(_dt),
      throwsA(isA<StateError>().having(
        (StateError e) => e.message,
        'message',
        contains('never reached publish'),
      )),
    );
  });

  test('and a world with no machinery owes nothing', () {
    // The other direction: the guard must not fire for a game that has no
    // mechanisms at all, which is every bare-physics harness in this repository.
    final step = WorldStep(collision: CollisionWorld());

    for (var i = 0; i < 3; i++) {
      step.movers(_dt);
      step.index(_dt);
      step.settle();
    }

    expect(true, isTrue, reason: 'reaching here without throwing is the test');
  });
}
