/// The vertical vocabulary: sliding down a wall, jumping off one, pulling up
/// onto a ledge, and being thrown by a pad.
///
/// Each one gets a shape it is the only way out of, so the test fails when the
/// verb stops working rather than when a number is tuned.
library;

import 'package:flutter3d_game/flutter3d_game.dart';
import 'package:flutter3d_game_platformer/flutter3d_game_platformer.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

const double _dt = 1.0 / 60.0;

final class _Stage {
  _Stage() {
    world.addBox(Vector3(0.0, -0.5, 0.0), Vector3(40.0, 1.0, 40.0));
    mechanisms = MechanismWorld(world);
    runner = Runner(
      body: CharacterController(world: world, position: Vector3(0.0, 0.9, 0.0)),
    );
  }

  final CollisionWorld world = CollisionWorld();
  final InputState input = InputState();
  late final MechanismWorld mechanisms;
  late final Runner runner;

  /// A wall whose face is at [x], running along Z.
  void wallAt(double x, {double height = 8.0, double from = -10.0, double to = 10.0}) {
    world.addBox(
      Vector3(x + 0.5, height / 2.0, (from + to) / 2.0),
      Vector3(1.0, height, to - from),
    );
  }

  /// A slab whose top is at [top], starting at [z] and running away.
  void ledgeAt(double z, {required double top}) {
    world.addBox(
      Vector3(0.0, top / 2.0, z + 3.0),
      Vector3(8.0, top, 6.0),
    );
  }

  Spring springAt(Vector3 at, {double speed = 15.0}) => mechanisms.add(
        Spring(
          collider: world.add(
            Collider(
              shape: CollisionBox(Vector3(0.8, 0.2, 0.8)),
              position: at,
              kind: ColliderKind.trigger,
              layer: CollisionLayers.trigger,
              mask: CollisionLayers.player,
            ),
          ),
          speed: speed,
        ),
      );

  final Set<GameAction> _held = <GameAction>{};

  void step({Set<GameAction>? holding}) {
    input.beginStep();
    final wanted = holding ?? const <GameAction>{};
    for (final action in wanted.difference(_held)) {
      input.press(action);
    }
    for (final action in _held.difference(wanted)) {
      input.release(action);
    }
    _held
      ..clear()
      ..addAll(wanted);
    mechanisms.step(_dt);
    world.reindex();
    runner.step(_dt, input);
    world.update();
    world.clearKinematicDeltas();
    input.endStep();
  }

  void run(int steps, {Set<GameAction>? holding}) {
    for (var i = 0; i < steps; i++) {
      step(holding: holding);
    }
  }

  /// Puts the runner in the air beside the wall, falling.
  void dropBeside(double x, {double height = 6.0}) {
    runner.body
      ..teleport(Vector3(x, height, 0.0))
      ..velocity.setZero();
  }
}

// Not `const`: a set literal cannot be constant when its elements override
// `==`, which `GameAction` does since it stopped being an enum. Worth
// knowing before somebody tries to declare a const set of actions.
//
// **`moveLeft` is world +X.** Screen-right of a camera looking along +Z is
// world -X — the thing a player found the hard way — so the way to lean on a
// wall standing at +X is to press left. Written down here because the first
// version of this file pressed right and spent a run wondering why the wall
// kept vanishing.
final Set<GameAction> _intoWall = <GameAction>{GameAction.moveLeft};
final Set<GameAction> _intoWallAndJump = <GameAction>{
  GameAction.moveLeft,
  GameAction.jump,
};
final Set<GameAction> _nothing = <GameAction>{};
final Set<GameAction> _forward = <GameAction>{GameAction.moveForward};
final Set<GameAction> _jump = <GameAction>{GameAction.jump};

void main() {
  group('the wall', () {
    test('a runner beside a wall knows it is there', () {
      final stage = _Stage()..wallAt(1.0);
      stage.dropBeside(0.6);
      stage.run(3);

      expect(stage.runner.isOnWall, isTrue);
      // The normal points away from the wall, so a wall at +X pushes towards -X.
      expect(stage.runner.wallAway.x, lessThan(-0.5));
    });

    test('a floor is not a wall', () {
      // Mutation: drop the `normal.y` test in `_probeWall`. Standing anywhere
      // reports a wall, and every jump becomes a wall jump.
      final stage = _Stage();
      stage.run(10);
      expect(stage.runner.isOnWall, isFalse);
    });

    test('sliding is slower than falling', () {
      // Mutation: remove `_slideDownWall`. The two runs agree, and the wall
      // stops being somewhere you can think.
      double fallFrom({required bool nearWall}) {
        final stage = _Stage();
        if (nearWall) stage.wallAt(1.0);
        stage.dropBeside(nearWall ? 0.6 : -5.0);
        stage.run(40, holding: nearWall ? _intoWall : _nothing);
        return stage.runner.position.y;
      }

      expect(fallFrom(nearWall: true), greaterThan(fallFrom(nearWall: false) + 1.0));
    });

    test('a wall jump goes up and away, and the away is not optional', () {
      // Mutation: set `wallJumpPush` to zero. The runner leaves straight up,
      // holding into the wall keeps it there, and a chimney becomes a ladder —
      // which is why the second assertion is about x and not about height.
      final stage = _Stage()..wallAt(1.0);
      stage.dropBeside(0.6);
      // Ten steps, not three: a runner is constructed standing, so it carries
      // ground coyote time for the first seven. Jump inside that window and it
      // is an ordinary jump, which is what the first version of this test
      // measured.
      stage.run(10, holding: _intoWall);
      expect(stage.runner.isOnWall, isTrue);

      final from = stage.runner.position.clone();
      stage.step(holding: _intoWallAndJump);

      expect(stage.runner.wallJumpedThisStep, isTrue);
      expect(stage.runner.body.velocity.y, greaterThan(8.0));
      expect(stage.runner.body.velocity.x, lessThan(-5.0),
          reason: 'away from a wall at +X');
      expect(stage.runner.position.y, greaterThan(from.y - 0.2));
    });

    test('a wall jump gives the air jump back', () {
      // Two walls facing each other are meant to be climbable; a wall jump that
      // spent the air jump would make the second one impossible.
      final stage = _Stage()..wallAt(1.0);
      stage.dropBeside(0.6);
      stage.run(10, holding: _intoWall);
      stage.step(holding: _intoWallAndJump);

      expect(stage.runner.airJumpsLeft, 1);
    });

    test('a wall jump still counts a moment after leaving the wall', () {
      // Coyote time, for the same reason as on the ground: the player pressed
      // jump when they were on the wall. Mutation: set `wallCoyoteTime` to zero.
      final stage = _Stage()..wallAt(1.0);
      stage.dropBeside(0.6);
      stage.run(10, holding: _intoWall);
      // Step away from the wall, then jump.
      stage.runner.body.teleport(Vector3(-1.0, stage.runner.position.y, 0.0));
      stage.run(2);
      stage.step(holding: _jump);

      expect(stage.runner.wallJumpedThisStep, isTrue);
    });
  });

  group('the ledge', () {
    test('a runner pulls up onto a ledge it was falling past', () {
      // Mutation: drop the `_tryMantle` call. The runner slides down the face
      // and lands at the bottom, and `position.y` ends near zero.
      final stage = _Stage()..ledgeAt(1.0, top: 1.4);
      stage.runner.body
        ..teleport(Vector3(0.0, 1.9, 0.2))
        ..velocity.setValues(0.0, -1.0, 0.0);
      stage.run(20, holding: _forward);

      expect(stage.runner.mantledThisStep || stage.runner.position.y > 2.0,
          isTrue);
      expect(stage.runner.position.y, greaterThan(2.0),
          reason: 'standing on a ledge topped at 1.4');
    });

    test('a ledge with no headroom is not climbed', () {
      // Mutation: skip the clearance check and the runner is placed inside the
      // slab above, which the depenetration then squeezes out sideways — the
      // classic "mantled into a ceiling" bug.
      final stage = _Stage()..ledgeAt(1.0, top: 1.4);
      // A lid a hand's breadth above the ledge.
      stage.world.addBox(Vector3(0.0, 2.2, 4.0), Vector3(8.0, 0.4, 6.0));

      stage.runner.body
        ..teleport(Vector3(0.0, 1.9, 0.2))
        ..velocity.setValues(0.0, -1.0, 0.0);
      stage.run(20, holding: _forward);

      expect(stage.runner.mantledThisStep, isFalse);
      expect(stage.runner.position.y, lessThan(2.0));
    });

    test('a kerb is stepped over, not mantled', () {
      // Below `mantleLow` the controller's own step-up handles it, and pulling
      // up onto a kerb looks like a stumble.
      final stage = _Stage()..ledgeAt(1.0, top: 0.25);
      stage.run(30, holding: _forward);

      expect(stage.runner.mantledThisStep, isFalse);
      expect(stage.runner.isGrounded, isTrue);
    });
  });

  group('the shaft', () {
    /// Two walls facing each other, too high to jump out of and too narrow to
    /// walk out of. The only way up is off the walls.
    _Stage shaft() {
      final stage = _Stage();
      // Faces at -0.9 and +0.9: the runner is 0.7 across, so a fifth of a metre
      // of air each side — inside the probe's reach and outside its body.
      stage.world.addBox(Vector3(-1.4, 6.0, 0.0), Vector3(1.0, 12.0, 8.0));
      stage.world.addBox(Vector3(1.4, 6.0, 0.0), Vector3(1.0, 12.0, 8.0));
      // The way out, four metres up — twice a jump and half again.
      stage.world.addBox(Vector3(0.0, 4.0, 6.0), Vector3(6.0, 8.0, 4.0));
      return stage;
    }

    /// Jumps on a rhythm and leans into whichever wall is nearer.
    double climb(_Stage stage) {
      var best = stage.runner.position.y;
      for (var i = 0; i < 400; i++) {
        final away = stage.runner.wallAway.x;
        final lean = away < 0 ? GameAction.moveLeft : GameAction.moveRight;
        stage.step(holding: <GameAction>{
          lean,
          if (i % 14 < 3) GameAction.jump,
        });
        if (stage.runner.position.y > best) best = stage.runner.position.y;
      }
      return best;
    }

    test('a runner climbs out of a shaft it cannot jump out of', () {
      // The stage's acceptance, and the reason it is a shaft rather than a
      // wall: this shape has no other answer. A single jump reaches 1.88 m and
      // a double 3.28; the way out is at 4.
      expect(climb(shaft()), greaterThan(4.0));
    });

    test('and cannot climb out without the wall jump', () {
      // The other half, and the one that makes the first mean something.
      // Mutation in reverse: with wall jumping switched off the same rhythm
      // never leaves the bottom of the shaft.
      final stage = shaft();
      stage.runner.body.teleport(Vector3(0.0, 0.9, 0.0));
      // A runner whose wall jump goes nowhere: the tuning is the switch.
      final crippled = Runner(
        body: stage.runner.body,
        tuning: const RunnerTuning(wallJumpUp: 0.0, wallJumpPush: 0.0),
      );
      var best = crippled.position.y;
      for (var i = 0; i < 400; i++) {
        stage.input.beginStep();
        if (i % 14 == 0) stage.input.press(GameAction.jump);
        if (i % 14 == 3) stage.input.release(GameAction.jump);
        crippled.step(1.0 / 60.0, stage.input);
        stage.world.update();
        stage.input.endStep();
        if (crippled.position.y > best) best = crippled.position.y;
      }

      expect(best, lessThan(4.0));
    });
  });

  group('the spring', () {
    test('walking onto a pad throws the runner', () {
      final stage = _Stage()..springAt(Vector3(0.0, 0.3, 2.0));
      stage.run(60, holding: _forward);

      expect(stage.runner.position.y, greaterThan(3.0));
    });

    test('a pad throws higher than a jump', () {
      // The reason a pad exists: it goes where the runner cannot. Mutation: set
      // the spring's speed to the jump speed and this fails.
      double apex({required bool onPad}) {
        final stage = _Stage();
        if (onPad) stage.springAt(Vector3(0.0, 0.3, 0.0));
        var best = 0.0;
        for (var i = 0; i < 90; i++) {
          stage.step(
              holding: onPad ? _nothing : _jump);
          if (stage.runner.position.y > best) best = stage.runner.position.y;
        }
        return best;
      }

      expect(apex(onPad: true), greaterThan(apex(onPad: false) + 1.5));
    });

    test('a launch gives the jump budget back', () {
      // Mutation: drop the `_airJumpsLeft` line in `launch`. A runner thrown
      // after spending their double jump cannot use it at the top, which is
      // exactly where a pad is aimed.
      final stage = _Stage()..springAt(Vector3(0.0, 0.3, 0.0));
      stage.runner.body.teleport(Vector3(0.0, 0.9, 0.0));
      stage.run(3);

      expect(stage.runner.airJumpsLeft, 1);
      expect(stage.runner.body.velocity.y, greaterThan(10.0));
    });
  });
}
