/// `pro-sim-02`'s own acceptance, rigid-body half: "куб падает и
/// останавливается" — a cube falls and comes to rest.
///
///     dart test test/simulation_bake_rigid_test.dart
library;

import 'package:flutter3d_model_core/flutter3d_model_core.dart';
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart';

void main() {
  group('BakeRigidBodyCommand', () {
    test(
      "pro-sim-02's own acceptance: a cube falls and stops",
      () async {
        final command = BakeRigidBodyCommand(
          objectId: 1,
          baseVersion: 0,
          halfExtents: Vector3.all(0.25),
          startPosition: Vector3(0, 3, 0),
          frameCount: 180,
        );

        final cache = await command.buildCache();

        expect(cache.vertexCount, 8);
        expect(cache.frameCount, 180);

        double centreY(int frame) {
          final f = cache.frame(frame);
          var sum = 0.0;
          for (var v = 0; v < 8; v++) {
            sum += f[v * 3 + 1];
          }
          return sum / 8;
        }

        // Falls: well below where it started, partway through the bake.
        expect(centreY(30), lessThan(2.5));

        // Stops: the last ten frames barely move — settled on the floor,
        // not still falling or bouncing forever.
        final tail = <double>[
          for (var f = cache.frameCount - 10; f < cache.frameCount; f++)
            centreY(f),
        ];
        final spread = tail.reduce((a, b) => a > b ? a : b) -
            tail.reduce((a, b) => a < b ? a : b);
        expect(spread, lessThan(0.01));

        // Resting on the floor (top at y = 0), not still up in the air or
        // sunk through it.
        expect(centreY(cache.frameCount - 1), closeTo(0.25, 0.05));
      },
    );

    test('the bake is deterministic: two runs give the same cache', () async {
      Future<SimulationCache> run() => BakeRigidBodyCommand(
        objectId: 1,
        baseVersion: 0,
        halfExtents: Vector3.all(0.3),
        startPosition: Vector3(0, 5, 0),
        frameCount: 60,
      ).buildCache();

      final a = await run();
      final b = await run();

      for (var f = 0; f < a.frameCount; f++) {
        expect(a.frame(f), equals(b.frame(f)), reason: 'frame $f');
      }
    });

    test('every frame has exactly 8 vertices, the box\'s own corners', () async {
      final cache = await BakeRigidBodyCommand(
        objectId: 1,
        baseVersion: 0,
        halfExtents: Vector3.all(0.5),
        startPosition: Vector3(0, 1, 0),
        frameCount: 5,
      ).buildCache();

      expect(cache.vertexCount, 8);
      for (var f = 0; f < cache.frameCount; f++) {
        expect(cache.frame(f).length, 24);
      }
    });
  });
}
