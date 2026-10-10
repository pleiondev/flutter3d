/// Bodies walking past each other: the velocity ORCA picks, and actors that
/// use it.
///
///     dart test test/avoidance_test.dart
///
/// The claim of the method is that two bodies that both take the velocity it
/// picks do not touch within the horizon, and that a body with nobody in the
/// way is not turned at all. The actors at the end are the same claim walked:
/// four of them crossing a floor to each other's places.
library;

import 'dart:math' as math;

import 'package:flutter3d_physics/flutter3d_physics.dart';
import 'package:flutter3d_sim/flutter3d_sim.dart';
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart';

const Avoidance _avoid = Avoidance();
const double _radius = 0.35;
const double _speed = 6.0;

/// The nearest two bodies come in [seconds], moving from their places at
/// their velocities in straight lines.
double _closest(
  (double, double) a,
  (double, double) va,
  (double, double) b,
  (double, double) vb,
  double seconds,
) {
  final rx = b.$1 - a.$1;
  final rz = b.$2 - a.$2;
  final wx = vb.$1 - va.$1;
  final wz = vb.$2 - va.$2;
  final ww = wx * wx + wz * wz;
  final t = ww == 0.0
      ? 0.0
      : (-(rx * wx + rz * wz) / ww).clamp(0.0, seconds).toDouble();
  final dx = rx + wx * t;
  final dz = rz + wz * t;
  return math.sqrt(dx * dx + dz * dz);
}

/// The velocity [_avoid] picks for a body at [at] moving at [v] and wanting
/// [want], with one neighbour at [other] moving at [ov].
(double, double) _pick(
  (double, double) at,
  (double, double) v,
  (double, double) want,
  (double, double) other,
  (double, double) ov,
) => _avoid.velocity(
  x: at.$1,
  z: at.$2,
  vx: v.$1,
  vz: v.$2,
  radius: _radius,
  maxSpeed: _speed,
  prefX: want.$1,
  prefZ: want.$2,
  neighbors: <AvoidanceNeighbor>[
    (x: other.$1, z: other.$2, vx: ov.$1, vz: ov.$2, radius: _radius),
  ],
  dt: 1 / 60,
);

void main() {
  group('the velocity', () {
    test('is the one wanted when nobody is near', () {
      final v = _avoid.velocity(
        x: 0,
        z: 0,
        vx: 0,
        vz: 0,
        radius: _radius,
        maxSpeed: _speed,
        prefX: 3,
        prefZ: -4,
        neighbors: const <AvoidanceNeighbor>[],
        dt: 1 / 60,
      );
      expect(v, (3.0, -4.0));
    });

    test('is no faster than the body goes', () {
      final v = _pick((0, 0), (0, 0), (30, 0), (0, 4), (0, 0));
      expect(math.sqrt(v.$1 * v.$1 + v.$2 * v.$2), lessThanOrEqualTo(_speed));
    });

    test('is the one wanted when the neighbour is behind and going away', () {
      final v = _pick((0, 0), (5, 0), (5, 0), (-2, 0), (-5, 0));
      expect(v.$1, closeTo(5.0, 1e-9));
      expect(v.$2, closeTo(0.0, 1e-9));
    });

    test('of two bodies head on keeps them apart, both turning', () {
      const a = (0.0, 0.0);
      const b = (4.0, 0.0);
      const va = (5.0, 0.0);
      const vb = (-5.0, 0.0);
      // Not quite on one line, as two bodies never quite are.
      final pa = _pick(a, va, va, (4.0, 0.01), vb);
      final pb = _pick((4.0, 0.01), vb, vb, a, va);
      // Mutation: taking all the turning rather than half leaves each
      // expecting the other to turn as well, and both swerve twice as far;
      // taking none of it meets head on.
      expect(pa.$2.abs(), greaterThan(0.1));
      expect(pb.$2.abs(), greaterThan(0.1));
      expect(pa.$2.sign, isNot(pb.$2.sign));
      final apart = _closest(a, pa, (4.0, 0.01), pb, _avoid.timeHorizon);
      expect(apart, greaterThanOrEqualTo(2 * _radius - 1e-6));
      // Half each is just enough: they brush past rather than give each
      // other a wide berth.
      expect(apart, lessThan(2 * _radius * 1.1));
      expect(_closest(a, va, b, vb, _avoid.timeHorizon), lessThan(2 * _radius));
    });

    test('of a body overlapping another points out of it', () {
      final v = _pick((0, 0), (0, 0), (0, 0), (0.3, 0), (0, 0));
      expect(v.$1, lessThan(0.0));
    });
  });

  group('four actors crossing to each other\'s places', () {
    List<double> run({Avoidance? avoidance}) {
      final world = CollisionWorld()
        ..addBox(Vector3(0, -0.5, 0), Vector3(30, 1, 30))
        ..update();
      final system = ActorSystem(world: world, random: GameRandom(5))
        ..avoidance = avoidance;
      final tree = BehaviorTree.read(const <String, Object?>{
        'kind': 'goTo',
        'key': 'post',
        'within': 0.3,
      }, BehaviorKinds()).tree!;
      const places = <(double, double)>[(-4, 0), (0, -4), (4, 0), (0, 4)];
      for (var i = 0; i < 4; i++) {
        final (x, z) = places[i];
        final (px, pz) = places[(i + 2) % 4];
        final actor = system.spawn(
          body: CharacterController(world: world, position: Vector3(x, 0.9, z)),
          brain: BehaviorBrain(tree),
          facing: Facing(),
          name: 'a$i',
        );
        system.entities.set(
          actor.entity,
          Blackboard(
            values: <String, Object?>{
              'post': <double>[px, 0.9, pz],
            },
          ),
        );
      }
      var closest = double.infinity;
      for (var step = 0; step < 240; step++) {
        system
          ..beginStep()
          ..step(1 / 60, focus: Vector3(0, -50, 0));
        final bodies = system.actors.map((a) => a.body!.position).toList();
        for (var i = 0; i < 4; i++) {
          for (var j = i + 1; j < 4; j++) {
            final dx = bodies[i].x - bodies[j].x;
            final dz = bodies[i].z - bodies[j].z;
            closest = math.min(closest, math.sqrt(dx * dx + dz * dz));
          }
        }
      }
      final misses = <double>[
        for (var i = 0; i < 4; i++)
          () {
            final at = system.actors.elementAt(i).body!.position;
            final (px, pz) = places[(i + 2) % 4];
            return math.sqrt(
              (at.x - px) * (at.x - px) + (at.z - pz) * (at.z - pz),
            );
          }(),
      ];
      return <double>[closest, ...misses];
    }

    test('pass each other and arrive', () {
      final result = run(avoidance: _avoid);
      // Moved exactly at the velocities picked, the four stay 98 per cent of
      // two radii apart: a later one picks against the others' new speeds
      // in the same step. Through the controller a turn takes a few steps
      // of acceleration, and they keep 94 per cent. Mutation: asking the
      // controller for the velocity itself, not along the difference to it,
      // turns them too slowly and they close to 70.
      expect(result.first, greaterThanOrEqualTo(2 * _radius * 0.9));
      expect(result.skip(1), everyElement(lessThan(0.5)));
    });

    test('meet in the middle without it', () {
      final result = run();
      expect(result.first, lessThan(2 * _radius * 0.95));
    });
  });
}
