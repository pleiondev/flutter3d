/// `PolylineVertexShader`'s mitre, checked against the vertex stage directly
/// rather than through a rendered frame.
///
/// A rendered frame confounds two things at an exact reversal: the mitre's
/// own length, and the fact that the two segments' "side 0"/"side 1" swap
/// which physical edge of the band they name once the line's own direction
/// reverses — a property of the vertex format, not of the mitre, and one
/// that would make a full scene of a there-and-back line hard to read as a
/// clean band regardless of what the mitre does. Calling the vertex stage
/// once, at the shared joint vertex, asks only the question this file is
/// about.
library;

import 'dart:typed_data';

import 'package:flutter3d_cpu/src/cpu_shader_bindings.dart';
import 'package:flutter3d_cpu/src/cpu_shaders_layout.dart';
import 'package:flutter3d_cpu/src/cpu_shaders_polyline.dart';
import 'package:flutter3d_cpu/src/cpu_texture.dart';
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart';

const double _width = 8.0;
const double _viewport = 200.0;

ShaderBindings _identityBindings() =>
    ShaderBindings(<String, Map<String, Float32List>>{
      'FrameInfo': <String, Float32List>{
        'mvp': Float32List.fromList(Matrix4.identity().storage),
        'model': Float32List.fromList(Matrix4.identity().storage),
        'normal_matrix': Float32List.fromList(Matrix4.identity().storage),
      },
      'MaterialParams': <String, Float32List>{
        'viewport': Float32List.fromList(<double>[_viewport, _viewport, 0, 0]),
      },
    }, <String, BoundTexture>{});

/// One joint vertex: `here`, with `before` and `after` as its neighbours and
/// `side`/`halfWidth` packed into `tangent.w` the way `buildPolyline` packs
/// them.
Float32List _vertex({
  required Vector3 here,
  required Vector3 before,
  required Vector3 after,
  required bool sideZero,
}) {
  final a = Float32List(16);
  a[kPosition] = here.x;
  a[kPosition + 1] = here.y;
  a[kPosition + 2] = here.z;
  a[kNormal] = before.x;
  a[kNormal + 1] = before.y;
  a[kNormal + 2] = before.z;
  a[kTangent] = after.x;
  a[kTangent + 1] = after.y;
  a[kTangent + 2] = after.z;
  a[kTangent + 3] = sideZero ? -_width / 2 : _width / 2;
  return a;
}

/// The offset the vertex stage applied, in pixels — read back out of the
/// clip position it returned, at `here`'s own w (which is 1 under an
/// identity MVP), the same conversion the vertex stage's own last line does
/// in reverse.
Vector2 _offsetPixels(Vector4 clip, Vector3 here) => Vector2(
  (clip.x - here.x) * (_viewport * 0.5),
  (clip.y - here.y) * (_viewport * 0.5),
);

void main() {
  const shader = PolylineVertexShader();
  final out = Float32List(shader.varyingCount);

  test(
    'a joint folding straight back on itself mitres to the limit, not to one',
    () {
      // Mutation: read the join's length off the old bisector-based
      // `dot(miter, segmentNormal)` again. At an exact reversal that comes
      // out as 1.0 rather than the 0.0 the half-angle identity gives, and
      // the offset below comes out at one half width (4 px) instead of the
      // mitre limit's four (16 px) — narrower exactly where two segments
      // pointing directly apart should mitre to their widest.
      final vertex = _vertex(
        here: Vector3.zero(),
        before: Vector3(-1, 0, 0),
        after: Vector3(-1, 0, 0),
        sideZero: true,
      );
      final clip = shader.runAt(1, 0, vertex, _identityBindings(), out);
      final offset = _offsetPixels(clip, Vector3.zero());

      expect(
        offset.x.abs(),
        lessThan(1e-6),
        reason: 'a reversal along the x axis should mitre in y, not x',
      );
      expect(
        offset.y.abs(),
        closeTo(_width / 2 * 4, 1e-6),
        reason:
            'half width (${_width / 2}) times the mitre limit (4) is 16; '
            'got ${offset.y.abs()}',
      );
    },
  );

  test('a straight run mitres to nothing, on either side', () {
    // The baseline the reversal case is measured against: two collinear
    // segments need no extension at all, so the offset is exactly the plain
    // half width.
    final vertex = _vertex(
      here: Vector3.zero(),
      before: Vector3(-1, 0, 0),
      after: Vector3(1, 0, 0),
      sideZero: false,
    );
    final clip = shader.runAt(1, 0, vertex, _identityBindings(), out);
    final offset = _offsetPixels(clip, Vector3.zero());

    expect(offset.x.abs(), lessThan(1e-6));
    expect(offset.y, closeTo(_width / 2, 1e-6));
  });
}
