/// What a floor snap costs this genre, and the one line that pays for it.
///
///     flutter test test/floor_snap_test.dart
///
/// `MovementTuning.floorSnapLength` keeps a body's feet on a floor it already
/// had, which is how a staircase stops being a series of small falls. The
/// engine cannot tell that from a body being *thrown* off a floor it already
/// had: both are a grounded body whose `velocity.y` was written from outside,
/// and nothing on a `Vector3` records who assigned to it. So the genre says
/// so, with `CharacterController.suppressFloorSnap`, at every point where it
/// takes the runner off the ground itself.
///
/// The whole visible difference is a single step, and it is worth being plain
/// about why: while the upward speed survives that step, the controller's own
/// `velocity.y > 0` rule already calls the body airborne, and from the step
/// after that a body which is airborne is never snapped. What is left is the
/// case where the rise is cancelled inside the same step it started — which
/// means something overhead, close enough to be hit in a sixtieth of a second.
/// A low soffit over a spring is a mean piece of level design and an entirely
/// ordinary one, and without the line below it is a runner that never leaves
/// the pad at all: snapped back down, fired again, sixty times a second.
library;

import 'package:flutter3d_game/flutter3d_game.dart';
import 'package:flutter3d_game_platformer/flutter3d_game_platformer.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

const double _dt = 1.0 / 60.0;

/// A floor, a low ceiling over it, and a runner whose body snaps to floors.
final class _Shaft {
  _Shaft({double headroom = 0.1, double snap = 0.5}) {
    world.addBox(Vector3(0.0, -0.5, 0.0), Vector3(20.0, 1.0, 20.0));
    // The runner is 1.8 m tall and stands with its head at y = 1.8.
    world.addBox(
      Vector3(0.0, 1.8 + headroom + 0.5, 0.0),
      Vector3(20.0, 1.0, 20.0),
    );

    final tuning = MovementTuning(floorSnapLength: snap);
    runner = Runner(
      body: CharacterController(
        world: world,
        position: Vector3(0.0, 0.9, 0.0),
        tuning: tuning,
      ),
      // The floor is a bare box rather than a `Brush`, so the surface lookup
      // never fires — but a table whose fallback forgot the snap would put it
      // back to zero on the first step a floor *is* named, and that is a trap
      // worth not walking into in the fixture.
      surfaces: Surfaces(const <String, MovementTuning>{}, fallback: tuning),
    );
  }

  final CollisionWorld world = CollisionWorld();
  final InputState input = InputState();
  late final Runner runner;

  void step({bool jump = false}) {
    input.beginStep();
    if (jump) input.press(GameAction.jump);
    runner.step(_dt, input);
    input.endStep();
    if (jump) input.release(GameAction.jump);
    world.update();
  }

  double get y => runner.position.y;
}

void main() {
  group('a runner thrown off a floor it was standing on', () {
    test('a spring launch is not undone by the snap', () {
      // Mutation: drop `body.suppressFloorSnap()` from `Runner.launch`. The
      // ceiling takes the fifteen metres a second away inside the same step,
      // the probe then finds the pad it was thrown from ten centimetres below
      // and puts the runner back on it — grounded, where it started, having
      // been launched.
      final shaft = _Shaft()..step();
      final pad = shaft.y;
      expect(shaft.runner.isGrounded, isTrue, reason: 'on the pad first');

      shaft.runner.launch(15.0);
      shaft.step();

      expect(shaft.runner.isGrounded, isFalse);
      expect(
        shaft.y,
        greaterThan(pad + 0.05),
        reason: 'it stays where the ceiling stopped it',
      );
      expect(
        shaft.runner.body.velocity.y,
        closeTo(0.0, 1e-9),
        reason: 'and the ceiling is what stopped it',
      );
    });

    test('and neither is the hop off something it stomped', () {
      // Mutation: drop `body.suppressFloorSnap()` from `Runner.bounce`.
      //
      // A stomp is the one that reads oddest and is the most likely: landing
      // on a head *is* landing, so the body is genuinely grounded when the
      // bounce is asked for, and this is the runner bouncing off an enemy in a
      // corridor with something over it.
      final shaft = _Shaft()..step();
      final head = shaft.y;

      shaft.runner.bounce();
      shaft.step();

      expect(shaft.runner.isGrounded, isFalse);
      expect(shaft.y, greaterThan(head + 0.05));
    });

    test('and neither is the jump this genre owns', () {
      // The one a player would report, because it is the only one of the three
      // they can ask for on purpose: a low ceiling and a jump that does
      // nothing at all. The runner rises ten centimetres, meets the soffit,
      // and is put back down inside the same step — there is not even a frame
      // of it to see.
      //
      // Mutation: drop `body.suppressFloorSnap()` from the ground branch of
      // `Runner._tryJump`.
      final shaft = _Shaft()..step();
      final floor = shaft.y;

      shaft.step(jump: true);

      expect(shaft.runner.isGrounded, isFalse);
      expect(shaft.y, greaterThan(floor + 0.05));
    });

    test('a jump in the open needs none of this', () {
      // No mutation is claimed here, and that is the point of writing it down:
      // with nothing overhead the upward speed survives the step, and
      // `_probeGround`'s `velocity.y > 0` rule already answers the question one
      // layer below anything this genre says. The suppression buys exactly the
      // case above and nothing else, and a reader who thinks otherwise is owed
      // this test.
      final open = _Shaft(headroom: 10.0)..step();
      final floor = open.y;

      open.runner.launch(15.0);
      open.step();

      expect(open.runner.isGrounded, isFalse);
      expect(open.runner.body.velocity.y, closeTo(15.0 - 24.0 * _dt, 1e-6));
      expect(open.y, greaterThan(floor + 0.2));
    });
  });
}
