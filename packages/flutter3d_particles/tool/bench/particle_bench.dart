// ignore_for_file: avoid_print — a command-line benchmark whose whole output is
// stdout.
//
// What the particle simulation costs, so the storage question stops being
// settled by two comments arguing with each other.
//
// One comment in `particle.dart` says pooled objects are fine at a few thousand
// particles and struct-of-arrays would not be measurable. Another engine's
// particle storage is SoA with a dense prefix and says so is why. Both are
// plausible; neither is a measurement.
//
// The number that decides it is not the layout, though — it is how many slots
// each frame touches. `step`, `writeQuads` and `aliveCount` all walk the whole
// pool, and `aliveCount` runs every frame from `ParticleContributor.isActive`.
// The dungeon runs `capacity: 3000` with a steady state near 200 alive, so the
// question is whether 15x too many slot visits is worth anything.
//
// Standalone Dart on purpose, as `flutter3d/tool/bench` is: compiled with
// `dart compile exe` it goes through the same AOT pipeline a release build
// uses, so the numbers are the shipped ones rather than JIT warm-up.
//
//   dart compile exe tool/bench/particle_bench.dart -o /tmp/pbench && /tmp/pbench

import 'dart:typed_data';

import 'package:flutter3d_particles/src/particle.dart';
import 'package:flutter3d_particles/src/particle_affector.dart';
import 'package:flutter3d_particles/src/particle_emitter.dart';
import 'package:flutter3d_particles/src/particle_system.dart';
import 'package:vector_math/vector_math.dart';

void bench(String name, int iterations, void Function() body,
    {int? items, String unit = 'particle'}) {
  body(); // one untimed run, so first-call paths are not counted

  final stopwatch = Stopwatch()..start();
  for (var i = 0; i < iterations; i++) {
    body();
  }
  stopwatch.stop();

  final perIteration = stopwatch.elapsedMicroseconds / iterations;
  final label = perIteration >= 1000
      ? '${(perIteration / 1000).toStringAsFixed(2)} ms'
      : '${perIteration.toStringAsFixed(1)} us';
  var line = '${name.padRight(52)} $label';
  if (items != null && items > 0) {
    line += '   (${(perIteration * 1000 / items).toStringAsFixed(1)} ns/$unit)';
  }
  print(line);
}

/// The dungeon's flame, which is the effect that actually runs continuously.
ParticleEffect flame() => ParticleEffect(
      count: 1,
      emitter: const ConeEmitter(
        speed: Range(0.22, 0.55),
        halfAngleDegrees: 10.0,
      ),
      lifetime: const Range(0.20, 0.40),
      size: const Range(0.10, 0.19),
      color: Vector4(2.4, 1.1, 0.35, 1.0),
      affectors: <ParticleAffector>[
        const ParticleGravity(1.1),
        const ParticleDrag(2.6),
        ParticleColorOverLife(
          Vector4(2.4, 1.1, 0.35, 1.0),
          Vector4(1.0, 0.25, 0.05, 1.0),
        ),
        const ParticleFade(startsAt: 0.35),
        const ParticleSizeOverLife(from: 1.0, to: 0.25),
      ],
    );

/// A system holding [alive] particles that will not die during a measurement.
///
/// The first version of this benchmark measured `step` by calling it in a loop
/// with no emission, which drained the system within a few iterations — so it
/// timed an *empty* pool. That was invisible before compaction, because
/// scanning an empty pool of 3000 still costs something; afterwards it read as
/// 0.0us and gave the change credit it had not earned. Long lifetimes keep the
/// live set live.
ParticleSystem populated({required int capacity, required int alive}) {
  final system = ParticleSystem(capacity: capacity);
  system.burst(
    ParticleEffect(
      count: alive,
      emitter: const SphereEmitter(speed: Range(0.5, 2.0)),
      lifetime: const Range.exact(1e6),
      size: const Range(0.10, 0.19),
      color: Vector4(2.4, 1.1, 0.35, 1.0),
      affectors: flame().affectors,
    ),
    Vector3(0.0, 1.0, 0.0),
  );
  return system;
}

/// A system in the dungeon's steady state: a big pool, a small live set.
ParticleSystem warmed({required int capacity, required int torches}) {
  final system = ParticleSystem(capacity: capacity);
  final effect = flame();
  // Half a second at 150 particles a second per torch, which is what the game
  // asks for, stepped so the live set reaches its natural size.
  for (var i = 0; i < 30; i++) {
    for (var t = 0; t < torches; t++) {
      system.emitFor(t, effect, Vector3(t * 2.0, 1.0, 0.0), 1 / 60,
          perSecond: 150.0);
    }
    system.step(1 / 60);
  }
  return system;
}

void main() {
  const dt = 1 / 60;

  for (final capacity in <int>[256, 3000]) {
    final system = warmed(capacity: capacity, torches: 5);
    final alive = system.aliveCount;
    final effect = flame();
    final vertices = Float32List(capacity * ParticleSystem.floatsPerParticle);
    final indices = Uint32List(capacity * 6);
    final right = Vector3(1.0, 0.0, 0.0);
    final up = Vector3(0.0, 1.0, 0.0);

    print('\ncapacity $capacity, $alive alive '
        '(${(100 * alive / capacity).toStringAsFixed(0)}% occupied)');

    // The whole frame's particle work, in the order the game does it.
    bench('emit + step + writeQuads', 2000, () {
      for (var t = 0; t < 5; t++) {
        system.emitFor(t, effect, Vector3(t * 2.0, 1.0, 0.0), dt,
            perSecond: 150.0);
      }
      system.step(dt);
      system.writeQuads(right, up, vertices, indices);
    }, items: alive);

    // Each piece, because they scale differently: two of these three walk the
    // pool and one walks the live set.
    // On a system that stays populated: measuring `step` on one it has already
    // drained times an empty pool.
    final held = populated(capacity: capacity, alive: 220);
    bench('  step alone', 4000, () => held.step(dt), items: held.aliveCount);
    bench('  writeQuads alone', 4000,
        () => held.writeQuads(right, up, vertices, indices),
        items: held.aliveCount);
    bench('  aliveCount alone', 20000, () {
      if (held.aliveCount < 0) throw StateError('unreachable');
    }, items: held.aliveCount);
  }
}
