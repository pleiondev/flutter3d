// Debris on the CPU and on the GPU — P9, phase 10: the core's own through
// the binding, and the compute shader's against it — the same to the GPU's
// rounding until bodies meet, then the same heap — and the read a frame
// late. The GPU half is skipped where there is no adapter, or no GPU
// library in the build.
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter3d_physics_native/flutter3d_physics_native.dart';
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart';

/// A pen two metres wide: a floor and four walls.
final List<DebrisStatic> _pen = <DebrisStatic>[
  DebrisPlane(Vector3(0.0, 1.0, 0.0), 0.0),
  DebrisPlane(Vector3(1.0, 0.0, 0.0), -1.0),
  DebrisPlane(Vector3(-1.0, 0.0, 0.0), -1.0),
  DebrisPlane(Vector3(0.0, 0.0, 1.0), -1.0),
  DebrisPlane(Vector3(0.0, 0.0, -1.0), -1.0),
];

/// A thousand balls of three sizes in ten layers above the pen.
List<DebrisBody> _pour() => <DebrisBody>[
  for (var i = 0; i < 1000; i++)
    (
      position: Vector3(
        -0.85 + (i % 10) * 0.19 + (i % 3) * 0.01,
        0.3 + (i ~/ 100) * 0.25,
        -0.85 + ((i ~/ 10) % 10) * 0.19,
      ),
      velocity: Vector3(0.0, -1.0, 0.0),
      radius: 0.05 + (i % 3) * 0.02,
      mass: 1.0,
    ),
];

double _meanHeight(Float32List bodies) {
  var sum = 0.0;
  for (var i = 0; i < bodies.length ~/ 8; i++) {
    sum += bodies[i * 8 + 1];
  }
  return sum / (bodies.length ~/ 8);
}

/// How far into another any ball sits, over the smaller radius, and how
/// many are through the floor or a wall by more than a centimetre.
({double overlap, int leaked}) _heap(Float32List b) {
  final n = b.length ~/ 8;
  var overlap = 0.0;
  var leaked = 0;
  for (var i = 0; i < n; i++) {
    final r = b[i * 8 + 7];
    if (b[i * 8 + 1] < r - 0.01 ||
        b[i * 8].abs() > 1 - r + 0.01 ||
        b[i * 8 + 2].abs() > 1 - r + 0.01) {
      leaked++;
    }
    for (var j = i + 1; j < n; j++) {
      final dx = b[i * 8] - b[j * 8];
      final dy = b[i * 8 + 1] - b[j * 8 + 1];
      final dz = b[i * 8 + 2] - b[j * 8 + 2];
      final depth = r + b[j * 8 + 7] - math.sqrt(dx * dx + dy * dy + dz * dz);
      overlap = math.max(overlap, depth / math.min(r, b[j * 8 + 7]));
    }
  }
  return (overlap: overlap, leaked: leaked);
}

void main() {
  test('a ball comes to rest on the floor through the binding', () {
    final d = NativeDebris(2);
    addTearDown(d.dispose);
    expect(d.capacity, 2);
    d.setStatics(_pen.sublist(0, 1));
    d.add(<DebrisBody>[
      (
        position: Vector3(0.0, 0.5, 0.0),
        velocity: Vector3.zero(),
        radius: 0.1,
        mass: 1.0,
      ),
    ]);
    expect(d.read(), isNull);
    final settings = DebrisSettings(restitution: 0.0);
    for (var i = 0; i < 120; i++) {
      d.step(settings, 1 / 60);
    }
    final frame = d.read()!;
    expect(frame.step, 120);
    expect(frame.bodies[1], closeTo(0.1, 0.001));
    expect(frame.bodies[7], closeTo(0.1, 1e-7));
    // The second slot is empty, and nothing new comes until a step.
    expect(frame.bodies[15], 0.0);
    expect(d.read(), isNull);
  });

  test('statics past sixty-four, and a disposed set, say so', () {
    final d = NativeDebris(1);
    expect(
      () => d.setStatics(List<DebrisStatic>.filled(65, _pen.first)),
      throwsArgumentError,
    );
    d.dispose();
    expect(() => d.read(), throwsStateError);
    d.dispose();
    expect(() => NativeDebris(0), throwsArgumentError);
  });

  final gpu = _openGpu();
  group(
    'on the GPU',
    skip: gpu == null ? 'no GPU adapter, or no GPU library' : null,
    () {
      tearDownAll(() => gpu?.dispose());

      test('reads a frame late, or waits', () {
        final d = gpu!.debris(16);
        addTearDown(d.dispose);
        d.setStatics(_pen);
        d.add(_pour().sublist(0, 16));
        expect(d.read(wait: false), isNull);
        final settings = DebrisSettings();
        var last = 0;
        for (var i = 1; i <= 30; i++) {
          d.step(settings, 1 / 60);
          final late = d.read(wait: false);
          if (late != null) {
            // Never a step not queued, never one older than the last read.
            expect(late.step, lessThanOrEqualTo(i));
            expect(late.step, greaterThan(last));
            last = late.step;
          }
        }
        expect(d.read()!.step, 30);
        expect(d.read(), isNull);
      });

      test('lands in a groove and stacks as the CPU does', () {
        // Scenes with no chaos in them, so body for body: a ball in a
        // shallow groove, its contacts splitting its mass, and three balls
        // of different sizes and masses stacked on a floor, each pair
        // counting different contacts on either side.
        const a = 0.35;
        final scenes = <(List<DebrisStatic>, List<DebrisBody>)>[
          (
            <DebrisStatic>[
              DebrisPlane(Vector3(math.sin(a), math.cos(a), 0.0), 0.0),
              DebrisPlane(Vector3(-math.sin(a), math.cos(a), 0.0), 0.0),
            ],
            <DebrisBody>[
              (
                position: Vector3(0.0, 1.0, 0.0),
                velocity: Vector3.zero(),
                radius: 0.1,
                mass: 1.0,
              ),
            ],
          ),
          (
            _pen.sublist(0, 1),
            <DebrisBody>[
              for (var i = 0; i < 3; i++)
                (
                  position: Vector3(0.0, 0.15 + i * 0.35, 0.0),
                  velocity: Vector3.zero(),
                  radius: 0.15 - i * 0.03,
                  mass: 4.0 - i * 1.5,
                ),
            ],
          ),
        ];
        for (final (statics, bodies) in scenes) {
          final cpu = NativeDebris(bodies.length);
          final onGpu = gpu!.debris(bodies.length);
          for (final DebrisSystem d in <DebrisSystem>[cpu, onGpu]) {
            d.setStatics(statics);
            d.add(bodies);
          }
          final settings = DebrisSettings(restitution: 0.0);
          // Every tenth step, so a hop on landing that settles shows too.
          for (var step = 1; step <= 120; step++) {
            cpu.step(settings, 1 / 60);
            onGpu.step(settings, 1 / 60);
            if (step % 10 != 0) continue;
            final x = cpu.read()!.bodies;
            final y = onGpu.read()!.bodies;
            for (var i = 0; i < x.length; i++) {
              expect(y[i], closeTo(x[i], 1e-4), reason: 'step $step, float $i');
            }
          }
          cpu.dispose();
          onGpu.dispose();
        }
      });

      test('pours the heap the CPU pours', () {
        final cpu = NativeDebris(1000);
        final onGpu = gpu!.debris(1000);
        addTearDown(cpu.dispose);
        addTearDown(onGpu.dispose);
        for (final DebrisSystem d in <DebrisSystem>[cpu, onGpu]) {
          d.setStatics(_pen);
          d.add(_pour());
        }
        final settings = DebrisSettings(restitution: 0.0);
        for (var i = 0; i < 5; i++) {
          cpu.step(settings, 1 / 60);
          onGpu.step(settings, 1 / 60);
        }
        // Falling, before they meet: the same to the GPU's rounding.
        final a = cpu.read()!.bodies;
        final b = onGpu.read()!.bodies;
        var worst = 0.0;
        for (var i = 0; i < a.length; i++) {
          worst = math.max(worst, (a[i] - b[i]).abs());
        }
        expect(worst, lessThan(1e-4));
        for (var i = 0; i < 235; i++) {
          cpu.step(settings, 1 / 60);
          onGpu.step(settings, 1 / 60);
        }
        // Settled: body for body they went their own ways, but the heap is
        // the same heap.
        final settledCpu = cpu.read()!.bodies;
        final settledGpu = onGpu.read()!.bodies;
        expect(
          _meanHeight(settledGpu),
          closeTo(_meanHeight(settledCpu), 0.01 * _meanHeight(settledCpu)),
        );
        final heap = _heap(settledGpu);
        expect(heap.leaked, 0);
        expect(heap.overlap, lessThan(0.1));
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
