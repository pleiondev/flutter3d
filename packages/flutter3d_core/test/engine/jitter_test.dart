/// The scene is drawn a fraction of a pixel off each frame, along a sequence
/// that covers the pixel evenly — `R1`.
///
///     dart test test/engine/jitter_test.dart
library;

import 'package:flutter3d_core/flutter3d_core.dart';
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart';

void main() {
  test('the offsets stay inside the pixel and repeat after the sequence', () {
    for (var frame = 0; frame < 64; frame++) {
      final (x, y) = jitterOffset(frame, 16);
      expect(x, inInclusiveRange(-0.5, 0.5));
      expect(y, inInclusiveRange(-0.5, 0.5));
      expect(jitterOffset(frame + 16, 16), (x, y));
    }
  });

  test('sixteen offsets are sixteen different places centred on the pixel', () {
    final offsets = <(double, double)>{
      for (var frame = 0; frame < 16; frame++) jitterOffset(frame, 16),
    };
    expect(offsets, hasLength(16));
    final meanX = offsets.fold(0.0, (a, o) => a + o.$1) / 16;
    final meanY = offsets.fold(0.0, (a, o) => a + o.$2) / 16;
    // Halton is low-discrepancy, not exactly balanced over a prefix: the mean
    // lands within a sixteenth of a pixel of the centre, where sixteen random
    // offsets would typically miss it by a tenth.
    expect(meanX.abs(), lessThan(1 / 16));
    expect(meanY.abs(), lessThan(1 / 16));
  });

  test('the first offset is not the pixel centre', () {
    // Mutation: count the sequence from zero. Halton's first point is
    // (0, 0), which is (-0.5, -0.5) here, and a corner weighted twice.
    expect(jitterOffset(0, 16), isNot((-0.5, -0.5)));
    final (x, y) = jitterOffset(0, 16);
    expect(x, 0.0);
    expect(y, closeTo(-1 / 6, 1e-12));
  });

  test('a jittered projection moves every point by the same NDC offset', () {
    const base = PerspectiveProjection();
    final jittered = JitteredProjection.frame(
      base,
      frame: 3,
      length: 16,
      width: 200,
      height: 100,
    );
    final (x, y) = jitterOffset(3, 16);
    for (final point in <Vector3>[
      Vector3(0, 0, -2),
      Vector3(1, -0.5, -7),
      Vector3(-3, 2, -40),
    ]) {
      Vector3 ndc(Matrix4 m) {
        final clip = m.transform(Vector4(point.x, point.y, point.z, 1));
        return clip.xyz / clip.w;
      }

      final a = ndc(base.toMatrix(2.0));
      final b = ndc(jittered.toMatrix(2.0));
      expect(b.x - a.x, closeTo(2 * x / 200, 1e-6));
      expect(b.y - a.y, closeTo(2 * y / 100, 1e-6));
      expect(b.z, closeTo(a.z, 1e-6));
    }
  });
}
