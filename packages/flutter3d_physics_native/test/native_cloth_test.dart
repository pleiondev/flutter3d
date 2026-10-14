// Cloth on the CPU — P9, phase 10: the core's own through the binding. On
// a GPU it is held to this in `flutter3d_effects/test/visual_workloads_test.dart`.
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
    expect(cloth.colorCount, inInclusiveRange(12, 24));
    expect(cloth.read(), isNull);
    final settings = CoreClothSettings(damping: 1.0);
    for (var i = 0; i < 120; i++) {
      cloth.step(ClothSystemStep(settings: settings, dt: 1 / 60));
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
        List.filled(17, ClothBall(center: Vector3.zero(), radius: 1.0)),
      ),
      throwsArgumentError,
    );
    cloth.dispose();
    expect(() => cloth.read(), throwsStateError);
    cloth.dispose();
  });
}
