/// Rigid bodies where a game can reach them.
///
/// Stage one of the physics exists in `flutter3d_physics` and was tested there
/// against the specification's numbers. This is the other half of making it
/// real: a crate in a level, stepped in the right place in the simulation's
/// order, pushed by a player who walks into it, and carried in the snapshot
/// with everything else.
library;

import 'package:flutter3d_game/flutter3d_game.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

const double _dt = 1.0 / 60.0;

final class _Room {
  _Room() {
    world.addBox(Vector3(0.0, -0.5, 0.0), Vector3(40.0, 1.0, 40.0));
    world.update();
    player = Player(
      body: CharacterController(world: world, position: Vector3(0.0, 0.9, 2.0)),
    );
    crate = dynamics.add(
      RigidBody(
        world: world,
        shape: CollisionBox(Vector3.all(0.35)),
        position: Vector3(0.0, 0.35, 0.0),
        mass: 20.0,
      ),
    );
    registerActorComponents(entities);
    entities.set(entities.spawn(), Physical(crate));
    sim = GameSimulation(
      player: player,
      collision: world,
      input: input,
      dynamics: dynamics,
    );
    world.update();
  }

  final CollisionWorld world = CollisionWorld();
  final EcsWorld entities = EcsWorld();
  late final Dynamics dynamics = Dynamics(world: world);
  late final Player player;
  late final RigidBody crate;
  late final GameSimulation sim;
  final InputState input = InputState();

  void walk(int steps, {double x = 0.0, double z = 0.0}) {
    for (var i = 0; i < steps; i++) {
      input.setStickAxis(x, z);
      sim.step(_dt);
      input.endStep();
    }
  }
}

void main() {
  test('a crate falls and rests while the simulation runs it', () {
    final room = _Room()..walk(120);
    expect(room.crate.position.y, closeTo(0.35, 0.01));
    expect(room.crate.isAsleep, isTrue);
  });

  test('walking into a crate pushes it', () {
    // The specification's acceptance for stage one, in a game rather than in a
    // physics test: a crate a player can shove.
    //
    // Mutation: drop the `dynamics.push` call in the step. The player walks
    // into the crate, is stopped by it, and it never moves — which is what a
    // kinematic character controller does on its own and why the transfer has
    // to be explicit.
    final room = _Room()..walk(60);
    final restedAt = room.crate.position.z;

    room.walk(180, z: 1.0);

    expect(room.crate.position.z, lessThan(restedAt - 0.5),
        reason: 'the player walked into it and it did not move');
    expect(room.player.body.position.z, greaterThan(room.crate.position.z),
        reason: 'the player ended up inside the crate');
  });

  test('a crate does not push back', () {
    // The other half: a body may be shoved and may not shove. A player who is
    // slowed by walking into a crate is a player fighting the scenery.
    final room = _Room()..walk(60);
    final before = room.player.body.position.clone();
    // Forward is −Z, so a negative axis walks away from the crate at the
    // origin rather than towards it.
    room.walk(60, z: -1.0);
    expect(room.player.body.position.z, greaterThan(before.z + 1.0),
        reason: 'walking away from the crate was somehow impeded');
  });

  test('standing still does not nudge it', () {
    final room = _Room()..walk(120);
    final restedAt = room.crate.position.clone();
    room.walk(120);
    expect((room.crate.position - restedAt).length, lessThan(1e-4));
  });

  test('the snapshot carries it', () {
    // `Physical` is a component, so `EcsWorld.save()` writes it and refuses to
    // write the next one nobody registered.
    final room = _Room()..walk(60);
    room.walk(60, z: 1.0);

    final saved = room.entities.save();
    final wasAt = room.crate.position.clone();

    room.walk(120, z: 1.0);
    expect(room.crate.position.z, isNot(wasAt.z));

    room.entities.restore(saved);
    expect(room.crate.position.z, closeTo(wasAt.z, 1e-6));
  });
}
