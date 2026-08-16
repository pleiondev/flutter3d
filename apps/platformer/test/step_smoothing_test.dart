/// What a riser in the shipped level looks like once it is drawn.
///
///     flutter test test/step_smoothing_test.dart
///
/// **Ascent is full of low ledges and the camera follows the body over every
/// one of them.** Eighteen places in `ascent.json` put a walkable top within
/// forty centimetres of the one beside it — planks laid on terraces, mostly —
/// and a character controller crosses one by *teleporting*: up, across, down,
/// all inside a single simulated step. The simulation is right to do that. The
/// picture is not: fifteen centimetres in a sixtieth of a second is nine metres
/// a second, and the camera pitches on every riser.
///
/// So the riser is found in the shipped level rather than built here, the
/// shipped simulation walks the runner over it, and the two interpolators the
/// application could have — smoothed and plain — are fed the same run. The
/// claim is the difference between them, which is why the plain one is asserted
/// to be bad: a test where both are smooth is a test of nothing.
///
/// The application's own wiring is three lines of `main.dart` — the limit comes
/// from the runner's tuning at load, and every push carries `steppedUp` and the
/// step length.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter3d_game/flutter3d_game.dart';
import 'package:flutter3d_platformer/flutter3d_platformer.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

const double _dt = 1.0 / 60.0;

Level _shipped() => Level.fromJson(
      jsonDecode(File('assets/levels/ascent.json').readAsStringSync())
          as Map<String, Object?>,
    );

double _top(Brush brush) => brush.centre.y + brush.size.y / 2.0;

/// Somewhere in the shipped level a walk crosses a ledge under [limit].
///
/// Returned as a place to stand and a way to face, both taken from the brushes:
/// hand-written coordinates would be a fixture wearing the level's name, and
/// would go stale the first time the generator moved a terrace.
final class _Riser {
  _Riser(this.lower, this.upper);

  final Brush lower;
  final Brush upper;

  double get rise => _top(upper) - _top(lower);
  double get facing => (upper.centre.x - lower.centre.x).sign;

  /// The middle of the lower top, a step back from the ledge.
  Vector3 get standing => Vector3(
        lower.centre.x - facing * (lower.size.x / 2.0 - 0.8),
        _top(lower),
        lower.centre.z,
      );
}

List<_Riser> _risersIn(Level level, double limit) {
  final found = <_Riser>[];
  for (final Brush lower in level.brushes) {
    for (final Brush upper in level.brushes) {
      if (identical(lower, upper)) continue;
      final rise = _top(upper) - _top(lower);
      if (rise <= 0.02 || rise > limit) continue;
      // Side by side along x, and sharing enough z to walk from one to the
      // other. Touching or overlapping counts: a plank laid on a terrace does
      // both.
      final apartX = (upper.centre.x - lower.centre.x).abs() -
          (lower.size.x + upper.size.x) / 2.0;
      final apartZ = (upper.centre.z - lower.centre.z).abs() -
          (lower.size.z + upper.size.z) / 2.0;
      if (apartX > 0.2 || apartZ > -1.5) continue;
      found.add(_Riser(lower, upper));
    }
  }
  return found;
}

/// The shipped level, the shipped simulation, and a runner put on a ledge.
final class _Walk {
  _Walk() {
    level.addTo(world);
    runner = Runner(
      body: CharacterController(world: world, position: Vector3.zero()),
      surfaces: Surfaces.common(),
    );
    sim = PlatformerSimulation(
      runner: runner,
      collision: world,
      input: input,
      startAt: Vector3.zero(),
      levelNext: level.next,
    );
  }

  final Level level = _shipped();
  final CollisionWorld world = CollisionWorld();
  final InputState input = InputState();
  late final Runner runner;
  late final PlatformerSimulation sim;

  /// Every drawn height the run produced, smoothed and plain.
  final List<double> smoothed = <double>[];
  final List<double> plain = <double>[];

  /// The tallest ledge the controller reported climbing.
  double climbed = 0.0;

  /// Stands on [riser]'s lower top and walks across it.
  void cross(_Riser riser, {int steps = 150}) {
    runner.body.teleport(
      riser.standing + Vector3(0.0, runner.body.halfExtents.y + 0.05, 0.0),
    );
    // Let the body settle before anything is recorded, so the first drawn
    // height is a standing one rather than a landing.
    for (var i = 0; i < 20; i++) {
      sim.step(_dt);
    }

    // Exactly the application's two interpolators: one built the way `main.dart`
    // builds it at load, one the way it did before.
    final smooth = InterpolatedVector3(
      initial: runner.body.position,
      stepLimit: runner.body.tuning.stepHeight,
    );
    final flat = InterpolatedVector3(initial: runner.body.position);
    final out = Vector3.zero();

    for (var i = 0; i < steps; i++) {
      input.beginStep();
      input.press(GameAction.moveForward);
      // The camera owns "forward", as it does in the game.
      sim.cameraYaw = riser.facing > 0 ? math.pi / 2.0 : -math.pi / 2.0;
      sim.step(_dt);
      input.endStep();

      climbed = math.max(climbed, runner.body.steppedUp);
      smooth.push(runner.body.position,
          dt: _dt, steppedUp: runner.body.steppedUp);
      flat.push(runner.body.position);

      smooth.read(1.0, out);
      smoothed.add(out.y);
      flat.read(1.0, out);
      plain.add(out.y);
    }
  }
}

/// The fastest the drawn body ever rises, in metres per second.
double _fastestRise(List<double> heights) {
  var most = 0.0;
  for (var i = 1; i < heights.length; i++) {
    most = math.max(most, (heights[i] - heights[i - 1]) / _dt);
  }
  return most;
}

void main() {
  test('the shipped level is full of ledges a walk climbs', () {
    // The reason this work pays off on content that already exists. Measured,
    // and the measurement is the one this file's rule makes: **eleven**, where
    // a looser count that does not ask whether the two tops share enough depth
    // to walk between says eighteen. The smaller number is the one that means
    // anything, because the other includes ledges nothing can cross.
    final level = _shipped();
    final risers = _risersIn(level, const MovementTuning().stepHeight);

    expect(risers.length, greaterThanOrEqualTo(8),
        reason: 'only ${risers.length} low ledges — if the level really lost '
            'them, this smoothing has stopped earning its place');
  });

  test('a riser in Ascent is drawn as a climb, not as a jump', () {
    final walk = _Walk();
    final risers =
        _risersIn(walk.level, walk.runner.body.tuning.stepHeight);

    // The first one the runner actually gets over. Not every low ledge is
    // walkable — some are under something, some are the top of a wall — and a
    // test that assumed the first candidate would be the one would be a test of
    // whichever order the brushes happen to be in.
    for (final riser in risers) {
      walk.cross(riser);
      if (walk.climbed > 0.0) break;
      walk.smoothed.clear();
      walk.plain.clear();
    }

    expect(walk.climbed, greaterThan(0.0),
        reason: 'never climbed anything, so nothing below is about smoothing');

    final rawly = _fastestRise(walk.plain);
    final smoothly = _fastestRise(walk.smoothed);

    // What the picture used to do: the whole ledge inside one step.
    expect(rawly, greaterThan(walk.climbed / _dt * 0.9),
        reason: 'the plain interpolator did not show the teleport, so the '
            'comparison below is between two smooth pictures');
    // And what it does now. A fifth is not a threshold anybody chose: it is
    // three times the margin the recovery gives, so a slower constant would
    // still pass and a broken one could not.
    expect(smoothly, lessThan(rawly / 5.0));
  });
}
