// Fluid on the CPU and on the GPU — P9, phase 10: the core's own through
// the binding, and the compute shader's against it — particle for
// particle for the first few steps, then the same water — and the read a
// frame late. The GPU half is skipped where there is no adapter, or no
// GPU library in the build.
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
    (
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
      f.step(settings, 1 / 60);
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

  final gpu = _openGpu();
  group(
    'on the GPU',
    skip: gpu == null ? 'no GPU adapter, or no GPU library' : null,
    () {
      tearDownAll(() => gpu?.dispose());

      test('slides a viscous pair as the CPU does', () {
        // Two particles passing each other, too few to push: viscosity
        // alone, point for point every tenth step.
        final pair = <FluidParticle>[
          (position: Vector3(0.0, 1.0, 0.0), velocity: Vector3(0.0, 0.0, 0.02)),
          (
            position: Vector3(0.06, 1.0, 0.0),
            velocity: Vector3(0.0, 0.0, -0.02),
          ),
        ];
        final cpu = NativeFluid(2, 0.05)..add(pair);
        final onGpu = gpu!.fluid(2, 0.05)..add(pair);
        addTearDown(cpu.dispose);
        addTearDown(onGpu.dispose);
        final settings = FluidSettings(
          tankMin: Vector3(-1.0, 0.0, -1.0),
          tankMax: Vector3(1.0, 2.0, 1.0),
          gravity: Vector3.zero(),
          viscosity: 0.5,
        );
        for (var step = 1; step <= 60; step++) {
          cpu.step(settings, 1 / 60);
          onGpu.step(settings, 1 / 60);
          if (step % 10 != 0) continue;
          final x = cpu.read()!.particles;
          final y = onGpu.read()!.particles;
          for (var i = 0; i < x.length; i++) {
            expect(y[i], closeTo(x[i], 1e-5), reason: 'step $step, float $i');
          }
        }
      });

      test('breaks the dam the CPU breaks', () {
        final cpu = NativeFluid(1000, 0.05);
        final onGpu = gpu!.fluid(1000, 0.05);
        addTearDown(cpu.dispose);
        addTearDown(onGpu.dispose);
        expect(onGpu.restDensity, closeTo(cpu.restDensity, 1e-3));
        cpu.add(_dam(10));
        onGpu.add(_dam(10));
        final settings = _tank();
        for (var i = 0; i < 5; i++) {
          cpu.step(settings, 1 / 60);
          onGpu.step(settings, 1 / 60);
        }
        // Slumping, before it splashes: particle for particle.
        final a = cpu.read()!.particles;
        final b = onGpu.read()!.particles;
        for (var i = 0; i < a.length; i++) {
          expect(b[i], closeTo(a[i], 1e-4), reason: 'float $i');
        }
        for (var i = 0; i < 175; i++) {
          cpu.step(settings, 1 / 60);
          onGpu.step(settings, 1 / 60);
        }
        // Settled, each its own way: the same water.
        final x = _shape(cpu.read()!.particles);
        final y = _shape(onGpu.read()!.particles);
        expect(y.front, closeTo(0.475, 1e-4));
        expect(y.height, closeTo(x.height, 0.01));
        expect(y.mean, closeTo(x.mean, 0.01));
        expect(y.densest, lessThan(1.08));
      });

      test('reads a frame late', () {
        final onGpu = gpu!.fluid(64, 0.05);
        addTearDown(onGpu.dispose);
        onGpu.add(_dam(4));
        expect(onGpu.read(wait: false), isNull);
        final settings = _tank();
        var last = 0;
        for (var i = 1; i <= 20; i++) {
          onGpu.step(settings, 1 / 60);
          final late = onGpu.read(wait: false);
          if (late != null) {
            expect(late.step, inInclusiveRange(last + 1, i));
            last = late.step;
          }
        }
        expect(onGpu.read()!.step, 20);
        expect(onGpu.read(), isNull);
      });
    },
  );
}

/// The machine's GPU, or null when it has none for the passes to run on.
NativeGpu? _openGpu() {
  try {
    return NativeGpu.open();
  } on GpuUnavailable {
    return null;
  }
}
