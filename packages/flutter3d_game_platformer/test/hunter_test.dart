/// An enemy that crosses a pit to get to the player.
///
///     flutter test test/hunter_test.dart
///
/// The first enemy in this game that asks the level for a route, and the
/// reason jump links exist: a patrol holds its own posts and a leaper jumps
/// the gaps in them, but neither can go where the player *is* across a level
/// made of platforms. This runs the real body over a real pit and asks
/// whether it arrived — and, as the control, whether it stayed put on a grid
/// baked without any reach, which is what every level had before.
library;

import 'package:flutter3d_game/flutter3d_game.dart';
import 'package:flutter3d_game_platformer/flutter3d_game_platformer.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

const double _dt = 1.0 / 60.0;

Brush _slab(double x0, double x1) => Brush(
  centre: Vector3((x0 + x1) / 2, -0.5, 0.0),
  size: Vector3(x1 - x0, 1.0, 8.0),
);

/// Platform A from −10 to 0, a three-metre pit, platform B from 3 to 13.
///
/// A body running off the edge at six metres a second covers about two and
/// a half before it is below the far lip, so three is the pit that tells a
/// jump from a fall. The hunter jumps at nine metres a second: four and a
/// half metres of reach at the same height, less its own width, is what
/// three metres of pit plus half a cell each side needs.
Level _pit() =>
    Level(name: 'a pit', brushes: <Brush>[_slab(-10.0, 0.0), _slab(3.0, 13.0)]);

const MovementTuning _legs = MovementTuning(jumpSpeed: 9.0);

CharacterController _body(CollisionWorld world, double x) =>
    CharacterController(
      world: world,
      shape: CollisionBox(Vector3(0.35, 0.35, 0.35)),
      position: Vector3(x, 0.35, 0.0),
      layer: CollisionLayers.actor,
      tuning: _legs,
    );

void main() {
  test('a hunter jumps the pit and reaches the player', () {
    final world = CollisionWorld();
    final level = _pit()..addTo(world);
    final actors = ActorSystem(world: world, random: GameRandom(1))
      ..navigation = Navigation.bake(level, jumps: JumpReach.of(_legs));
    final body = _body(world, -6.0);
    // Fourteen metres and a bit: the default sight would miss by the height
    // difference, and the test is about the pit rather than the eyesight.
    final hunter = Hunter(sight: 20.0);
    actors.spawn(
      body: body,
      health: Health(20.0),
      facing: Facing(),
      brain: hunter,
    );
    final player = Vector3(8.0, 0.9, 0.0);

    var airborne = false;
    var arrived = false;
    for (var step = 0; step < 60 * 8 && !arrived; step++) {
      world.update();
      actors.beginStep();
      actors.step(_dt, focus: player);
      if (!body.isGrounded) airborne = true;
      if ((body.position - player).xz.length < 1.5) arrived = true;
    }

    expect(hunter.hunting, isTrue, reason: 'it never saw the player');
    expect(airborne, isTrue, reason: 'it never left the ground');
    expect(arrived, isTrue, reason: 'it ended at x = ${body.position.x}');
    expect(body.position.y, greaterThan(-1.0), reason: 'it fell in the pit');
  });

  test('on a grid baked without a reach it stops at the edge', () {
    final world = CollisionWorld();
    final level = _pit()..addTo(world);
    final actors = ActorSystem(world: world, random: GameRandom(1))
      ..navigation = Navigation.bake(level);
    final body = _body(world, -6.0);
    actors.spawn(
      body: body,
      health: Health(20.0),
      facing: Facing(),
      brain: Hunter(sight: 20.0),
    );
    final player = Vector3(8.0, 0.9, 0.0);

    var airborne = false;
    for (var step = 0; step < 60 * 4; step++) {
      world.update();
      actors.beginStep();
      actors.step(_dt, focus: player);
      if (!body.isGrounded) airborne = true;
    }

    // Without a route the brain walks straight at the player, which is off
    // the edge: the pit is where the old behaviour ends up, and that is the
    // difference the links make. Only the height is asked, because a pit with
    // no bottom is a body still steering through the air on the way down.
    expect(airborne, isTrue);
    expect(body.position.y, lessThan(-1.0), reason: 'it did not fall in');
  });

  test('a hunter forgets a player it cannot see', () {
    final hunter = Hunter(sight: 5.0, patience: 0.5);
    final world = CollisionWorld();
    final level = Level(
      brushes: <Brush>[
        _slab(-10.0, 10.0),
        // A wall between them.
        Brush(centre: Vector3(0.0, 1.5, 0.0), size: Vector3(0.5, 3.0, 8.0)),
      ],
    )..addTo(world);
    final actors = ActorSystem(world: world, random: GameRandom(1))
      ..navigation = Navigation.bake(level);
    final body = _body(world, -3.0);
    actors.spawn(
      body: body,
      health: Health(20.0),
      facing: Facing(),
      brain: hunter,
    );

    for (var step = 0; step < 60; step++) {
      world.update();
      actors.beginStep();
      actors.step(_dt, focus: Vector3(3.0, 0.9, 0.0));
    }

    expect(hunter.hunting, isFalse, reason: 'it saw through a wall');
    expect(body.position.x, closeTo(-3.0, 0.05), reason: 'it moved unseen');
  });
}
