import 'dart:math' as math;

import 'package:flutter3d_physics/flutter3d_physics.dart';
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart';

const double _dt = 1.0 / 60.0;

/// Half the player: 0.7 m across, 1.8 m tall.
final Vector3 _playerHalf = Vector3(0.35, 0.9, 0.35);

/// A floor at y = 0 with walls around it.
CollisionWorld _room({double size = 20.0, bool walls = true}) {
  final world = CollisionWorld();
  world.addBox(Vector3(0.0, -0.5, 0.0), Vector3(size, 1.0, size));
  if (walls) {
    final half = size / 2.0;
    world.addBox(Vector3(half, 2.0, 0.0), Vector3(1.0, 4.0, size));
    world.addBox(Vector3(-half, 2.0, 0.0), Vector3(1.0, 4.0, size));
    world.addBox(Vector3(0.0, 2.0, half), Vector3(size, 4.0, 1.0));
    world.addBox(Vector3(0.0, 2.0, -half), Vector3(size, 4.0, 1.0));
  }
  return world;
}

CharacterController _player(CollisionWorld world, {Vector3? at}) =>
    CharacterController(
      world: world,
      shape: CollisionBox(_playerHalf),
      position: at ?? Vector3(0.0, 0.9, 0.0),
    );

/// Runs [steps] steps, walking in [direction].
void _walk(
  CharacterController player,
  int steps, {
  Vector3? direction,
  bool sprint = false,
}) {
  final wish = direction ?? Vector3.zero();
  for (var i = 0; i < steps; i++) {
    player.step(_dt, wishDirection: wish, sprint: sprint);
    player.world.update();
  }
}

void main() {
  group('walking', () {
    test('settles onto the floor and stays there', () {
      final world = _room();
      final player = _player(world, at: Vector3(0.0, 3.0, 0.0));

      _walk(player, 120);

      expect(player.isGrounded, isTrue);
      // The box is 1.8 m tall, so its centre rests at 0.9 above the floor.
      expect(player.position.y, closeTo(0.9, 0.02));
    });

    test('walks forward and gets somewhere', () {
      final world = _room();
      final player = _player(world);
      _walk(player, 30);

      _walk(player, 60, direction: Vector3(0.0, 0.0, -1.0));

      expect(player.position.z, lessThan(-3.0));
      expect(player.position.x, closeTo(0.0, 1e-6));
    });

    test('stops at a wall instead of passing through it', () {
      final world = _room(size: 10.0);
      final player = _player(world);
      _walk(player, 30);

      _walk(player, 300, direction: Vector3(0.0, 0.0, -1.0), sprint: true);

      // The inner face of the far wall is at z = -4.5; the player's half-depth
      // keeps their centre 0.35 short of it.
      expect(player.position.z, greaterThan(-4.9));
      expect(player.position.z, lessThan(-4.0));
    });

    test('slides along a wall met at an angle', () {
      final world = _room(size: 10.0);
      final player = _player(world);
      _walk(player, 30);

      final start = player.position.x;
      // Into the far wall at 45 degrees: blocked in z, free in x.
      _walk(player, 120, direction: Vector3(1.0, 0.0, -1.0)..normalize());

      expect(player.position.x, greaterThan(start + 2.0));
    });

    test('a corner neither traps nor ejects', () {
      final world = _room(size: 10.0);
      final player = _player(world);
      _walk(player, 30);

      _walk(player, 400, direction: Vector3(1.0, 0.0, -1.0)..normalize());

      // Wedged into the corner and still inside the room.
      expect(player.position.x, lessThan(4.9));
      expect(player.position.z, greaterThan(-4.9));
      expect(player.position.x, greaterThan(3.5));
      expect(player.position.z, lessThan(-3.5));
    });

    test('a gap narrower than the player does not let them through', () {
      final world = _room();
      // Two blocks leaving a 0.5 m slot, against a 0.7 m player.
      world.addBox(Vector3(1.0, 2.0, -3.0), Vector3(1.5, 4.0, 1.0));
      world.addBox(Vector3(-1.0, 2.0, -3.0), Vector3(1.5, 4.0, 1.0));

      final player = _player(world);
      _walk(player, 30);
      _walk(player, 300, direction: Vector3(0.0, 0.0, -1.0), sprint: true);

      expect(player.position.z, greaterThan(-2.5));
    });

    test('diagonal movement is not faster than straight movement', () {
      final world = _room(size: 200.0, walls: false);
      final straight = _player(world);
      _walk(straight, 30);
      _walk(straight, 120, direction: Vector3(0.0, 0.0, -1.0));
      final straightDistance = straight.position.z.abs();

      final diagonal = _player(world, at: Vector3(50.0, 0.9, 0.0));
      _walk(diagonal, 30);
      _walk(diagonal, 120, direction: Vector3(1.0, 0.0, -1.0)..normalize());
      final dx = diagonal.position.x - 50.0;
      final dz = diagonal.position.z;
      final diagonalDistance = math.sqrt(dx * dx + dz * dz);

      expect(diagonalDistance, closeTo(straightDistance, 0.1));
    });

    test('sprinting is faster than walking', () {
      final world = _room(size: 200.0, walls: false);
      final walker = _player(world);
      _walk(walker, 30);
      _walk(walker, 120, direction: Vector3(0.0, 0.0, -1.0));

      final runner = _player(world, at: Vector3(50.0, 0.9, 0.0));
      _walk(runner, 30);
      _walk(runner, 120, direction: Vector3(0.0, 0.0, -1.0), sprint: true);

      expect(runner.position.z.abs(), greaterThan(walker.position.z.abs() + 3));
    });
  });

  group('inertia', () {
    test('speed builds up rather than appearing at once', () {
      final world = _room(size: 200.0, walls: false);
      final player = _player(world);
      _walk(player, 30);

      player.step(_dt, wishDirection: Vector3(0.0, 0.0, -1.0));
      final afterOne = player.velocity.z.abs();

      _walk(player, 30, direction: Vector3(0.0, 0.0, -1.0));
      final atSpeed = player.velocity.z.abs();

      expect(afterOne, lessThan(atSpeed * 0.5));
      expect(atSpeed, closeTo(6.0, 0.2));
    });

    test('letting go brings the player to a stop', () {
      final world = _room(size: 200.0, walls: false);
      final player = _player(world);
      _walk(player, 30);
      _walk(player, 60, direction: Vector3(0.0, 0.0, -1.0));

      _walk(player, 60);

      expect(player.velocity.x, closeTo(0.0, 1e-6));
      expect(player.velocity.z, closeTo(0.0, 1e-6));
    });

    test('control in the air is weaker than on the ground', () {
      final world = _room(size: 200.0, walls: false);

      final grounded = _player(world);
      _walk(grounded, 30);
      grounded.step(_dt, wishDirection: Vector3(1.0, 0.0, 0.0));
      final groundGain = grounded.velocity.x;

      final airborne = _player(world, at: Vector3(50.0, 20.0, 0.0));
      airborne.step(_dt, wishDirection: Vector3.zero());
      airborne.step(_dt, wishDirection: Vector3(1.0, 0.0, 0.0));
      final airGain = airborne.velocity.x;

      expect(airGain, greaterThan(0.0));
      expect(airGain, lessThan(groundGain));
    });
  });

  group('falling', () {
    test('a long drop does not pass through the floor', () {
      // The point of sweeping rather than stepping: from this height the last
      // step before impact covers half a metre.
      final world = _room(size: 40.0, walls: false);
      final player = _player(world, at: Vector3(0.0, 60.0, 0.0));

      _walk(player, 600);

      expect(player.position.y, closeTo(0.9, 0.02));
      expect(player.isGrounded, isTrue);
    });

    test('falling speed is capped', () {
      final world = CollisionWorld();
      final player = _player(world, at: Vector3(0.0, 0.0, 0.0));

      _walk(player, 600);

      expect(player.velocity.y, greaterThanOrEqualTo(-55.0));
    });
  });

  group('stairs', () {
    CollisionWorld stairsWorld(double height) {
      final world = _room(size: 40.0, walls: false);
      world.addBox(Vector3(0.0, height / 2.0, -3.0), Vector3(6.0, height, 2.0));
      return world;
    }

    test('a low step is walked over', () {
      final world = stairsWorld(0.3);
      final player = _player(world);
      _walk(player, 30);

      // Thirty-five steps at walking pace stops in the middle of the ledge,
      // which spans z from -4 to -2. Running longer walks off the far side and
      // measures the drop instead of the climb.
      _walk(player, 35, direction: Vector3(0.0, 0.0, -1.0));

      expect(player.position.z, lessThan(-2.5));
      expect(player.position.y, closeTo(1.2, 0.05));
      expect(player.isGrounded, isTrue);
    });

    test('a step taller than the limit is a wall', () {
      final world = stairsWorld(0.6);
      final player = _player(world);
      _walk(player, 30);

      _walk(player, 180, direction: Vector3(0.0, 0.0, -1.0));

      expect(player.position.z, greaterThan(-2.0));
      expect(player.position.y, closeTo(0.9, 0.05));
    });

    test('the climb is reported, so a renderer can smooth it', () {
      // A step up is a teleport inside one simulated step, and a renderer
      // showing it raw pitches the horizon on every riser. It cannot work the
      // height out from the position — see the lift below — so the controller
      // says how far it lifted the body.
      final world = stairsWorld(0.3);
      final player = _player(world);
      _walk(player, 30);
      expect(
        player.steppedUp,
        0.0,
        reason: 'nothing was climbed standing still',
      );

      var climbed = 0.0;
      for (var i = 0; i < 35; i++) {
        player.step(_dt, wishDirection: Vector3(0.0, 0.0, -1.0));
        player.world.update();
        climbed = math.max(climbed, player.steppedUp);
      }

      expect(
        player.position.z,
        lessThan(-2.5),
        reason: 'never reached the step',
      );
      // The whole of the ledge, in one step, and never more than the limit.
      expect(climbed, closeTo(0.3, 0.02));
      expect(climbed, lessThanOrEqualTo(const MovementTuning().stepHeight));
      // And it is this step's news, not a running total.
      _walk(player, 5, direction: Vector3(0.0, 0.0, -1.0));
      expect(player.steppedUp, 0.0);
    });

    test('a body carried upward has climbed nothing', () {
      // **The distinction the report exists for.** A lift moves its passenger
      // by writing the body's position, so a rise measured from outside looks
      // exactly like a stair — and a renderer smoothing it would draw the
      // runner sunk into the lift for the whole ascent.
      final world = CollisionWorld();
      final platform = world.add(
        Collider(
          shape: CollisionBox(Vector3(2.0, 0.5, 2.0)),
          position: Vector3(0.0, -0.5, 0.0),
          kind: ColliderKind.kinematic,
        ),
      );

      final player = _player(world, at: Vector3(0.0, 0.9, 0.0));
      _walk(player, 20);

      var reported = 0.0;
      for (var i = 0; i < 60; i++) {
        platform.moveTo(platform.position + Vector3(0.0, 0.02, 0.0));
        player.step(_dt, wishDirection: Vector3.zero());
        world.update();
        world.clearKinematicDeltas();
        reported = math.max(reported, player.steppedUp);
      }

      expect(
        player.position.y,
        greaterThan(1.9),
        reason: 'the lift never rose',
      );
      expect(reported, 0.0);
    });

    test('stepping up does not fire when there is no headroom', () {
      final world = stairsWorld(0.3);
      // A ceiling low enough that standing on the step would not fit.
      world.addBox(Vector3(0.0, 2.05, -3.0), Vector3(6.0, 0.5, 2.0));

      final player = _player(world);
      _walk(player, 30);
      _walk(player, 180, direction: Vector3(0.0, 0.0, -1.0));

      expect(player.position.z, greaterThan(-2.0));
    });
  });

  group('jumping', () {
    test('a jump leaves the ground', () {
      final world = _room(size: 40.0, walls: false);
      final player = _player(world);
      _walk(player, 30);

      player.requestJump();
      _walk(player, 10);

      expect(player.position.y, greaterThan(1.4));
      expect(player.isGrounded, isFalse);
    });

    test('and comes back down', () {
      final world = _room(size: 40.0, walls: false);
      final player = _player(world);
      _walk(player, 30);

      player.requestJump();
      _walk(player, 200);

      expect(player.position.y, closeTo(0.9, 0.02));
      expect(player.isGrounded, isTrue);
    });

    test('there is no second jump in mid-air', () {
      final world = _room(size: 40.0, walls: false);
      final player = _player(world);
      _walk(player, 30);

      player.requestJump();
      _walk(player, 15);
      final apexBefore = player.position.y;

      player.requestJump();
      _walk(player, 2);

      // Still rising or falling under gravity, not launched again.
      expect(player.velocity.y, lessThan(8.0));
      expect(player.position.y, lessThan(apexBefore + 0.5));
    });

    test('coyote time lets a jump work just after leaving an edge', () {
      final world = CollisionWorld();
      // A ledge ending at z = 0.
      world.addBox(Vector3(0.0, -0.5, 2.0), Vector3(6.0, 1.0, 4.0));

      final player = _player(world, at: Vector3(0.0, 0.9, 0.5));
      _walk(player, 30);
      expect(player.isGrounded, isTrue);

      // Walk off the end, then ask to jump a few steps later — inside the
      // coyote window but well after the ground was lost.
      _walk(player, 12, direction: Vector3(0.0, 0.0, -1.0));
      expect(player.isGrounded, isFalse);

      player.requestJump();
      final before = player.velocity.y;
      _walk(player, 1);

      expect(player.velocity.y, greaterThan(before));
      expect(player.velocity.y, greaterThan(5.0));
    });

    test('the window closes, so it is not a free jump forever', () {
      final world = CollisionWorld();
      world.addBox(Vector3(0.0, -0.5, 2.0), Vector3(6.0, 1.0, 4.0));

      final player = _player(world, at: Vector3(0.0, 0.9, 0.5));
      _walk(player, 30);
      _walk(player, 40, direction: Vector3(0.0, 0.0, -1.0));

      player.requestJump();
      _walk(player, 1);

      expect(player.velocity.y, lessThan(0.0));
    });

    test('a jump asked for just before landing still happens', () {
      final world = _room(size: 40.0, walls: false);
      // A tenth of a metre up, which is about five steps of falling — inside
      // the buffer, and far enough that the request lands while airborne.
      final player = _player(world, at: Vector3(0.0, 1.0, 0.0));

      _walk(player, 1);
      expect(player.isGrounded, isFalse);

      player.requestJump();
      _walk(player, 12);

      expect(player.position.y, greaterThan(1.5));
    });

    test('a jump asked for too early is forgotten, not stored', () {
      final world = _room(size: 40.0, walls: false);
      final player = _player(world, at: Vector3(0.0, 6.0, 0.0));

      player.requestJump();
      // Long enough for the buffer to lapse well before the landing.
      _walk(player, 120);

      expect(player.isGrounded, isTrue);
      expect(player.position.y, closeTo(0.9, 0.02));
    });

    test('a jump into a low ceiling stops without sticking', () {
      final world = _room(size: 40.0, walls: false);
      world.addBox(Vector3(0.0, 2.4, 0.0), Vector3(6.0, 0.4, 6.0));

      final player = _player(world);
      _walk(player, 30);
      player.requestJump();
      _walk(player, 8);

      // The ceiling's underside is at 2.2, so the centre cannot pass 1.3.
      expect(player.position.y, lessThan(1.35));

      // And the player comes back down rather than hanging there.
      _walk(player, 120);
      expect(player.position.y, closeTo(0.9, 0.02));
      expect(player.isGrounded, isTrue);
    });
  });

  group('moving platforms', () {
    test('a rising platform lifts its passenger', () {
      final world = CollisionWorld();
      final platform = world.add(
        Collider(
          shape: CollisionBox(Vector3(2.0, 0.5, 2.0)),
          position: Vector3(0.0, -0.5, 0.0),
          kind: ColliderKind.kinematic,
        ),
      );

      final player = _player(world, at: Vector3(0.0, 0.9, 0.0));
      _walk(player, 20);
      expect(player.isGrounded, isTrue);
      expect(player.groundBody, same(platform));

      final startY = player.position.y;
      for (var i = 0; i < 60; i++) {
        platform.moveTo(platform.position + Vector3(0.0, 0.02, 0.0));
        player.step(_dt, wishDirection: Vector3.zero());
        world.update();
        world.clearKinematicDeltas();
      }

      expect(player.position.y, closeTo(startY + 1.2, 0.05));
    });

    test('a passenger set down exactly on a platform stands on it', () {
      // **A body put exactly on a surface used to hover a fraction under it for
      // ever.** Depenetration leaves it touching; the ground probe sweeps down
      // from there; and a sweep that reads "exactly on the face" as "already
      // inside" answers no contact — so the body is airborne, gravity carries
      // it properly in, and from there the answer is honestly no contact. It
      // never lands and never falls.
      //
      // It only shows when the push lands the body precisely, which is why it
      // took a belt eight metres wide and a body dropped into the middle of it.
      final world = CollisionWorld();
      world.add(
        Collider(
          shape: CollisionBox(Vector3(4.0, 0.2, 10.0)),
          position: Vector3(0.0, 0.2, 0.0),
          kind: ColliderKind.kinematic,
        ),
      );

      // Feet at -0.2 against a platform whose top is 0.4: the body's own height
      // swallows the platform whole, which is the case that puts it exactly on
      // the surface in one push.
      final player = _player(world, at: Vector3(0.0, 0.7, 0.0));
      _walk(player, 2);

      expect(player.isGrounded, isTrue, reason: 'never landed');
      expect(player.position.y, closeTo(1.3, 0.005));
    });

    test('a sideways platform carries its passenger', () {
      final world = CollisionWorld();
      final platform = world.add(
        Collider(
          shape: CollisionBox(Vector3(2.0, 0.5, 2.0)),
          position: Vector3(0.0, -0.5, 0.0),
          kind: ColliderKind.kinematic,
        ),
      );

      final player = _player(world, at: Vector3(0.0, 0.9, 0.0));
      _walk(player, 20);

      for (var i = 0; i < 60; i++) {
        platform.moveTo(platform.position + Vector3(0.03, 0.0, 0.0));
        player.step(_dt, wishDirection: Vector3.zero());
        world.update();
        world.clearKinematicDeltas();
      }

      // Carried, and still on the platform rather than left behind its edge.
      expect(player.position.x, closeTo(1.8, 0.1));
      expect(player.isGrounded, isTrue);
    });

    test('a descending platform does not leave the player behind', () {
      final world = CollisionWorld();
      final platform = world.add(
        Collider(
          shape: CollisionBox(Vector3(2.0, 0.5, 2.0)),
          position: Vector3(0.0, 9.5, 0.0),
          kind: ColliderKind.kinematic,
        ),
      );

      final player = _player(world, at: Vector3(0.0, 10.9, 0.0));
      _walk(player, 20);

      for (var i = 0; i < 120; i++) {
        platform.moveTo(platform.position + Vector3(0.0, -0.04, 0.0));
        player.step(_dt, wishDirection: Vector3.zero());
        world.update();
        world.clearKinematicDeltas();
      }

      // Riding it down, not floating above where it used to be.
      expect(player.position.y - platform.position.y, closeTo(1.4, 0.1));
    });

    test('a platform closing on the player does not push them through', () {
      final world = _room(size: 20.0, walls: false);
      final ceiling = world.add(
        Collider(
          shape: CollisionBox(Vector3(3.0, 0.5, 3.0)),
          position: Vector3(0.0, 6.0, 0.0),
          kind: ColliderKind.kinematic,
        ),
      );

      final player = _player(world);
      _walk(player, 20);

      for (var i = 0; i < 200; i++) {
        ceiling.moveTo(ceiling.position + Vector3(0.0, -0.03, 0.0));
        player.step(_dt, wishDirection: Vector3.zero());
        world.update();
        world.clearKinematicDeltas();
      }

      // Squashed against the floor, and above it. Being pushed through would
      // put the player under the level, which is unrecoverable.
      expect(player.position.y, greaterThan(0.0));
    });
  });

  group('the floor snap', () {
    /// A staircase going down along +Z: [treads] treads, each 2 m deep and
    /// [rise] lower than the one before, each solid all the way down so the
    /// only thing under the feet is the tread itself.
    CollisionWorld staircase({double rise = 0.2, int treads = 40}) {
      final world = CollisionWorld();
      for (var i = 0; i < treads; i++) {
        world.addBox(
          Vector3(0.0, -rise * i - 2.0, 2.0 * i + 1.0),
          Vector3(8.0, 4.0, 2.0),
        );
      }
      return world;
    }

    /// Walks down [world] for [steps] and counts the steps spent off the
    /// ground.
    int airborneWalkingDown(
      CollisionWorld world,
      MovementTuning tuning, {
      int steps = 600,
    }) {
      final player = CharacterController(
        world: world,
        shape: CollisionBox(_playerHalf),
        position: Vector3(0.0, 0.9, 0.5),
        tuning: tuning,
      );
      var airborne = 0;
      for (var i = 0; i < steps; i++) {
        player.step(_dt, wishDirection: Vector3(0.0, 0.0, 1.0));
        world.update();
        if (!player.isGrounded) airborne++;
      }
      return airborne;
    }

    test('without one, a staircase is a series of small falls', () {
      // The measurement the snap exists to fix, pinned so that the fixture is
      // known to reproduce it — and so that a default which quietly stopped
      // being zero would be caught here rather than in a level.
      //
      // Mutation: default `floorSnapLength` to 0.3 and this reads zero.
      expect(
        airborneWalkingDown(staircase(), const MovementTuning()),
        greaterThan(100),
        reason:
            'eight centimetres of probe cannot hold a twenty centimetre '
            'step, and the body falls the rest of the way every tread',
      );
    });

    test('with one, the feet never leave the stairs', () {
      // Mutation: set `floorSnapLength` here to 0.0 — 116 of the 600 steps go
      // airborne. Or drop the `math.max` in `_probeGround` so the reach stays
      // at `groundProbe`, which is the same thing said in the controller.
      final airborne = airborneWalkingDown(
        staircase(),
        const MovementTuning(floorSnapLength: 0.3),
      );

      expect(airborne, 0, reason: 'a 0.3 m reach carries a 0.2 m step');
    });

    test('a body already in the air is not caught early by the long reach', () {
      // **The one sentence in the controller that says why the snap is safe**,
      // and it had no test behind it: "a body that was already airborne gets
      // the short probe, so the long reach can never find ground the body was
      // not standing on". Everything else about the feature can be right and
      // this still wrong.
      //
      // Mutation: drop the `_grounded &&` from the reach in `_probeGround`,
      // leaving `!leftDeliberately`. The whole physics suite and the whole
      // platformer suite stay green — and every fall in every game lands early
      // and soft, because the last fraction of it is deleted and the impact
      // speed with it. Anything reading landing speed for a squash, a sound or
      // fall damage reads a number that was never reached.
      double impactFalling(double snap) {
        final world = _room(size: 40.0, walls: false);
        final player = CharacterController(
          world: world,
          shape: CollisionBox(_playerHalf),
          position: Vector3(0.0, 3.9, 0.0),
          tuning: MovementTuning(floorSnapLength: snap),
        );
        var last = 0.0;
        for (var i = 0; i < 200; i++) {
          final before = player.velocity.y;
          player.step(_dt, wishDirection: Vector3.zero());
          world.update();
          if (player.isGrounded) return last;
          last = before;
        }
        fail('never landed');
      }

      // A snap changes how a fall *ends* only by not changing it: the body must
      // arrive at the floor under gravity, at the speed gravity gave it.
      expect(
        impactFalling(0.3),
        closeTo(impactFalling(0.0), 0.01),
        reason:
            'the long reach shortened a plain fall onto a flat floor: '
            '${impactFalling(0.3)} against ${impactFalling(0.0)}',
      );
    });

    test(
      'and a pit is still a pit, at the default and at a stair-sized snap',
      () {
        // The hazard the length has to stay under. A snap deep enough to reach
        // an authored pit floor does not make the body fall in slowly — it
        // *places* it at the bottom on the first step, so the fall never
        // happens and nothing downstream ever sees the body airborne.
        //
        // Two metres is the shallowest pit anything in this repository authors.
        //
        // Mutation: default `floorSnapLength` to 2.0, or pass 2.0 below, and
        // the body walks off the lip still grounded.
        CollisionWorld pit() {
          final world = CollisionWorld();
          // The lip, z from -6 to 0, its top at y = 0.
          world.addBox(Vector3(0.0, -1.0, -3.0), Vector3(8.0, 2.0, 6.0));
          // The pit floor, two metres down, and long enough that walking on is
          // not walking off the end of it.
          world.addBox(Vector3(0.0, -3.0, 20.0), Vector3(8.0, 2.0, 40.0));
          return world;
        }

        for (final tuning in <MovementTuning>[
          const MovementTuning(),
          const MovementTuning(floorSnapLength: 0.3),
        ]) {
          final world = pit();
          final player = CharacterController(
            world: world,
            shape: CollisionBox(_playerHalf),
            position: Vector3(0.0, 0.9, -3.0),
            tuning: tuning,
          );

          var fell = false;
          var fastest = 0.0;
          for (var i = 0; i < 180; i++) {
            player.step(_dt, wishDirection: Vector3(0.0, 0.0, 1.0));
            world.update();
            if (!player.isGrounded) fell = true;
            fastest = math.max(fastest, -player.velocity.y);
          }

          expect(fell, isTrue, reason: 'the body must leave the lip');
          expect(
            fastest,
            greaterThan(3.0),
            reason: 'and fall, rather than be placed at the bottom',
          );
          expect(
            player.position.y,
            closeTo(-1.1, 0.05),
            reason: 'landing on the pit floor at y = -2',
          );
        }
      },
    );

    test(
      'the snap sweep asks the filter, so a refused floor is not a floor',
      () {
        // The snap is the second sweep that can hold a body up, and
        // [solidFilter] is how a game says which surfaces count for it —
        // droppable platforms, phase states, a platform that is a floor only
        // from above. Stepping off a lip onto a surface the filter refuses has
        // to be stepping into space.
        //
        // Mutation: drop `allow: solidFilter` from the snap sweep in
        // `_probeGround`. The reach finds the refused platform 0.2 m under the
        // lip and stands the body on it.
        //
        // **For one step and not more**, which is worth saying rather than
        // overselling: the step after, gravity sinks the box into the platform,
        // and a sweep whose shape starts inside a box reports no hit at all — so
        // the fall resumes by itself. One step is still a refilled jump budget,
        // a reset coyote timer, a landing, and [ground] naming a collider the
        // game has just said is not there.
        final world = CollisionWorld();
        // The lip: top at y = 0, z from -6 to 0.
        world.addBox(Vector3(0.0, -1.0, -3.0), Vector3(8.0, 2.0, 6.0));
        // A platform 0.2 m lower and well inside the snap's reach, which the
        // filter refuses.
        final refused = world.addBox(
          Vector3(0.0, -0.35, 4.0),
          Vector3(8.0, 0.3, 8.0),
        );
        // And the real floor, far below both.
        world.addBox(Vector3(0.0, -6.5, 0.0), Vector3(40.0, 1.0, 40.0));

        final player = CharacterController(
          world: world,
          shape: CollisionBox(_playerHalf),
          position: Vector3(0.0, 0.9, -3.0),
          tuning: const MovementTuning(floorSnapLength: 0.5),
        )..solidFilter = (SweptContact c) => c.other != refused;

        var stoodOnIt = 0;
        for (var i = 0; i < 90; i++) {
          player.step(_dt, wishDirection: Vector3(0.0, 0.0, 1.0));
          world.update();
          // Past the lip, and not yet down on the real floor.
          if (player.position.z > 0.36 &&
              player.position.y > -2.0 &&
              player.isGrounded) {
            stoodOnIt++;
          }
        }

        expect(stoodOnIt, 0, reason: 'the refused platform is not ground');
        expect(
          player.position.y,
          closeTo(-5.1, 0.05),
          reason: 'it fell past it to the floor at y = -6',
        );
      },
    );

    test('a body that left the ground on purpose is not pulled back to it', () {
      // A spring, a stomp bounce or a jump the game owns writes `velocity.y`
      // from outside and the controller has no other way to know it was
      // deliberate.
      //
      // **In open air it needs no help**, and this half claims no mutation:
      // the upward speed survives the whole step, and `_probeGround`'s
      // `velocity.y > 0.0` early-out already calls that airborne one layer
      // down. Asserted anyway, because it is the thing a caller cares about.
      final open = CollisionWorld();
      open.addBox(Vector3(0.0, -0.5, 0.0), Vector3(20.0, 1.0, 20.0));
      final thrown = CharacterController(
        world: open,
        shape: CollisionBox(_playerHalf),
        position: Vector3(0.0, 0.9, 0.0),
        tuning: const MovementTuning(floorSnapLength: 0.5),
      );
      _walk(thrown, 30);
      thrown.velocity.y = 15.0;
      thrown.suppressFloorSnap();
      thrown.step(_dt, wishDirection: Vector3.zero());

      expect(thrown.velocity.y, closeTo(15.0 - 24.0 * _dt, 1e-6));
      expect(thrown.isGrounded, isFalse);

      // The half that does need it: a low ceiling takes the upward speed away
      // inside the same step, so the probe runs with `velocity.y` at zero and
      // the feet twenty centimetres above a floor they were on last step —
      // which is exactly the shape of a stair edge.
      //
      // Mutation: drop the `suppressFloorSnap()` call — or the
      // `!leftDeliberately` term in `_probeGround` — and the body is placed
      // back on the pad it was thrown from, still grounded, having gone
      // nowhere. With a pad that fires while it is stood on, that is a runner
      // vibrating in place for ever.
      final shaft = CollisionWorld();
      shaft.addBox(Vector3(0.0, -0.5, 0.0), Vector3(20.0, 1.0, 20.0));
      shaft.addBox(Vector3(0.0, 2.3, 0.0), Vector3(20.0, 0.6, 20.0));
      final bonked = CharacterController(
        world: shaft,
        shape: CollisionBox(_playerHalf),
        position: Vector3(0.0, 0.9, 0.0),
        tuning: const MovementTuning(floorSnapLength: 0.5),
      );
      _walk(bonked, 30);
      final pad = bonked.position.y;

      bonked.velocity.y = 15.0;
      bonked.suppressFloorSnap();
      bonked.step(_dt, wishDirection: Vector3.zero());

      expect(bonked.velocity.y, closeTo(0.0, 1e-9), reason: 'the ceiling');
      expect(bonked.isGrounded, isFalse);
      expect(
        bonked.position.y,
        greaterThan(pad + 0.15),
        reason: 'it stays where the ceiling stopped it',
      );
    });

    test('and the suppression is spent by one probe, not held for ever', () {
      // A flag nobody clears is a body whose snap was turned off by one jump
      // and never came back — and because the plain probe still lands it, the
      // symptom is not a fall but a staircase that starts stuttering again
      // twenty seconds after the jump that broke it. That is the kind of bug
      // nobody attributes to the jump.
      //
      // Mutation: drop `_snapSuppressed = false;` from `_probeGround`. The
      // stairs below go back to 116 airborne steps out of 600.
      final world = staircase();
      final player = CharacterController(
        world: world,
        shape: CollisionBox(_playerHalf),
        position: Vector3(0.0, 0.9, 0.5),
        tuning: const MovementTuning(floorSnapLength: 0.3),
      );

      var airborne = 0;
      for (var i = 0; i < 600; i++) {
        // Once, early on, and nothing else about the run changes.
        if (i == 60) player.suppressFloorSnap();
        player.step(_dt, wishDirection: Vector3(0.0, 0.0, 1.0));
        world.update();
        // From the step after the one it was allowed to spoil.
        if (i > 61 && !player.isGrounded) airborne++;
      }

      expect(airborne, 0, reason: 'one probe later the snap is back');
    });
  });

  group('the stress test', () {
    test('a thousand runs never end inside geometry', () {
      // Point tests find the failures somebody thought of. This finds the ones
      // nobody did: the wedge that ejects, the corner that swallows, the seam
      // between two brushes that a sweep slips through. It is the single most
      // valuable test in this file.
      final world = _room(size: 30.0);

      // Pillars, steps and a low ceiling, to give the sweep awkward company.
      for (var i = 0; i < 12; i++) {
        final angle = i / 12.0 * 2.0 * math.pi;
        world.addBox(
          Vector3(math.cos(angle) * 8.0, 2.0, math.sin(angle) * 8.0),
          Vector3(1.2, 4.0, 1.2),
        );
      }
      for (var i = 0; i < 5; i++) {
        world.addBox(
          Vector3(0.0, 0.15 + i * 0.3, -2.0 - i * 1.2),
          Vector3(4.0, 0.3 + i * 0.6, 1.2),
        );
      }
      world.addBox(Vector3(4.0, 2.3, 4.0), Vector3(5.0, 0.4, 5.0));

      final random = math.Random(20260809);
      final probe = <Collider>[];
      var worstIntrusion = 0.0;

      for (var run = 0; run < 1000; run++) {
        final player = _player(
          world,
          at: Vector3(
            (random.nextDouble() - 0.5) * 24.0,
            1.0 + random.nextDouble() * 6.0,
            (random.nextDouble() - 0.5) * 24.0,
          ),
        );

        var angle = random.nextDouble() * 2.0 * math.pi;
        for (var i = 0; i < 90; i++) {
          // Turn now and then, so runs do not all end pressed against one wall.
          if (i % 15 == 0) angle += (random.nextDouble() - 0.5) * 2.0;
          if (random.nextDouble() < 0.05) player.requestJump();

          player.step(
            _dt,
            wishDirection: Vector3(math.cos(angle), 0.0, math.sin(angle)),
            sprint: random.nextDouble() < 0.5,
          );
          world.update();
        }

        // Inside the room, on the right side of the floor.
        expect(
          player.position.y,
          greaterThan(-0.5),
          reason: 'run $run fell through the floor',
        );
        expect(
          player.position.x.abs(),
          lessThan(15.5),
          reason: 'run $run escaped through a wall',
        );
        expect(
          player.position.z.abs(),
          lessThan(15.5),
          reason: 'run $run escaped through a wall',
        );

        // And not embedded in a brush. A little intrusion is inevitable — the
        // controller sits a millimetre off every surface it touches — so the
        // bar is that nothing is *deeply* inside.
        world.overlap(
          CollisionBox(_playerHalf * 0.9),
          player.position,
          probe,
          ignore: player.collider,
          includeTriggers: false,
        );
        if (probe.isNotEmpty) {
          for (final other in probe) {
            final overlapX =
                (_playerHalf.x * 0.9 + other.shape.boundsHalfExtents.x) -
                (player.position.x - other.position.x).abs();
            final overlapZ =
                (_playerHalf.z * 0.9 + other.shape.boundsHalfExtents.z) -
                (player.position.z - other.position.z).abs();
            final overlapY =
                (_playerHalf.y * 0.9 + other.shape.boundsHalfExtents.y) -
                (player.position.y - other.position.y).abs();
            final shallowest = math.min(overlapX, math.min(overlapY, overlapZ));
            if (shallowest > worstIntrusion) worstIntrusion = shallowest;
          }
        }

        world.remove(player.collider);
      }

      expect(
        worstIntrusion,
        lessThan(0.05),
        reason:
            'a run ended ${worstIntrusion.toStringAsFixed(3)} m inside a '
            'brush, which is deep enough to be a bug rather than skin width',
      );
    });
  });
}
