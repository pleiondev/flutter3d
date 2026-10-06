// Cloth on the CPU and on the GPU — P9, phase 10: the core's own through
// the binding, and the compute shader's against it — point for point
// where nothing folds, and up to the first wrinkles in a sheet, then the
// same sheet in what it does — the read a frame late, and carried pins.
// The GPU half is skipped where there is no adapter, or no GPU library in
// the build.
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter3d_physics_native/flutter3d_physics_native.dart';
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart';

/// A sheet a metre square hanging from the two corners of its first row.
CoreClothMesh _sheet(int side) => CoreClothMesh.grid(
  columns: side,
  rows: side,
  origin: Vector3(-0.5, 0.0, -0.5),
  pinned: <int>{0, side - 1},
);

/// How much longer than it started the longest structural edge of a
/// [side] × [side] sheet a metre wide is, as a fraction.
double _stretch(Float32List p, int side) {
  var worst = 0.0;
  for (var j = 0; j < side; j++) {
    for (var i = 0; i + 1 < side; i++) {
      final a = (j * side + i) * 4;
      final b = a + 4;
      final d = math.sqrt(
        math.pow(p[a] - p[b], 2) +
            math.pow(p[a + 1] - p[b + 1], 2) +
            math.pow(p[a + 2] - p[b + 2], 2),
      );
      worst = math.max(worst, d * (side - 1) - 1.0);
    }
  }
  return worst;
}

double _lowest(Float32List p) {
  var low = double.infinity;
  for (var i = 1; i < p.length; i += 4) {
    low = math.min(low, p[i]);
  }
  return low;
}

void main() {
  test('a sheet hangs from its pins through the binding', () {
    final cloth = NativeCloth(_sheet(12));
    addTearDown(cloth.dispose);
    expect(cloth.pointCount, 144);
    expect(cloth.colourCount, inInclusiveRange(12, 24));
    expect(cloth.read(), isNull);
    final settings = CoreClothSettings(damping: 1.0);
    for (var i = 0; i < 120; i++) {
      cloth.step(settings, 1 / 60);
    }
    final frame = cloth.read()!;
    expect(frame.step, 120);
    final p = frame.points;
    expect(<double>[p[0], p[1], p[2], p[3]], <double>[-0.5, 0.0, -0.5, 0.0]);
    expect(p[11 * 4 + 1], 0.0);
    expect(_lowest(p), inInclusiveRange(-1.1, -0.8));
    expect(_stretch(p, 12), lessThan(0.02));
    expect(cloth.read(), isNull);
  });

  test('bad meshes, too many balls and a disposed cloth say so', () {
    expect(
      () => NativeCloth(
        CoreClothMesh(
          points: <Vector3>[Vector3.zero(), Vector3(1.0, 0.0, 0.0)],
          inverseMasses: <double>[1.0, 1.0],
          edges: <(int, int)>[(1, 1)],
          compliances: <double>[0.0],
        ),
      ),
      throwsArgumentError,
    );
    final cloth = NativeCloth(_sheet(4));
    expect(
      () => cloth.setBalls(
        List.filled(17, (centre: Vector3.zero(), radius: 1.0)),
      ),
      throwsArgumentError,
    );
    cloth.dispose();
    expect(() => cloth.read(), throwsStateError);
    cloth.dispose();
  });

  final gpu = NativeGpu.open();
  group(
    'on the GPU',
    skip: gpu == null ? 'no GPU adapter, or no GPU library' : null,
    () {
      tearDownAll(() => gpu?.dispose());

      test('swings, springs, drifts and rolls off a ball as the CPU does', () {
        // Scenes nothing folds in, so point for point every tenth step — to
        // half a millimetre, a swing's phase drifting by its rounding — a
        // rigid pendulum, a damped spring in a wind, a rod dropped onto a
        // ball off its top that slides off it, and loose points blown along
        // the floor.
        final scenes =
            <
              (
                CoreClothMesh,
                CoreClothSettings,
                List<({Vector3 centre, double radius})>,
              )
            >[
              (
                CoreClothMesh(
                  points: <Vector3>[Vector3.zero(), Vector3(1.0, 0.0, 0.0)],
                  inverseMasses: <double>[0.0, 1.0],
                  edges: <(int, int)>[(0, 1)],
                  compliances: <double>[0.0],
                ),
                CoreClothSettings(damping: 0.0),
                <({Vector3 centre, double radius})>[],
              ),
              (
                CoreClothMesh(
                  points: <Vector3>[Vector3.zero(), Vector3(0.0, -1.0, 0.0)],
                  inverseMasses: <double>[0.0, 1.0],
                  edges: <(int, int)>[(0, 1)],
                  compliances: <double>[1e-3],
                ),
                CoreClothSettings(
                  damping: 2.0,
                  wind: Vector3(3.0, 0.0, 0.0),
                  drag: 0.5,
                ),
                <({Vector3 centre, double radius})>[],
              ),
              (
                CoreClothMesh(
                  points: <Vector3>[
                    Vector3(0.1, 1.0, 0.0),
                    Vector3(0.3, 1.0, 0.05),
                  ],
                  inverseMasses: <double>[2.0, 2.0],
                  edges: <(int, int)>[(0, 1)],
                  compliances: <double>[1e-6],
                ),
                CoreClothSettings(floorY: 0.0, friction: 0.2),
                <({Vector3 centre, double radius})>[
                  (centre: Vector3(0.0, 0.3, 0.0), radius: 0.3),
                ],
              ),
              (
                CoreClothMesh(
                  points: <Vector3>[
                    Vector3(0.0, 0.5, 0.0),
                    Vector3(0.3, 0.2, 0.0),
                  ],
                  inverseMasses: <double>[1.0, 1.0],
                  edges: <(int, int)>[],
                  compliances: <double>[],
                ),
                CoreClothSettings(
                  floorY: 0.1,
                  thickness: 0.02,
                  friction: 0.4,
                  wind: Vector3(2.0, 0.0, 1.0),
                  drag: 1.0,
                ),
                <({Vector3 centre, double radius})>[],
              ),
            ];
        for (final (mesh, settings, balls) in scenes) {
          final cpu = NativeCloth(mesh);
          final onGpu = gpu!.cloth(mesh);
          cpu.setBalls(balls);
          onGpu.setBalls(balls);
          for (var step = 1; step <= 120; step++) {
            cpu.step(settings, 1 / 60);
            onGpu.step(settings, 1 / 60);
            if (step % 10 != 0) continue;
            final x = cpu.read()!.points;
            final y = onGpu.read()!.points;
            for (var i = 0; i < x.length; i++) {
              expect(y[i], closeTo(x[i], 5e-4), reason: 'step $step, float $i');
            }
          }
          cpu.dispose();
          onGpu.dispose();
        }
      });

      test('hangs the sheet the CPU hangs', () {
        final cpu = NativeCloth(_sheet(32));
        final onGpu = gpu!.cloth(_sheet(32));
        addTearDown(cpu.dispose);
        addTearDown(onGpu.dispose);
        final settings = CoreClothSettings(damping: 1.0);
        for (var i = 0; i < 30; i++) {
          cpu.step(settings, 1 / 60);
          onGpu.step(settings, 1 / 60);
        }
        // Half a second in, falling and not yet folded: point for point.
        final a = cpu.read()!.points;
        final b = onGpu.read()!.points;
        for (var i = 0; i < a.length; i++) {
          expect(b[i], closeTo(a[i], 1e-4), reason: 'float $i');
        }
        for (var i = 0; i < 150; i++) {
          cpu.step(settings, 1 / 60);
          onGpu.step(settings, 1 / 60);
        }
        // Wrinkled, each its own way: the same sheet.
        final settledCpu = cpu.read()!.points;
        final settled = onGpu.read()!.points;
        expect(
          <double>[settled[0], settled[1], settled[2]],
          <double>[-0.5, 0.0, -0.5],
        );
        // A sheet of 32² stretches some 4% at sixteen substeps, on either.
        expect(_stretch(settled, 32), closeTo(_stretch(settledCpu, 32), 0.005));
        expect(_lowest(settled), closeTo(_lowest(settledCpu), 0.01));
      });

      test('reads a frame late, and carries its pins', () {
        final onGpu = gpu!.cloth(_sheet(8));
        addTearDown(onGpu.dispose);
        expect(onGpu.read(wait: false), isNull);
        final settings = CoreClothSettings();
        var last = 0;
        for (var i = 1; i <= 20; i++) {
          onGpu.step(settings, 1 / 60);
          final late = onGpu.read(wait: false);
          if (late != null) {
            expect(late.step, inInclusiveRange(last + 1, i));
            last = late.step;
          }
        }
        onGpu
          ..movePoint(0, Vector3(-0.5, 1.0, -0.5))
          ..movePoint(7, Vector3(0.5, 1.0, -0.5));
        for (var i = 0; i < 60; i++) {
          onGpu.step(settings, 1 / 60);
        }
        final p = onGpu.read()!;
        expect(p.step, 80);
        expect(p.points[1], 1.0);
        expect(p.points[7 * 4 + 1], 1.0);
        expect(p.points[63 * 4 + 1], greaterThan(0.0));
        expect(onGpu.read(), isNull);
      });
    },
  );
}
