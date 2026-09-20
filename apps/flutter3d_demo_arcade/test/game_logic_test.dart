/// The game logic underneath the picture, exercised the way
/// `packages/flutter3d_flame/test/*.dart` exercises the bridges themselves:
/// real objects, `.update(dt)` called directly, no widget tree anywhere.
library;

import 'package:flutter3d/flutter3d.dart' hide Material;
import 'package:flutter3d_cpu/testing.dart';
import 'package:flutter3d_demo_arcade/src/arcade_game.dart';
import 'package:flutter3d_sim/flutter3d_sim.dart';
import 'package:flutter_test/flutter_test.dart';

/// A fresh [ArcadeGame] with its world already built, on a CPU device so the
/// meshes have something to upload their geometry to.
ArcadeGame _newGame() {
  final it = cpuTestDevice(width: 32, height: 24);
  final game = ArcadeGame();
  game.spawnWorld(it.device, Scene());
  return game;
}

/// Advances [game] by [steps] sixtieths of a second, the way `GameWidget`
/// would tick it every frame.
void _run(ArcadeGame game, int steps) {
  for (var i = 0; i < steps; i++) {
    game.update(1 / 60);
  }
}

void main() {
  test('spawnWorld wires the ship and three drones into one collision '
      'world', () {
    final game = _newGame();

    expect(game.drones, hasLength(3));
    expect(game.ship.body.collider.world, same(game.collisionWorld));
    for (final drone in game.drones) {
      expect(drone.actor.body!.collider.world, same(game.collisionWorld));
    }
  });

  test('holding forward moves the ship through Dynamics, not by hand', () {
    final game = _newGame();
    final startZ = game.ship.body.position.z;

    game.inputState.press(GameAction.moveForward);
    _run(game, 30);

    // Real movement through `Dynamics.step`: the body's own position moved,
    // and the Flame side and the scene node both followed it — proof the
    // transform bridge (`Object3dComponent.update`, which `RigidBodyComponent`
    // extends) actually ran, not just the physics.
    expect(game.ship.body.position.z, greaterThan(startZ));
    expect(
      game.ship.position,
      ArcadeGame.groundPlane.to2d(game.ship.body.position),
    );
  });

  test('a drone patrols under the actor system, not an animation', () {
    final game = _newGame();
    final drone = game.drones.first;
    final startX = drone.actor.body!.position.x;

    _run(game, 90);

    // `ActorSystemComponent.update` is what calls `ActorSystem.step`, which
    // is what calls `PatrolBrain.act`; nothing in this test moves the body
    // directly, so any movement at all is the actor system's own doing.
    expect(drone.actor.body!.position.x, isNot(closeTo(startX, 1e-9)));
  });

  test('a contact with a drone hits the ship, once, through the bridge', () {
    final game = _newGame();
    final drone = game.drones.first;
    final droneBody = drone.actor.body!;

    // Put the ship exactly where the drone already is, the same way
    // `packages/flutter3d_flame/test/collision_bridge_test.dart` places two
    // real colliders on top of each other before asking the world to notice.
    // Dispatched directly, rather than through a full `game.update` frame:
    // a full frame also steps the actor system, whose own
    // `CharacterController.step` would immediately depenetrate a drone
    // planted exactly inside another solid body, shoving it away before the
    // world ever gets to notice the contact this test is asking about.
    game.ship.body.collider
      ..position.setFrom(droneBody.position)
      ..refreshBounds();
    game.collisionWorld.update();

    expect(game.hits, 1);
    expect(game.drones, hasLength(2));
    expect(game.drones, isNot(contains(drone)));
  });

  test('the ship blinks for a while after a hit, then stops', () {
    final game = _newGame();
    game.ship.flash();

    var sawHidden = false;
    for (var i = 0; i < 40; i++) {
      game.ship.update(1 / 60);
      if (!game.ship.node.visible) sawHidden = true;
    }

    expect(sawHidden, isTrue, reason: 'the ship never blinked');
    expect(game.ship.node.visible, isTrue, reason: 'the blink never ended');
  });

  test('three hits end the run and stop stepping the world', () {
    final game = _newGame();

    for (var i = 0; i < ArcadeGame.maxHits; i++) {
      final drone = game.drones.first;
      game.ship.body.collider
        ..position.setFrom(drone.actor.body!.position)
        ..refreshBounds();
      game.collisionWorld.update();
    }

    expect(game.gameOver, isTrue);
    expect(game.hits, ArcadeGame.maxHits);

    // The ship no longer moves, even while the input is held: `update` zeros
    // the velocity once the run is over rather than reading the axis. This
    // also drains the three queued removals — see `ArcadeGame._drainHits` —
    // through a real frame, the same as a live game would.
    game.inputState.press(GameAction.moveForward);
    final z = game.ship.body.position.z;
    _run(game, 30);
    expect(game.ship.body.position.z, closeTo(z, 1e-9));
  });
}
