/// The game logic underneath the picture, exercised the way
/// `packages/flame_flutter3d/test/*.dart` exercises the bridges themselves:
/// real objects, `.update(dt)` called directly, no widget tree anywhere.
library;

import 'package:flame_flutter3d/flame_flutter3d.dart' show ActorComponent;
import 'package:flutter3d/flutter3d.dart' hide Material;
import 'package:flutter3d_cpu/testing.dart';
import 'package:flutter3d_demo_arcade/src/arcade_game.dart';
import 'package:flutter3d_sim/flutter3d_sim.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart' show Vector3;

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
  test('spawnWorld wires the ship and three bots into one collision '
      'world', () {
    final game = _newGame();

    expect(game.bots, hasLength(3));
    expect(game.ship.body.collider.world, same(game.collisionWorld));
    for (final bot in game.bots) {
      expect(bot.actor.body!.collider.world, same(game.collisionWorld));
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
    // Forward is up the screen, which the top-down camera shows as -Z.
    expect(game.ship.body.position.z, lessThan(startZ));
    expect(
      game.ship.position,
      ArcadeGame.groundPlane.to2d(game.ship.body.position),
    );
  });

  test('a bot patrols under the actor system, not an animation', () {
    final game = _newGame();
    final bot = game.bots.first;
    final startX = bot.actor.body!.position.x;

    _run(game, 90);

    // `ActorSystemComponent.update` is what calls `ActorSystem.step`, which
    // is what calls `PatrolBrain.act`; nothing in this test moves the body
    // directly, so any movement at all is the actor system's own doing.
    expect(bot.actor.body!.position.x, isNot(closeTo(startX, 1e-9)));
  });

  test('a bot running into a still ship hits it, through the bridge, '
      'and flies on', () {
    final game = _newGame();
    final bot = game.bots.first;

    // Put the ship exactly where the bot already is, the same way
    // `packages/flame_flutter3d/test/collision_bridge_test.dart` places two
    // real colliders on top of each other before asking the world to notice.
    // Dispatched directly, rather than through a full `game.update` frame:
    // a full frame also steps the actor system, whose own
    // `CharacterController.step` would immediately depenetrate a bot
    // planted exactly inside another solid body, shoving it away before the
    // world ever gets to notice the contact this test is asking about.
    _touch(game, bot);

    expect(game.hits, 1);
    expect(game.rammed, 0);
    expect(game.bots, contains(bot));
    expect(game.ship.isFlashing, isTrue);
  });

  test('a ship flying at a bot rams it, and takes no hit', () {
    final game = _newGame();
    final bot = game.bots.first;

    // Flying up the screen, towards -Z, with the bot just ahead of it.
    game.shipHeading.setValues(0.0, 0.0, -ArcadeGame.shipSpeed);
    _touch(game, bot, offset: Vector3(0.0, 0.0, 0.3));

    expect(game.hits, 0);
    expect(game.rammed, 1);
    expect(game.bots, isNot(contains(bot)));
  });

  test('a ship flying past a bot is struck, not ramming', () {
    final game = _newGame();
    final bot = game.bots.first;

    // Flying sideways, with the bot ahead along -Z: more than 60 degrees
    // off the line of flight.
    game.shipHeading.setValues(ArcadeGame.shipSpeed, 0.0, 0.0);
    _touch(game, bot, offset: Vector3(0.0, 0.0, 0.3));

    expect(game.hits, 1);
    expect(game.bots, contains(bot));
  });

  test('a hunter that catches a still ship hits it, frame by frame', () {
    // Through whole frames, the way the game runs: the bot's sweep stops
    // it at the hull and never inside, so only the sensor can hear this.
    // Mutation: bridge the hull's own collider instead, and the hunter sits
    // on the ship with no hit at all.
    final game = _newGame()..startLevel(1);
    final hunter = game.bots.first;
    expect(arcadeLevels[1].hunters, greaterThan(0));
    game.ship.body.position.setFrom(
      hunter.actor.body!.position + Vector3(2.5, -0.1, 0.0),
    );

    _run(game, 120);

    expect(game.hits, greaterThanOrEqualTo(1));
    expect(game.bots, contains(hunter));
  });

  test('a blinking ship is not hit again by the same brush', () {
    final game = _newGame();
    _touch(game, game.bots[0]);
    _touch(game, game.bots[1]);

    expect(game.hits, 1);
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

  test("the level's hits end it and stop stepping the world", () {
    final game = _newGame();
    _loseLevel(game);

    expect(game.gameOver, isTrue);
    expect(game.hits, game.maxHits);

    // The ship no longer moves, even while the input is held: `update` zeros
    // the velocity once the level is lost rather than reading the axis.
    game.inputState.press(GameAction.moveForward);
    final z = game.ship.body.position.z;
    _run(game, 30);
    expect(game.ship.body.position.z, closeTo(z, 1e-9));
  });

  test('retrying a lost level plays it again from the start', () {
    final game = _newGame();
    _loseLevel(game);

    game.retry();
    _run(game, 1);

    expect(game.gameOver, isFalse);
    expect(game.levelIndex, 0);
    expect(game.hits, 0);
    expect(game.bots, hasLength(arcadeLevels.first.bots));
    // Stepping again: the bots walk.
    final x = game.bots.first.actor.body!.position.x;
    _run(game, 30);
    expect(game.bots.first.actor.body!.position.x, isNot(closeTo(x, 1e-9)));
  });

  test('clearing a level starts the next, harder one after a pause', () {
    final game = _newGame();
    _clearLevel(game);
    _run(game, 1);

    expect(game.levelCleared, isTrue);
    expect(game.cleared, isFalse);
    expect(game.levelIndex, 0, reason: 'the next level waits for the pause');

    _run(game, (ArcadeGame.levelPause * 60).ceil() + 1);

    expect(game.levelIndex, 1);
    expect(game.hits, 0);
    expect(game.bots, hasLength(arcadeLevels[1].bots));
    expect(arcadeLevels[1].bots, greaterThan(arcadeLevels[0].bots));
  });

  test('the levels only ever get harder', () {
    for (var i = 1; i < arcadeLevels.length; i++) {
      final (easier, harder) = (arcadeLevels[i - 1], arcadeLevels[i]);
      expect(harder.bots, greaterThanOrEqualTo(easier.bots));
      expect(harder.botSpeed, greaterThan(easier.botSpeed));
      expect(harder.hunters, greaterThanOrEqualTo(easier.hunters));
      expect(harder.maxHits, lessThanOrEqualTo(easier.maxHits));
      // A hunter the ship cannot outrun can never be rammed.
      expect(harder.botSpeed, lessThan(ArcadeGame.shipSpeed));
    }
  });

  test('clearing the last level wins the run', () {
    final game = _newGame();
    for (var i = 0; i < arcadeLevels.length; i++) {
      expect(game.levelIndex, i);
      _clearLevel(game);
      _run(game, (ArcadeGame.levelPause * 60).ceil() + 2);
    }
    expect(game.cleared, isTrue);
    expect(game.levelIndex, arcadeLevels.length - 1);
  });
}

/// Puts the ship's sensor on [bot], [offset] from it, and has the world
/// notice — see the first contact test for why the world is updated directly
/// rather than through a frame, and [ArcadeGame.shipSensor] for why it is
/// the sensor that reports a bot and not the hull.
void _touch(ArcadeGame game, ActorComponent bot, {Vector3? offset}) {
  final at = bot.actor.body!.position.clone();
  if (offset != null) at.add(offset);
  game.shipSensor
    ..position.setFrom(at)
    ..refreshBounds();
  game.collisionWorld.update();
  // Apart again, so the next touch is a new contact rather than this one
  // carrying on.
  game.shipSensor
    ..position.setValues(0.0, 1.2, 100.0)
    ..refreshBounds();
  game.collisionWorld.update();
}

/// Takes the level's hits, one bot each, letting the blink run out
/// between them.
void _loseLevel(ArcadeGame game) {
  for (var i = 0; i < game.maxHits; i++) {
    _touch(game, game.bots[i % game.bots.length]);
    game.ship.update(1.0);
  }
}

/// Rams every bot of the level, flying at each from just behind it.
void _clearLevel(ArcadeGame game) {
  game.shipHeading.setValues(0.0, 0.0, -ArcadeGame.shipSpeed);
  for (final bot in List<ActorComponent>.of(game.bots)) {
    _touch(game, bot, offset: Vector3(0.0, 0.0, 0.3));
  }
}
