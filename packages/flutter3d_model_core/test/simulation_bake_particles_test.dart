/// `pro-sim-02`'s own acceptance, particle half: "частицы детерминированы"
/// — particles are deterministic.
///
///     dart test test/simulation_bake_particles_test.dart
library;

import 'package:flutter3d_model_core/flutter3d_model_core.dart';
import 'package:flutter3d_particles_core/flutter3d_particles_core.dart';
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart';

ParticleSystem _burningTorch({int seed = 7, int capacity = 64}) {
  final system = ParticleSystem(capacity: capacity, seed: seed);
  system.emit(
    #torch,
    ParticleEffect(
      count: 1,
      emitter: const SphereEmitter(speed: Range.exact(1.0)),
      lifetime: const Range.exact(0.6),
      size: const Range.exact(0.05),
      color: Vector4(1, 0.6, 0.1, 1),
    ),
    Vector3.zero(),
    perSecond: 40,
  );
  return system;
}

void main() {
  group('BakeParticleSystemJobRequest', () {
    test(
      "pro-sim-02's own acceptance: particles are deterministic",
      () async {
        Future<SimulationCache> run() => BakeParticleSystemJobRequest(
          objectId: 1,
          baseVersion: 0,
          system: _burningTorch(),
          frameCount: 90,
        ).buildCache();

        final a = await run();
        final b = await run();

        expect(a.frameCount, b.frameCount);
        for (var f = 0; f < a.frameCount; f++) {
          expect(a.frame(f), equals(b.frame(f)), reason: 'frame $f');
        }
      },
    );

    test('a fresh system with nothing emitting yet bakes to all zeros', () async {
      final cache = await BakeParticleSystemJobRequest(
        objectId: 1,
        baseVersion: 0,
        system: ParticleSystem(capacity: 16, seed: 1),
        frameCount: 5,
      ).buildCache();

      expect(cache.vertexCount, 16);
      for (var f = 0; f < cache.frameCount; f++) {
        expect(cache.frame(f), everyElement(0.0));
      }
    });

    test('vertexCount is the system\'s own capacity, not how many are alive', () async {
      final system = _burningTorch(capacity: 32);
      final cache = await BakeParticleSystemJobRequest(
        objectId: 1,
        baseVersion: 0,
        system: system,
        frameCount: 3,
      ).buildCache();

      expect(cache.vertexCount, 32);
      expect(cache.frame(0).length, 32 * 3);
    });

    test('emission actually moves some particles away from the origin', () async {
      final cache = await BakeParticleSystemJobRequest(
        objectId: 1,
        baseVersion: 0,
        system: _burningTorch(),
        frameCount: 30,
      ).buildCache();

      final last = cache.frame(cache.frameCount - 1);
      var anyMoved = false;
      for (var v = 0; v < cache.vertexCount; v++) {
        final x = last[v * 3], y = last[v * 3 + 1], z = last[v * 3 + 2];
        if (x != 0.0 || y != 0.0 || z != 0.0) {
          anyMoved = true;
          break;
        }
      }
      expect(anyMoved, isTrue);
    });
  });
}
