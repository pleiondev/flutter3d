// The background is another isolate, which the web has not: there what
// would be put off is worked out at once, and nothing here applies.
@TestOn('vm')
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter3d_physics/flutter3d_physics.dart';
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart';

/// Lets the other isolate answer everything it has been asked.
Future<void> _settle() async {
  for (var i = 0; i < 400 && fluidBackground!.outstanding > 0; i++) {
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
}

void main() {
  test(
    'modes worked out on the other isolate are the same, to the bit',
    () async {
      // A 9 × 9 square of cells, each with its neighbours inside.
      const side = 9;
      final neighbours = [
        for (var r = 0; r < side; r++)
          for (var c = 0; c < side; c++)
            [
              if (c + 1 < side) r * side + c + 1,
              if (c > 0) r * side + c - 1,
              if (r + 1 < side) (r + 1) * side + c,
              if (r > 0) (r - 1) * side + c,
            ],
      ];
      final here = FreeSurface.solveModes(side * side, neighbours, 1e-6, 4);
      (List<Float64List>, Float64List)? there;
      fluidBackground!.solve(
        side * side,
        neighbours,
        1e-6,
        4,
        (modes) => there = modes,
      );
      await _settle();
      expect(there, isNotNull);
      expect(there!.$2, here.$2);
      for (var m = 0; m < here.$1.length; m++) {
        expect(there!.$1[m], here.$1[m]);
      }
    },
  );

  test('a meniscus worked out on the other isolate is the same', () async {
    final here = TubeMeniscus(
      medium: FluidMedium.water,
      radius: 0.0075,
      g: 9.81,
    );
    TubeMeniscus? there;
    fluidBackground!.meniscus(
      FluidMedium.water,
      0.0075,
      9.81,
      (m) => there = m,
    );
    await _settle();
    expect(there!.apexCurvature, here.apexCurvature);
    expect(there!.meanHeight, here.meanHeight);
    expect(there!.wallRise, here.wallRise);
  });

  test(
    'a tube tipped to a new angle carries on, then takes its modes',
    () async {
      final world = FluidWorld(gravity: Vector3(0, -9.81, 0), background: true);
      final tube = LiquidBody(
        shape: RevolvedVessel([
          for (var i = 0; i <= 8; i++)
            Vector2(
              0.0075 * math.sin(i * math.pi / 16),
              0.0075 - 0.0075 * math.cos(i * math.pi / 16),
            ),
          Vector2(0.0075, 0.1),
        ]),
        medium: FluidMedium.water,
        volume: 3e-6,
        modes: 4,
      );
      world.bodies.add(tube);
      void at(double tilt) {
        tube.place(
          Matrix3.rotationX(tilt),
          Vector3.zero(),
          time: world.time + world.step,
        );
        world.advance(world.step);
      }

      for (var i = 0; i < 10; i++) {
        at(0.0);
      }
      // An angle no tube has been at here: its cross-section is new.
      at(0.6123);
      expect(tube.surface.waitingForModes, isTrue);
      await _settle();
      at(0.6123);
      expect(tube.surface.waitingForModes, isFalse);
      // And the liquid is all there throughout.
      expect(tube.volume, closeTo(3e-6, 1e-18));
    },
  );
}
