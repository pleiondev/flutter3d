// Particles on the CPU and on the GPU — P9, phase 10: the core's own, and
// the compute shader's against them, to a GPU's rounding. The GPU half is
// skipped where there is no adapter, or no GPU library in the build.
import 'dart:typed_data';

import 'package:flutter3d_physics_native/flutter3d_physics_native.dart';
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart';

/// A thousand particles thrown every way from a grid above a floor.
List<NativeParticle> _spray() => <NativeParticle>[
  for (var i = 0; i < 1000; i++)
    (
      position: Vector3(
        (i % 10).toDouble(),
        1.0 + (i % 7) * 0.1,
        (i ~/ 100).toDouble(),
      ),
      velocity: Vector3(
        ((i * 37) % 11) - 5.0,
        ((i * 13) % 9).toDouble(),
        ((i * 7) % 5) - 2.0,
      ),
      life: 0.5 + (i % 30) * 0.1,
    ),
];

final ParticleForces _weather = ParticleForces(
  wind: Vector3(2.0, 0.0, 1.0),
  drag: 0.5,
  floorY: 0.0,
  restitution: 0.6,
  friction: 0.2,
);

void main() {
  test('a spark flies as semi-implicit Euler sums, and dies', () {
    final p = NativeParticles(2);
    addTearDown(p.dispose);
    p.emit(<NativeParticle>[
      (position: Vector3.zero(), velocity: Vector3(3.0, 4.0, 0.0), life: 0.49),
    ]);
    // It lives thirty steps of a sixtieth, then stays where it died.
    p.step(ParticleForces(), 1 / 60, steps: 60);
    final out = p.read();
    const h = 1 / 60;
    expect(out[0], closeTo(3.0 * 30 * h, 1e-5));
    expect(out[1], closeTo(4.0 * 30 * h - 9.81 * h * h * 30 * 31 / 2, 1e-5));
    expect(out[3], closeTo(0.49 - 30 * h, 1e-5));
    // The second slot was never alive.
    expect(out[4], 0.0);
    expect(p.capacity, 2);
  });

  test('a floor turns a fall back, and the spray settles on it', () {
    final p = NativeParticles(1000);
    addTearDown(p.dispose);
    p.emit(_spray());
    p.step(_weather, 1 / 60, steps: 120);
    final out = p.read();
    for (var i = 0; i < 1000; i++) {
      expect(out[i * 4 + 1], greaterThanOrEqualTo(0.0), reason: 'particle $i');
    }
  });

  test('a disposed set says so', () {
    final p = NativeParticles(4)..dispose();
    expect(() => p.read(), throwsStateError);
    p.dispose();
    expect(() => NativeParticles(0), throwsArgumentError);
  });

  final gpu = _openGpu();
  group(
    'on the GPU',
    skip: gpu == null ? 'no GPU adapter, or no GPU library' : null,
    () {
      tearDownAll(() => gpu?.dispose());

      test('names its adapter', () {
        expect(gpu!.adapterName, isNotEmpty);
      });

      test('steps the spray as the CPU does, to its rounding', () {
        final cpu = NativeParticles(1000);
        final onGpu = gpu!.particles(1000);
        addTearDown(cpu.dispose);
        addTearDown(onGpu.dispose);
        cpu.emit(_spray());
        onGpu.emit(_spray());
        for (var s = 0; s < 4; s++) {
          cpu.step(_weather, 1 / 60, steps: 30);
          onGpu.step(_weather, 1 / 60, steps: 30);
        }
        final Float32List a = cpu.read();
        final Float32List b = onGpu.read();
        expect(b.length, a.length);
        var worst = 0.0;
        var moved = 0;
        for (var i = 0; i < a.length; i++) {
          worst = (a[i] - b[i]).abs() > worst ? (a[i] - b[i]).abs() : worst;
        }
        for (var i = 0; i < 1000; i++) {
          if (a[i * 4 + 3] < 0.5 + (i % 30) * 0.1) moved++;
        }
        // Two seconds of a thousand bouncing particles: a GPU rounds its own
        // way, but not by more than a tenth of a millimetre.
        expect(worst, lessThan(1e-4));
        expect(moved, 1000);
      });

      test('emits round and round, as the CPU does', () {
        final onGpu = gpu!.particles(3);
        addTearDown(onGpu.dispose);
        NativeParticle at(double x) => (
          position: Vector3(x, 0.0, 0.0),
          velocity: Vector3.zero(),
          life: 1.0,
        );
        onGpu.emit(<NativeParticle>[at(1), at(2), at(3), at(4)]);
        final out = onGpu.read();
        expect(<double>[out[0], out[4], out[8]], <double>[4, 2, 3]);
        onGpu.dispose();
        expect(() => onGpu.read(), throwsStateError);
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
