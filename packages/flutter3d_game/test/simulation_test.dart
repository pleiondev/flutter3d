/// The order of a step, and the state the game is in.
///
/// The first group is the reason this stage happened. Those five lines carried
/// comments about two bugs they prevent, in an application file with no tests,
/// for the whole life of the project. Both bugs look like physics faults and
/// neither is one; neither is visible in a screenshot; and both come back the
/// moment somebody moves a line while tidying up.
///
/// Both tests were written by permuting the order first and watching them go
/// red. The permutation is named in each.
library;

import 'package:flutter3d_game/src/actors/player.dart';
import 'package:flutter3d_game/src/combat/projectile.dart';
import 'package:flutter3d_game/src/input/game_action.dart';
import 'package:flutter3d_game/src/input/input_state.dart';
import 'package:flutter3d_game/src/loop/simulation.dart';
import 'package:flutter3d_game/src/physics/layers.dart';
import 'package:flutter3d_game/src/world/exit.dart';
import 'package:flutter3d_game/src/world/inventory.dart';
import 'package:flutter3d_game/src/world/mechanism.dart';
import 'package:flutter3d_game/src/world/mover.dart';
import 'package:flutter3d_game/src/world/signals.dart';
import 'package:flutter3d_physics/flutter3d_physics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

const double _dt = 1.0 / 60.0;

/// A floor twenty metres square with its top face at y = 0.
CollisionWorld _ground() {
  final world = CollisionWorld();
  world.addBox(Vector3(0.0, -0.5, 0.0), Vector3(20.0, 1.0, 20.0));
  return world;
}

({GameSimulation sim, Player player, InputState input, MechanismWorld mechanisms})
    _harness(
  CollisionWorld world, {
  Vector3? at,
  Inventory? inventory,
}) {
  final input = InputState();
  final player = Player(
    body: CharacterController(
      world: world,
      position: at ?? Vector3(0.0, 0.9, 0.0),
    ),
    inventory: inventory,
  );
  final mechanisms = MechanismWorld(world);
  world.update();
  return (
    sim: GameSimulation(
      player: player,
      collision: world,
      input: input,
      mechanisms: mechanisms,
      projectiles: ProjectileSystem(world: world),
    ),
    player: player,
    input: input,
    mechanisms: mechanisms,
  );
}

void main() {
  group('the order of a step', () {
    test('a platform that moves sideways takes its passenger with it', () {
      // Permutation: call `collision.clearKinematicDeltas()` before
      // `body.step` instead of after. This step's movement is erased before
      // the passenger is asked to ride it, and the platform slides out from
      // under them — which reads as the controller failing to detect ground.
      //
      // **Sideways, and that is the whole test.** The comment this replaces
      // said a *lift* that had not moved yet could not carry you, and that is
      // simply not true: a rising platform penetrates the capsule standing on
      // it and the controller pushes it out, upwards, whether or not the
      // kinematic delta was ever read. Measured, not assumed — a vertical
      // platform carries its passenger identically with the mutation applied.
      // Sideways there is no penetration to resolve, so the delta is the only
      // thing carrying anybody, and the mutation is caught.
      final world = _ground();
      final platform = world.add(
        Collider(
          shape: CollisionBox(Vector3(1.5, 0.25, 1.5)),
          position: Vector3(0.0, 0.25, 0.0),
          kind: ColliderKind.kinematic,
        ),
      );
      final h = _harness(world, at: Vector3(0.0, 1.4, 0.0));
      h.mechanisms.add(
        Platform(collider: platform, travel: Vector3(4.0, 0.0, 0.0), wait: 0.0),
      );

      // Settle, so the capsule is resting on the platform rather than falling
      // towards it.
      for (var i = 0; i < 20; i++) {
        h.sim.step(_dt);
      }
      final startedAt = h.player.body.position.x;
      final platformStartedAt = platform.position.x;

      for (var i = 0; i < 60; i++) {
        h.sim.step(_dt);
      }

      final carried = h.player.body.position.x - startedAt;
      final travelled = platform.position.x - platformStartedAt;
      expect(travelled, greaterThan(1.0), reason: 'the platform did move');
      expect(carried, closeTo(travelled, 0.05),
          reason: 'the passenger moved $carried while the floor under them '
              'moved $travelled');
    });

    test('a passenger is not an obstruction', () {
      // The bug the test above uncovered, and the larger of the two. A mover
      // refuses to move into a body — and a passenger standing on it overlaps
      // where it is about to be, every step, for ever. No lift in the
      // repository could move while anybody rode it.
      //
      // Mutation: treat any overlap as blocking, which is what the code did.
      // The platform never moves and this fails on its first expectation.
      final world = _ground();
      final platform = world.add(
        Collider(
          shape: CollisionBox(Vector3(1.5, 0.25, 1.5)),
          position: Vector3(0.0, 0.25, 0.0),
          kind: ColliderKind.kinematic,
        ),
      );
      final h = _harness(world, at: Vector3(0.0, 1.4, 0.0));
      final lift =
          Lift(collider: platform, travel: Vector3(0.0, 3.0, 0.0), wait: 0.0);
      h.mechanisms.add(lift);
      for (var i = 0; i < 20; i++) {
        h.sim.step(_dt);
      }

      lift.activate(const Activation());
      for (var i = 0; i < 60; i++) {
        h.sim.step(_dt);
      }

      expect(lift.progress, greaterThan(0.2),
          reason: 'the lift refused to move because somebody was on it');
      expect(h.player.body.position.y, greaterThan(1.9),
          reason: 'and it left without them');
    });
  });

  group('game state', () {
    test('starts playing', () {
      expect(_harness(_ground()).sim.state, GameState.playing);
    });

    test('a player whose health runs out is dead, once', () {
      final h = _harness(_ground());
      h.player.applyDamage(1000.0);
      h.sim.step(_dt);
      expect(h.sim.state, GameState.dead);

      h.sim.step(_dt);
      expect(h.sim.state, GameState.dead);
    });

    test('a dead player moves nothing, and the world keeps going', () {
      // The difference between dying and the game freezing. A corpse that can
      // still walk is the other half of the same bug.
      //
      // Mutation: drop the `playing` guard on the input. The corpse walks and
      // this fails.
      final world = _ground();
      final h = _harness(world);
      final platform = world.add(
        Collider(
          shape: CollisionBox(Vector3(1.0, 0.25, 1.0)),
          position: Vector3(6.0, 0.25, 0.0),
          kind: ColliderKind.kinematic,
        ),
      );
      h.mechanisms.add(
        Platform(collider: platform, travel: Vector3(0.0, 2.0, 0.0), wait: 0.0),
      );
      world.update();

      h.player.applyDamage(1000.0);
      h.sim.step(_dt);
      final restedAt = h.player.body.position.clone();
      final platformAt = platform.position.y;

      h.input
        ..setStickAxis(1.0, 1.0)
        ..press(GameAction.jump);
      for (var i = 0; i < 60; i++) {
        h.sim.step(_dt);
      }

      expect(h.player.body.position.x, closeTo(restedAt.x, 1e-3));
      expect(h.player.body.position.z, closeTo(restedAt.z, 1e-3));
      expect(platform.position.y, greaterThan(platformAt + 0.5),
          reason: 'the level stopped when the player did');
    });

    test('a dead player cannot look around either', () {
      final h = _harness(_ground());
      h.player.applyDamage(1000.0);
      h.sim.step(_dt);

      final facing = h.player.yaw;
      h.input.addLook(500.0, 0.0);
      h.sim.step(_dt);
      expect(h.player.yaw, facing);
    });
  });

  group('the way out', () {
    Exit exitIn(CollisionWorld world, MechanismWorld mechanisms,
        {String? next, String? key}) {
      final exit = Exit(
        name: 'out',
        collider: world.add(
          Collider(
            shape: CollisionBox(Vector3(0.75, 1.25, 0.75)),
            position: Vector3(0.0, 1.0, -3.0),
            kind: ColliderKind.trigger,
            layer: CollisionLayers.trigger,
            mask: CollisionLayers.player,
          ),
        ),
        next: next,
        key: key,
      );
      mechanisms.add(exit);
      world.update();
      return exit;
    }

    test('walking into it finishes the level', () {
      // `ExitKind` used to spawn nothing at all, which made `exit` the one word
      // in the level vocabulary a document could contain and the game could not
      // act on.
      final world = _ground();
      final h = _harness(world);
      exitIn(world, h.mechanisms);

      h.input.setStickAxis(0.0, 1.0);
      for (var i = 0; i < 120 && h.sim.state == GameState.playing; i++) {
        h.sim.step(_dt);
      }

      expect(h.sim.state, GameState.complete);
    });

    test('an exit names where to go next, over the level', () {
      // `Level.next` was a field nothing read. It is the default now, and an
      // exit's own answer wins — which is what lets a level with two doors lead
      // to two places.
      final world = _ground();
      final input = InputState();
      final player = Player(
        body: CharacterController(world: world, position: Vector3(0.0, 0.9, 0.0)),
      );
      final mechanisms = MechanismWorld(world);
      final sim = GameSimulation(
        player: player,
        collision: world,
        input: input,
        mechanisms: mechanisms,
        levelNext: 'crypt2.json',
      );
      world.update();
      expect(sim.nextLevel, 'crypt2.json', reason: 'the level has an answer');

      exitIn(world, mechanisms, next: 'cellar.json');
      input.setStickAxis(0.0, 1.0);
      for (var i = 0; i < 120 && sim.state == GameState.playing; i++) {
        sim.step(_dt);
      }

      expect(sim.state, GameState.complete);
      expect(sim.nextLevel, 'cellar.json');
    });

    test('a locked exit is not a way out', () {
      // Mutation: drop the key check in `Exit.activate`. This fails.
      final world = _ground();
      final h = _harness(world);
      exitIn(world, h.mechanisms, key: 'brass');

      h.input.setStickAxis(0.0, 1.0);
      for (var i = 0; i < 120; i++) {
        h.sim.step(_dt);
      }
      expect(h.sim.state, GameState.playing);
    });

    test('an exit switched on by something else finishes the level too', () {
      // The reason an exit is a `Mechanism` rather than something the
      // simulation watches for: it inherits being switchable by anything else,
      // and the level ends the same way whichever route reached it.
      final world = _ground();
      final h = _harness(world);
      final exit = exitIn(world, h.mechanisms);
      h.mechanisms.add(
        TriggerVolume(
          target: 'out',
          collider: world.add(
            Collider(
              shape: CollisionBox(Vector3(1.0, 1.25, 0.5)),
              position: Vector3(0.0, 1.0, 4.0),
              kind: ColliderKind.trigger,
              layer: CollisionLayers.trigger,
              mask: CollisionLayers.player,
            ),
          ),
        ),
      );
      world.update();

      // Away from the exit, into the trigger.
      h.input.setStickAxis(0.0, -1.0);
      for (var i = 0; i < 200 && h.sim.state == GameState.playing; i++) {
        h.sim.step(_dt);
      }

      expect(exit.isReached, isTrue,
          reason: 'the player never touched the exit itself');
      expect(h.sim.state, GameState.complete);
    });
  });
}

