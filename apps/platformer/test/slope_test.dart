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

const List<String> _levels = <String>[
  'assets/levels/first_steps.json',
  'assets/levels/ascent.json',
];

Level _shipped([String path = 'assets/levels/first_steps.json']) =>
    Level.fromJson(
      jsonDecode(File(path).readAsStringSync()) as Map<String, Object?>,
    );

/// Where a ramp is walked onto, and which way from there.
///
/// The foot is the tapering end: the one a body can step onto because it is at
/// floor level. Approached from any other side a ramp is a wall.
({Vector3 foot, Vector3 towards}) _approach(Brush ramp) {
  final uphill = ramp.ramp!;
  final along = Vector3(uphill.x, 0.0, uphill.z);
  final half = uphill.axis == 0 ? ramp.size.x / 2.0 : ramp.size.z / 2.0;
  return (
    foot: ramp.centre - along.scaled(half) - Vector3(0.0, ramp.size.y / 2.0, 0.0),
    towards: along,
  );
}

/// The shipped level, and a runner that can be walked about in it.
final class _Walk {
  _Walk([String path = 'assets/levels/first_steps.json'])
      : level = _shipped(path) {
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

  final Level level;
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

  /// Whether there is anything solid under [at] to stand on.
  bool groundUnder(Vector3 at) {
    for (final brush in level.brushes) {
      if (!brush.solid || brush.isRamp) continue;
      final min = brush.min;
      final max = brush.max;
      if (at.x > min.x && at.x < max.x && at.z > min.z && at.z < max.z &&
          max.y <= at.y + 0.5 && max.y > at.y - 3.0) {
        return true;
      }
    }
    return false;
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
    // Only while on the ramp: past the crest the body is on whatever the ramp
    // leads to, and a drop off the far end is not a fact about slopes.
    final uphill = ramp.ramp!;
    final axis = uphill.axis;
    final half = axis == 0 ? ramp.size.x / 2.0 : ramp.size.z / 2.0;
    final centre = axis == 0 ? ramp.centre.x : ramp.centre.z;
    final sign = uphill.sign;
    for (var i = 0; i < steps; i++) {
      input.beginStep();
      input.press(GameAction.moveForward);
      sim.cameraYaw = yaw;
      sim.step(_dt);
      input.endStep();
      highest = math.max(highest, runner.position.y);
      final at = axis == 0 ? runner.position.x : runner.position.z;
      // How far up the climb the body is, from nought at the foot to one at
      // the crest.
      final up = (sign * (at - centre) / half + 1.0) / 2.0;
      if (!runner.isGrounded && up > 0.05 && up < 0.92) airborne++;
    }
    return (highest: highest, airborne: airborne);
  }
}

void main() {
  test('the shipped levels have slopes in them at all', () {
    // The whole point of the format learning the word. If a generator ever
    // stops emitting one, everything below passes by having nothing to check.
    var total = 0;
    for (final path in _levels) {
      total += _shipped(path).brushes.where((Brush b) => b.isRamp).length;
    }
    expect(total, greaterThanOrEqualTo(2));
  });

  for (final path in _levels) {
    final level = _shipped(path);
    final ramps = level.brushes.where((Brush b) => b.isRamp).toList();

    group(path.split('/').last, () {
      for (var i = 0; i < ramps.length; i++) {
        final ramp = ramps[i];
        final approach = _approach(ramp);
        final degrees = math.atan2(
              ramp.size.y,
              ramp.ramp!.axis == 0 ? ramp.size.x : ramp.size.z,
            ) *
            180.0 /
            math.pi;

        test('ramp $i is a slope a body can stand on', () {
          // Under sixty degrees is the controller's own limit for a floor;
          // over ten is the difference between a ramp and a rounding error.
          expect(degrees, greaterThan(8.0));
          expect(degrees, lessThan(50.0));
        });

        test('ramp $i has ground at the foot of it', () {
          // **The mistake this test exists for, and it has now been made
          // twice.** A ramp whose tapering end is over a hole is a perfectly
          // valid brush that nothing complains about: the first placement in
          // `ascent.json` put its foot at z = 26, and the field ends at z = 25
          // where the drop begins. There is no way onto a ramp you cannot
          // reach.
          final walk = _Walk(path);
          expect(
            walk.groundUnder(approach.foot - approach.towards.scaled(1.5)),
            isTrue,
            reason: 'nothing to stand on in front of the ramp at '
                '${ramp.centre}',
          );
        });

        test('ramp $i is walked up, and walked rather than flown', () {
          // Through the shipped simulation, with the shipped tuning and
          // surfaces. The wedge's own tests build a ramp in code; this one
          // asks whether the ramp in the level is any use.
          final walk = _Walk(path);
          walk.standAt(approach.foot - approach.towards.scaled(2.0));
          final startY = walk.runner.position.y;

          final yaw = math.atan2(approach.towards.x, approach.towards.z);
          final climbed = walk.walk(yaw, 300);

          expect(climbed.highest, greaterThan(startY + ramp.size.y * 0.8),
              reason: 'walked into the ramp at ${ramp.centre} instead of up '
                  'it: reached ${climbed.highest} from $startY');
          expect(climbed.airborne, 0,
              reason: 'left the ground walking up the ramp at ${ramp.centre}');
        });
      }
    });
  }

  test('the coin at the top of the teaching slope is above it, not inside', () {
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
