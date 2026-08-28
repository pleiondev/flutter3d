/// The dash, which shipped with no test at all.
///
/// It was written, played and committed on the strength of looking right, which
/// is exactly the kind of thing this repository has a rule about. These are the
/// four claims its doc comment makes.
library;

import 'dart:math' as math;

import 'package:flutter3d_game/flutter3d_game.dart';
import 'package:flutter3d_game_platformer/flutter3d_game_platformer.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

const double _dt = 1.0 / 60.0;

final class _Field {
  _Field() {
    world.addBox(Vector3(0.0, -0.5, 0.0), Vector3(120.0, 1.0, 120.0));
    runner = Runner(
      body: CharacterController(world: world, position: Vector3(0.0, 0.9, 0.0)),
    );
  }

  final CollisionWorld world = CollisionWorld();
  final InputState input = InputState();
  late final Runner runner;

  bool _forward = false;

  void step({bool forward = false, bool dash = false}) {
    input.beginStep();
    if (forward != _forward) {
      forward
          ? input.press(GameAction.moveForward)
          : input.release(GameAction.moveForward);
      _forward = forward;
    }
    if (dash) input.press(PlatformerActions.dash);
    runner.step(_dt, input);
    input.endStep();
    if (dash) input.release(PlatformerActions.dash);
  }

  void run(int steps, {bool forward = false}) {
    for (var i = 0; i < steps; i++) {
      step(forward: forward);
    }
  }
}

void main() {
  test('a dash covers ground a walk of the same length does not', () {
    // Mutation: set `dashSpeed` to the walk speed. The two runs land within a
    // few centimetres and this fails.
    double travelled({required bool dashing}) {
      final field = _Field()..step(forward: true, dash: dashing);
      field.run(30, forward: true);
      return field.runner.position.z;
    }

    expect(
      travelled(dashing: true),
      greaterThan(travelled(dashing: false) + 1.0),
    );
  });

  test('a dash with the stick centred goes where the runner faces', () {
    // The clause its doc argues for: a dash that refuses to happen because the
    // stick is centred is a dash that feels broken at the moment it is needed.
    // Mutation: drop the facing fallback in `_tryDash` and this goes nowhere.
    final field = _Field();
    // Walk far enough to be facing +Z, then let go and dash from standing.
    field.run(30, forward: true);
    final facing = field.runner.yaw;
    field.run(20);
    final from = field.runner.position.z;

    field.step(dash: true);
    field.run(20);

    expect(facing, closeTo(0.0, 0.05), reason: 'it was walking along +Z');
    expect(field.runner.position.z, greaterThan(from + 0.8));
  });

  test('a dash is flat: it neither lifts nor drops the runner', () {
    // `_tryDash` zeroes `velocity.y`, which is what makes an air dash read as
    // a hang rather than a dive. On the ground the visible half is that a dash
    // does not launch you.
    final field = _Field()..step(forward: true, dash: true);
    final ground = field.runner.position.y;
    field.run(20, forward: true);

    expect(field.runner.position.y, closeTo(ground, 0.02));
  });

  test('the cooldown makes the second dash wait', () {
    // Mutation: never set `_dashCooldown`. The second dash fires immediately
    // and the runner crosses the field at dash speed for ever.
    final field = _Field()..step(forward: true, dash: true);
    expect(field.runner.dashCooldown, greaterThan(0.0));

    // Measured as speed, not as distance travelled in a step: the runner is
    // still carrying the first dash, so a step's length says nothing about
    // whether a second one fired. The first version of this test measured
    // distance and passed for the wrong reason.
    double flatSpeed() {
      final v = field.runner.body.velocity;
      return math.sqrt(v.x * v.x + v.z * v.z);
    }

    field.run(20, forward: true);
    expect(
      field.runner.dashCooldown,
      greaterThan(0.0),
      reason: 'still cooling',
    );
    field.step(forward: true, dash: true);
    expect(flatSpeed(), lessThan(12.0), reason: 'the press was refused');

    field.run(40, forward: true);
    expect(field.runner.dashCooldown, 0.0);
    field.step(forward: true, dash: true);
    expect(flatSpeed(), greaterThan(17.0), reason: 'and now it fires');
  });

  test('a dash in the air keeps its distance', () {
    // Air friction does not exist in the controller, so an air dash carries
    // further than a ground one. Worth pinning: it is the reason a dash is a
    // traversal move and not only an attack.
    // Genuinely airborne: a jump held to its apex. Dashing from a hop does not
    // test this, because `_tryDash` zeroes the vertical speed — so a dash a few
    // centimetres off the floor lands on the same step it started.
    final field = _Field();
    field.input.press(GameAction.jump);
    for (var i = 0; i < 24; i++) {
      field.step(forward: true);
    }
    field.input.release(GameAction.jump);
    expect(field.runner.isGrounded, isFalse, reason: 'at the top of a jump');

    final from = field.runner.position.z;
    field.step(forward: true, dash: true);
    for (var i = 0; i < 20; i++) {
      field.step(forward: true);
    }

    expect(field.runner.position.z - from, greaterThan(3.0));
  });

  test('facing follows the direction of travel, by the shortest way round', () {
    // `_face` turns towards `atan2(wish.x, wish.z)` and wraps. Mutation: drop
    // the wrap and a runner turning past pi spins the long way round, visible
    // as a pirouette every time you reverse.
    final field = _Field()..run(20, forward: true);
    expect(field.runner.yaw, closeTo(0.0, 0.05));

    // Now ask for the opposite direction and watch it arrive within a turn.
    field.input.press(GameAction.moveBack);
    field.input.release(GameAction.moveForward);
    field._forward = false;
    for (var i = 0; i < 40; i++) {
      field.input.beginStep();
      field.runner.step(_dt, field.input);
      field.input.endStep();
    }

    expect(field.runner.yaw.abs(), closeTo(math.pi, 0.1));
  });
}
