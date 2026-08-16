/// The slope in the teaching level, walked.
///
///     flutter test test/slope_test.dart
///
/// **The wedge has tests and the level has a wedge, and neither of those says
/// a player can use it.** `packages/flutter3d_physics/test/wedge_test.dart`
/// builds a ramp in code and walks a bare `CharacterController` up it; this
/// loads `first_steps.json` off disk and drives the shipped simulation, with
/// the shipped tuning and the shipped surfaces, the way the application does.
///
/// It exists because the first placement passed every one of those other tests
/// and was still unusable: its thin end sat a metre and a half *behind* the
/// spawn against the back wall, so the only way up was to walk backwards, and
/// approached from the side at the spawn's own z the slope's edge stood 0.43 m
/// against a step of 0.40 — three centimetres too tall, which looks walkable
/// and is not.
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
      jsonDecode(File('assets/levels/first_steps.json').readAsStringSync())
          as Map<String, Object?>,
    );

/// The shipped level, and a runner that can be walked about in it.
final class _Walk {
  _Walk() {
    level.addTo(world);
    final start = level.playerStart?.position ?? Vector3.zero();
    runner = Runner(
      body: CharacterController(
        world: world,
        position: start + Vector3(0.0, 0.9, 0.0),
      ),
      surfaces: Surfaces.common(),
    );
    sim = PlatformerSimulation(
      runner: runner,
      collision: world,
      input: input,
      startAt: start,
      levelNext: level.next,
    );
  }

  final Level level = _shipped();
  final CollisionWorld world = CollisionWorld();
  final InputState input = InputState();
  late final Runner runner;
  late final PlatformerSimulation sim;

  Brush get ramp => level.brushes.firstWhere((Brush b) => b.isRamp);

  /// Stands the runner at [at] and lets it settle.
  void standAt(Vector3 at) {
    runner.body.teleport(at + Vector3(0.0, 0.9, 0.0));
    for (var i = 0; i < 20; i++) {
      sim.step(_dt);
    }
  }

  /// Walks towards [yaw] for [steps], and says how it went.
  ///
  /// [airborne] counts only the steps taken **on the ramp itself**, between its
  /// foot and its crest. Past the crest the body is on the ledge and then off
  /// the end of it, and a fall of two metres onto the floor is not a fact about
  /// slopes.
  ({double highest, int airborne}) walk(double yaw, int steps) {
    var highest = runner.position.y;
    var airborne = 0;
    final foot = ramp.centre.z - ramp.size.z / 2.0;
    final crest = ramp.centre.z + ramp.size.z / 2.0;
    for (var i = 0; i < steps; i++) {
      input.beginStep();
      input.press(GameAction.moveForward);
      sim.cameraYaw = yaw;
      sim.step(_dt);
      input.endStep();
      highest = math.max(highest, runner.position.y);
      final z = runner.position.z;
      if (!runner.isGrounded && z > foot && z < crest - 0.5) airborne++;
    }
    return (highest: highest, airborne: airborne);
  }
}

void main() {
  test('the teaching level has a slope, and it is a gentle one', () {
    // Eighteen degrees, and the number is the size rather than a field: the cut
    // runs corner to corner. A ramp steeper than the walkable limit of sixty
    // degrees would be a wall, and one barely off the floor would be a joke.
    final ramp = _Walk().ramp;
    final degrees =
        math.atan2(ramp.size.y, ramp.size.z) * 180.0 / math.pi;

    expect(ramp.ramp, WedgeUphill.positiveZ);
    expect(degrees, greaterThan(10.0));
    expect(degrees, lessThan(30.0));
  });

  test('its foot is in front of the player, not behind them', () {
    // **What the first placement got wrong.** A ramp whose thin end is behind
    // the spawn is one you have to walk backwards to use, and nothing in the
    // tutorial has taught the player to turn round.
    final walk = _Walk();
    final spawn = walk.level.playerStart!.position;
    final foot = walk.ramp.centre.z - walk.ramp.size.z / 2.0;

    expect(foot, greaterThan(spawn.z),
        reason: 'the way up starts behind where the player starts');
  });

  test('walking forward beside the wall becomes walking uphill', () {
    // The claim, through the shipped simulation: a player who does the only
    // thing the first room asks — go forward — ends up two metres higher
    // without ever deciding to climb.
    final walk = _Walk();
    final ramp = walk.ramp;
    final foot = ramp.centre.z - ramp.size.z / 2.0;
    walk.standAt(Vector3(ramp.centre.x, 0.0, foot - 2.0));
    final startY = walk.runner.position.y;

    // Forward is +z, which is a camera yaw of nought.
    final climbed = walk.walk(0.0, 240);

    expect(climbed.highest, greaterThan(startY + 1.8),
        reason: 'walked into the slope instead of up it');
    expect(walk.runner.position.z, greaterThan(ramp.centre.z),
        reason: 'stopped somewhere on the way up');
  });

  test('and it is walked rather than flown', () {
    // A ramp the runner leaves the ground on is a ramp that reads as a jump
    // pad. Measured on the shipped level, not on a fixture.
    //
    // **The crest is left out of the count on purpose, and it is not nothing.**
    // A *box* swept against a slope touches it at its downhill bottom corner,
    // so its centre rides about 1.02 m above the surface on an eighteen-degree
    // ramp instead of the 0.90 it sits at on the flat. Stepping off the top
    // onto level ground is therefore a drop of a dozen centimetres, and the
    // body is airborne for four steps while it happens. That is geometry, not a
    // defect: it is what a box on a slope is, and the fix would be a body that
    // is not a box.
    final walk = _Walk();
    final ramp = walk.ramp;
    walk.standAt(
      Vector3(ramp.centre.x, 0.0, ramp.centre.z - ramp.size.z / 2.0 - 2.0),
    );

    final climbed = walk.walk(0.0, 180);

    expect(climbed.airborne, 0, reason: 'left the ground walking up a slope');
  });

  test('the coin at the top is above the slope, not inside it', () {
    // The generator's buried check knows a ramp's box is half empty, and this
    // is the shipped-content half of that: the reward for the climb has to be
    // somewhere a player can reach.
    final walk = _Walk();
    final coin = walk.level.entities.firstWhere(
      (EntityDef e) => e.name == 'the coin at the top of the slope',
    );

    for (final brush in walk.level.brushes) {
      if (!brush.isRamp) continue;
      final wedge = CollisionWedge(brush.halfExtents, uphill: brush.ramp!);
      expect(wedge.containsPoint(brush.centre, coin.position), isFalse,
          reason: 'the coin is inside the slope');
    }
  });
}
