/// `pro-sim-02`'s own particle half: a [ParticleSystem] advanced one frame
/// at a time into the same [SimulationCache] the rigid-body and cloth halves
/// bake into.
///
/// **Padded to [ParticleSystem.capacity], not to how many happen to be
/// alive.** [SimulationCache] holds one fixed `vertexCount` across every
/// frame — its own constructor throws otherwise — and how many particles
/// are alive changes frame to frame as a system emits and ages them out.
/// Capacity is the one number that does not change once a system is built,
/// so it is what this bakes to: a dead slot writes as `(0, 0, 0)`, the same
/// answer [ParticleSystem.writeInstances] already gives a slot past its own
/// `aliveCount`. A player scrubbing the cache sees exactly what the system
/// itself would have drawn that frame, dead particles included — this is
/// not a second decision about what "dead" looks like, only where that
/// answer is captured.
///
/// **Deterministic because [ParticleSystem] already is.** Its own doc
/// comment says so: the same seed and the same sequence of [ParticleSystem
/// .advance] calls give byte-identical particles. Building [system] with an
/// explicit `seed` and calling [advancePerFrame] with nothing else touching
/// it in between is what `pro-sim-02`'s own acceptance — "частицы
/// детерминированы" — asks for, already true of the type this bakes rather
/// than a property this file adds.
library;

import 'dart:typed_data';

import 'package:flutter3d_particles_core/flutter3d_particles_core.dart';

import 'simulation_cache.dart';

/// Bakes [frameCount] frames of [system], advancing it by [dt] seconds
/// between each — [advancePerFrame] runs once per frame, so a caller wanting
/// an emission already burning when the cache starts advances [system]
/// itself first.
///
/// [system] is read, not owned: nothing here calls [ParticleSystem.clear],
/// so a caller keeps whatever else it wanted the same instance for.
final class BakeParticleSystemJobRequest implements SimulationBakeRequest {
  BakeParticleSystemJobRequest({
    required this.objectId,
    required this.baseVersion,
    required this.system,
    this.frameCount = 180,
    this.dt = 1.0 / 60.0,
    void Function(double dt)? advancePerFrame,
    this.label = 'Particles',
  }) : advancePerFrame = advancePerFrame ?? system.advance;

  @override
  final int objectId;
  @override
  final int baseVersion;
  final ParticleSystem system;
  @override
  final int frameCount;
  final double dt;
  final String label;

  /// What one frame of baking does to [system] before its positions are
  /// read — [ParticleSystem.advance] by default, so a caller that has
  /// already called [ParticleSystem.emit] gets ordinary emission-and-step
  /// behaviour without naming this at all.
  final void Function(double dt) advancePerFrame;

  @override
  int get vertexCount => system.capacity;

  Future<SimulationCache> buildCache() async {
    final instances = Float32List(
      system.capacity * ParticleSystem.floatsPerInstance,
    );
    final frames = <Float32List>[];
    for (var i = 0; i < frameCount; i++) {
      advancePerFrame(dt);

      instances.fillRange(0, instances.length, 0.0);
      system.writeInstances(instances);

      final frame = Float32List(vertexCount * 3);
      for (var p = 0; p < system.capacity; p++) {
        final at = p * ParticleSystem.floatsPerInstance;
        frame[p * 3] = instances[at];
        frame[p * 3 + 1] = instances[at + 1];
        frame[p * 3 + 2] = instances[at + 2];
      }
      frames.add(frame);
    }

    return SimulationCache(vertexCount: vertexCount, frames: frames);
  }

  @override
  Future<SimulationCache> bake() => buildCache();
}
