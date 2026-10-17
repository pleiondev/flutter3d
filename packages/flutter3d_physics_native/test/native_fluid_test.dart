// Fluid on the CPU — P9, phase 10: the core's own through the binding. On
// a GPU it is held to this in `flutter3d_effects/test/visual_workloads_test.dart`.
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter3d_physics_native/flutter3d_physics_native.dart';
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart';

/// A tank a metre long, half a metre wide.
FluidSettings _tank() => FluidSettings(
  tankMin: Vector3(-0.5, 0.0, -0.25),
  tankMax: Vector3(0.5, 2.0, 0.25),
);

/// A block of [n]³ particles 5 cm apart against the tank's low end.
List<FluidParticle> _dam(int n) => <FluidParticle>[
  for (var i = 0; i < n * n * n; i++)
    FluidParticle(
      position: Vector3(
        -0.475 + (i % n) * 0.05,
        0.025 + (i ~/ (n * n)) * 0.05,
        -0.225 + ((i ~/ n) % n) * 0.05,
      ),
      velocity: Vector3.zero(),
    ),
];

({double height, double front, double densest, double mean}) _shape(
  Float32List p,
) {
  var height = 0.0;
  var front = -1.0;
  var densest = 0.0;
  var mean = 0.0;
  final n = p.length ~/ 4;
  for (var i = 0; i < n; i++) {
    height += p[i * 4 + 1] / n;
    front = math.max(front, p[i * 4]);
    densest = math.max(densest, p[i * 4 + 3]);
    mean += p[i * 4 + 3] / n;
  }
  return (height: height, front: front, densest: densest, mean: mean);
}

void main() {
  test('a dam breaks and settles through the binding', () {
    final f = NativeFluid(1000, 0.05);
    addTearDown(f.dispose);
    expect(f.capacity, 1000);
    expect(f.restDensity, closeTo(8078.2, 0.1));
    expect(f.read(), isNull);
    f.add(_dam(10));
    expect(f.count, 1000);
    final settings = _tank();
    for (var i = 0; i < 180; i++) {
      f.step(FluidSystemStep(settings: settings, dt: 1 / 60));
    }
    final frame = f.read()!;
    expect(frame.step, 180);
    final shape = _shape(frame.particles);
    expect(shape.front, closeTo(0.475, 1e-4));
    // 0.125 m³ over half a square metre is 25 cm deep, its centre of
    // mass half that, sloshing or not.
    expect(shape.height, closeTo(0.125, 0.015));
    expect(shape.densest, lessThan(1.08));
    expect(f.read(), isNull);
  });

  test('bad spacing and a disposed fluid say so', () {
    expect(() => NativeFluid(10, 0.0), throwsArgumentError);
    final f = NativeFluid(10, 0.1)..dispose();
    expect(() => f.read(), throwsStateError);
    f.dispose();
  });
}
