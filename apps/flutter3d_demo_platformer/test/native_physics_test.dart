/// The shipped level on the native core, held against the reference.
///
/// The game steps its crates with `NativeDynamics`; `stage` takes any
/// `RigidDynamics`, and this builds the level on both and plays it the way
/// `playthrough_test` does. What is held: every crate lands where the
/// reference lands it and none falls out of the world, the runner crosses
/// what it crosses with the reference, a crate pushed moves, and two runs on
/// the core land on the same bits.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter3d_demo_platformer/src/staging.dart';
import 'package:flutter3d_game_platformer/flutter3d_game_platformer.dart';
import 'package:flutter3d_physics_native/flutter3d_physics_native.dart';
import 'package:flutter3d_sim/flutter3d_sim.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

const double _dt = 1.0 / 60.0;

Level _shipped() => Level.fromJson(
  jsonDecode(File('assets/levels/ascent.json').readAsStringSync())
      as Map<String, Object?>,
);

/// The shipped level staged on [native] or the reference, and stepped.
final class _Game {
  _Game({required bool native}) {
    level.addTo(world);
    staged = stage(
      level,
      world,
      input: input,
      registry: platformerRegistry(),
      dynamicsFor: native
          ? (world) {
              final dynamics = NativeDynamics(world: world);
              addTearDown(dynamics.dispose);
              return dynamics;
            }
          : (world) => Dynamics(world: world),
    );
  }

  final Level level = _shipped();
  final CollisionWorld world = CollisionWorld();
  final InputState input = InputState();
  late final Staged staged;

  List<RigidBody> get crates => staged.dynamics.bodies;

  bool _forward = false;
  bool _jump = false;

  void step({bool forward = false, bool jump = false}) {
    input.beginStep();
    if (forward != _forward) {
      forward
          ? input.press(GameAction.moveForward)
          : input.release(GameAction.moveForward);
      _forward = forward;
    }
    if (jump != _jump) {
      jump ? input.press(GameAction.jump) : input.release(GameAction.jump);
      _jump = jump;
    }
    staged.sim.step(_dt);
    input.endStep();
  }

  void settle(int steps) {
    for (var i = 0; i < steps; i++) {
      step();
    }
  }

  /// Forward, jumping on the rhythm `playthrough_test` uses.
  void autopilot(int steps) {
    for (var i = 0; i < steps; i++) {
      step(forward: true, jump: i % 30 < 22);
    }
  }
}

/// Whether [crate] starts more than a centimetre deep in level geometry
/// other than what it stands on, by their boxes.
bool _inWall(RigidBody crate, CollisionWorld world) {
  final c = crate.collider.bounds;
  for (final other in world.statics) {
    final o = other.bounds;
    final dx = math.min(c.max.x, o.max.x) - math.max(c.min.x, o.min.x);
    final dy = math.min(c.max.y, o.max.y) - math.max(c.min.y, o.min.y);
    final dz = math.min(c.max.z, o.max.z) - math.max(c.min.z, o.min.z);
    if (dx > 0.01 && dy > 0.01 && dz > 0.01) return true;
  }
  return false;
}

void main() {
  test('the level stages on the core and its crates land where the '
      'reference lands them', () {
    final native = _Game(native: true);
    final reference = _Game(native: false);
    expect(native.staged.dynamics, isA<NativeDynamics>());
    expect(native.crates, isNotEmpty);
    expect(native.crates.length, reference.crates.length);
    // A crate placed inside a wall is pushed out of it by each solver its
    // own way, and may land elsewhere by centimetres. The shipped level has
    // nine of them: four 1.4 m wide in gaps of a metre between pillars, and
    // five half sunk in a step. Those are held only to stay in the world;
    // the rest must agree.
    final jammed = <int>{
      for (var i = 0; i < reference.crates.length; i++)
        if (_inWall(reference.crates[i], reference.world)) i,
    };
    native.settle(180);
    reference.settle(180);
    for (var i = 0; i < native.crates.length; i++) {
      final a = native.crates[i].position, b = reference.crates[i].position;
      expect(a.y, greaterThan(-1.0), reason: 'crate $i fell out');
      if (jammed.contains(i)) continue;
      expect(
        a.distanceTo(b),
        lessThan(0.05),
        reason: 'crate $i: core $a, reference $b',
      );
      expect(native.crates[i].isAsleep, isTrue, reason: 'crate $i');
    }
  });

  test('the runner crosses on the core what it crosses on the '
      'reference', () {
    final native = _Game(native: true);
    final reference = _Game(native: false);
    native.autopilot(600);
    reference.autopilot(600);
    final a = native.staged.runner.position;
    final b = reference.staged.runner.position;
    // The runner does not stand on a crate on this route, so nothing the
    // core does reaches it: it walks exactly as it walks on the reference.
    expect(a, b);
    for (final crate in native.crates) {
      expect(crate.position.y, greaterThan(-20.0));
      expect(crate.position.x.isFinite, isTrue);
    }
  });

  test('a crate a walker walks into moves', () {
    final game = _Game(native: true)..settle(60);
    final crate = game.crates.first;
    final before = crate.position.clone();
    final half = (crate.collider.shape as CollisionBox).halfExtents;
    // A walker standing against the crate's +z face, walking into it: the
    // push `Runner` gives a crate, without steering a runner there.
    final walker = game.world.add(
      Collider(
        shape: CollisionCapsule(radius: 0.3, halfHeight: 0.3),
        position: before + Vector3(0.0, 0.0, half.z + 0.3 + 0.005),
        kind: ColliderKind.kinematic,
      ),
    );
    game.staged.dynamics.push(walker, Vector3(0.0, 0.0, -3.0));
    game.world.remove(walker);
    game.settle(30);
    expect(crate.position.z, lessThan(before.z - 0.1));
  });

  test('a run restored from a save taken as a shoved crate comes to rest '
      'steps on to the same bits, as a rewind needs', () {
    final game = _Game(native: true)..settle(60);
    // A crate shoved across the floor.
    final crate = game.crates.first;
    final half = (crate.collider.shape as CollisionBox).halfExtents;
    final walker = game.world.add(
      Collider(
        shape: CollisionCapsule(radius: 0.3, halfHeight: 0.3),
        position: crate.position + Vector3(0.0, 0.0, half.z + 0.3 + 0.005),
        kind: ColliderKind.kinematic,
      ),
    );
    game.staged.dynamics.push(walker, Vector3(0.0, 0.0, -6.0));
    game.world.remove(walker);
    // Saved as it comes to rest: slower than sleep's threshold, the core's
    // clock counting towards sleep — which a body's own save cannot carry.
    var steps = 0;
    while (crate.velocity.length > 0.05 && steps < 120) {
      game.settle(1);
      steps++;
    }
    game.settle(3);
    expect(crate.isAsleep, isFalse);
    final mid = game.staged.sim.save();
    expect(mid.data['dynamics'], isA<String>());
    // Every step's save, as a demo's checkpoints and a rewind's resim check
    // them: a crate that fell asleep a step later ends where it would have,
    // and only the steps between say so.
    List<String> rest() => <String>[
      for (var i = 0; i < 90; i++)
        (() {
          game.settle(1);
          return jsonEncode(game.staged.sim.save().toJson());
        })(),
    ];

    final live = rest();
    game.staged.sim.restore(mid);
    final again = rest();
    for (var i = 0; i < live.length; i++) {
      if (live[i] == again[i]) continue;
      final a = jsonDecode(live[i]), b = jsonDecode(again[i]);
      void diff(Object? x, Object? y, String path) {
        if (x is Map && y is Map) {
          for (final k in {...x.keys, ...y.keys}) {
            diff(x[k], y[k], '$path/$k');
          }
        } else if (x is List && y is List && x.length == y.length) {
          for (var j = 0; j < x.length; j++) {
            diff(x[j], y[j], '$path[$j]');
          }
        } else if (jsonEncode(x) != jsonEncode(y)) {
          printOnFailure(
            'step $i $path: live ${jsonEncode(x)} again ${jsonEncode(y)}',
          );
        }
      }

      diff(a, b, '');
      break;
    }
    expect(again, live);
  });

  test('two runs on the core land on the same bits', () {
    String run() {
      final game = _Game(native: true)..autopilot(300);
      return <Object?>[for (final c in game.crates) c.save()].toString() +
          game.staged.runner.position.toString();
    }

    expect(run(), run());
  });
}
