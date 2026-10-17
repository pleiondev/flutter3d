/// A body walking voxel ground on the physics the build asked for.
///
///     flutter test test/voxel_physics_test.dart
///     flutter test --dart-define=FLUTTER3D_PHYSICS=dart test/voxel_physics_test.dart
///
/// The first runs on the native core — the body moved by it, the world's
/// statics, every chunk's boxes, mirrored into it — and the second on the
/// Dart reference. The same claims hold on both: the body walks the ground,
/// a wall built in front of it stops it, and a pit dug in front of it is a
/// pit it falls into. Both of those edits replace boxes the core has
/// already mirrored, so they hold only if it mirrors them again.
library;

import 'dart:math' as math;

import 'package:flutter3d_demo_sandbox/src/staging.dart';
import 'package:flutter3d_physics_native/flutter3d_physics_native.dart';
import 'package:flutter3d_sim/flutter3d_sim.dart';
import 'package:flutter3d_voxel/flutter3d_voxel.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

/// Level ground four deep, the body at `(8.5, 8.5)` facing +x.
Future<SandboxRun> _plot() async {
  final started = await startPhysics();
  final run = SandboxRun(
    VoxelWorld(
      chunksX: 2,
      chunksY: 1,
      chunksZ: 2,
      terrain: const VoxelTerrain.flat(4),
    ),
    backend: started.backend,
    at: Vector3(8.5, 4.95, 8.5),
    yaw: math.pi / 2,
  );
  addTearDown(() => started.backend.release(run.physics));
  return run;
}

/// [steps] steps, walking forward when [forward].
void _walk(SandboxRun run, int steps, {bool forward = true}) {
  final input = InputState();
  if (forward) input.press(GameAction.moveForward);
  for (var i = 0; i < steps; i++) {
    run.step(1 / 60, input);
    input.endStep();
  }
}

void main() {
  test('the build\'s physics is the one the body moves on', () async {
    final run = await _plot();
    // Mutation: not attaching the run's backend leaves the body on its own
    // sweeps with the core loaded and idle.
    expect(run.physics.characterMover != null, askedPhysics != 'dart');
    expect(physicsFallbackReason, isNull, reason: 'the core did not start');
  });

  test('a body walks the ground, and a wall built ahead stops it', () async {
    final run = await _plot();
    _walk(run, 30, forward: false);
    expect(run.walk.body.isGrounded, isTrue);
    expect(run.walk.body.position.y, closeTo(4.9, 0.02));

    // A wall two high across x = 12, built through the run as a player
    // builds — each edit replacing a chunk's boxes the core has mirrored.
    for (var z = 4; z < 13; z++) {
      for (final y in <int>[4, 5]) {
        expect(run.blocks.edit(12, y, z, 5), isTrue);
      }
    }
    final changes = run.blocks.drainChanges();
    run.collision.refresh(changes.chunks);
    run.navigation.follow(changes);

    _walk(run, 120);
    // Mutation: refreshing the boxes without the world's revision moving
    // — or a core that mirrors statics once — walks it through the wall.
    expect(run.walk.body.position.x, closeTo(12.0 - 0.35, 0.02));
    expect(run.walk.body.isGrounded, isTrue);
  });

  test('a pit dug ahead is one the body falls into', () async {
    final run = await _plot();
    _walk(run, 30, forward: false);
    for (var x = 11; x < 14; x++) {
      for (var z = 6; z < 11; z++) {
        for (final y in <int>[3, 2, 1]) {
          run.blocks.edit(x, y, z, Voxels.empty);
        }
      }
    }
    final changes = run.blocks.drainChanges();
    run.collision.refresh(changes.chunks);

    _walk(run, 50);
    _walk(run, 60, forward: false);
    expect(run.walk.body.position.x, inInclusiveRange(11.0, 14.0));
    expect(run.walk.body.position.y, closeTo(1.9, 0.02));
    expect(run.walk.body.isGrounded, isTrue);
  });
}
