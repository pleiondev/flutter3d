/// `pro-sim-02`'s own rigid-body half: a box dropped through `Dynamics`, one
/// frame at a time, into the same [SimulationCache] `pro-sim-01`'s cloth
/// solver already bakes into — see `simulation_bake.dart`'s own doc comment
/// for why a cache rather than a live simulation.
///
/// **No rotation, on purpose.** `pro-sim-02`'s own row asks for this
/// explicitly: a box that only translates needs no basis to carry along
/// with its position, so every frame is [halfExtents]'s own eight corners
/// plus [RigidBody.position] — the cheapest cache a rigid body can bake to,
/// and the honest scope a single unconstrained body actually needs. A body
/// that tips over is `pro-sim-02`'s own future row, not this one's.
library;

import 'dart:typed_data';

import 'package:flutter3d_physics/flutter3d_physics.dart';
import 'package:vector_math/vector_math.dart';

import 'simulation_cache.dart';

/// The eight corners of a box [halfExtents] on a side, centred on the
/// origin — the same corner order [SimulationCache]'s own frames hold them
/// in from one bake to the next, since nothing here ever reorders them.
List<Vector3> _boxCorners(Vector3 halfExtents) => <Vector3>[
  for (final sx in <double>[-1, 1])
    for (final sy in <double>[-1, 1])
      for (final sz in <double>[-1, 1])
        Vector3(sx * halfExtents.x, sy * halfExtents.y, sz * halfExtents.z),
];

/// Bakes [frameCount] frames of a box, [halfExtents] on a side, falling from
/// [startPosition] onto a floor at `y = 0`, [dt] seconds apart.
///
/// **A floor is always there.** `pro-sim-02`'s own acceptance — "cube falls
/// and stops" — needs something for it to stop *on*; a caller with its own
/// floor already in the scene bakes against a taller drop instead of
/// against no floor at all, since a body that never lands never stops.
///
/// [objectId] and [baseVersion] ride along for [label]'s own reason:
/// nothing here reads either, and a caller building [ApplySimulationCache]
/// from the result names both itself. [label] is the row's own "с
/// подписью" — what a cache-status strip shows for a bake nothing else here
/// distinguishes from another rigid body's.
final class BakeRigidBodyCommand {
  BakeRigidBodyCommand({
    required this.objectId,
    required this.baseVersion,
    required this.halfExtents,
    required this.startPosition,
    this.mass = 1.0,
    this.frameCount = 180,
    this.dt = 1.0 / 60.0,
    this.label = 'Rigid body',
  });

  final int objectId;
  final int baseVersion;
  final Vector3 halfExtents;
  final Vector3 startPosition;
  final double mass;
  final int frameCount;
  final double dt;
  final String label;

  /// Always eight — the box's own corners, never resampled.
  int get vertexCount => 8;

  /// Runs the whole drop and hands back the finished cache.
  ///
  /// **On the calling isolate, like `RetargetClipJobRequest`.** `Dynamics`
  /// stepping a single body a few hundred times costs microseconds, the
  /// same size class that row's own doc comment draws the line at — nothing
  /// here approaches the per-vertex cost `JobRequest`'s own isolate
  /// crossing exists for.
  Future<SimulationCache> buildCache() async {
    final world = CollisionWorld();
    world.addBox(Vector3(startPosition.x, -0.5, startPosition.z), Vector3(40.0, 1.0, 40.0));
    world.update();

    final dynamics = Dynamics(world: world);
    final body = dynamics.add(
      RigidBody(
        world: world,
        shape: CollisionBox(halfExtents),
        position: startPosition,
        mass: mass,
      ),
    );

    final corners = _boxCorners(halfExtents);
    final frames = <Float32List>[];
    for (var i = 0; i < frameCount; i++) {
      dynamics.step(dt);
      world.update();
      world.clearKinematicDeltas();

      final frame = Float32List(vertexCount * 3);
      for (var v = 0; v < vertexCount; v++) {
        final corner = corners[v] + body.position;
        frame[v * 3] = corner.x;
        frame[v * 3 + 1] = corner.y;
        frame[v * 3 + 2] = corner.z;
      }
      frames.add(frame);
    }

    return SimulationCache(vertexCount: vertexCount, frames: frames);
  }
}
