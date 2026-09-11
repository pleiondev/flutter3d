/// `anim-02`'s own row: `SkinBlend` on its own, with hand-built meshes and
/// hand-checked numbers.
///
/// The arithmetic-parity claim against `MeshSkinnedVertexShader` — the whole
/// point of this row — lives in `flutter3d_cpu/test/skin_blend_test.dart`
/// instead, since `flutter3d_cpu` is the package allowed to depend on both.
///
///     dart test test/skin_blend_test.dart
library;

import 'dart:typed_data';

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart' hide Ray;

/// One triangle, skinned: vertex 0 rigid to joint 0, vertex 1 rigid to
/// joint 1, vertex 2 split unevenly (and not normalized) between both.
MeshData _triangle() {
  const layout = VertexLayout.skinned;
  final stride = layout.floatsPerVertex;
  final data = Float32List(3 * stride);

  void vertex(
    int i,
    Vector3 position,
    Vector3 normal,
    List<double> joints,
    List<double> weights,
  ) {
    final at = i * stride;
    data[at] = position.x;
    data[at + 1] = position.y;
    data[at + 2] = position.z;
    data[at + 3] = normal.x;
    data[at + 4] = normal.y;
    data[at + 5] = normal.z;
    data[at + 8] = 1.0; // tangent.x
    data[at + 11] = 1.0; // tangent.w
    data[at + 12] = 1.0; // color, all four channels
    data[at + 13] = 1.0;
    data[at + 14] = 1.0;
    data[at + 15] = 1.0;
    data[at + 16] = joints[0];
    data[at + 17] = joints[1];
    data[at + 18] = joints[2];
    data[at + 19] = joints[3];
    data[at + 20] = weights[0];
    data[at + 21] = weights[1];
    data[at + 22] = weights[2];
    data[at + 23] = weights[3];
  }

  vertex(0, Vector3(1, 0, 0), Vector3(0, 1, 0), <double>[
    0,
    0,
    0,
    0,
  ], <double>[1.0, 0.0, 0.0, 0.0]);
  vertex(1, Vector3(0, 1, 0), Vector3(0, 1, 0), <double>[
    1,
    0,
    0,
    0,
  ], <double>[1.0, 0.0, 0.0, 0.0]);
  // Weights sum to 0.6, not 1 — an exporter's rounding error, exercising the
  // renormalization every other vertex here has no reason to touch.
  vertex(2, Vector3(0, 0, 1), Vector3(0, 1, 0), <double>[
    0,
    1,
    0,
    0,
  ], <double>[0.3, 0.3, 0.0, 0.0]);

  return MeshData(
    layout: layout,
    vertices: data,
    indices: Uint32List.fromList(<int>[0, 1, 2]),
  );
}

/// [maxJoints] joint matrices, all identity, then [overrides] written on top —
/// the shape `Skeleton.matrices`/`Pose.jointMatrices` hand a caller.
Float32List _jointMatrices(
  Map<int, Matrix4> overrides, {
  int maxJoints = 64,
}) {
  final out = Float32List(maxJoints * 16);
  for (var i = 0; i < maxJoints; i++) {
    final m = overrides[i] ?? Matrix4.identity();
    final storage = m.storage;
    for (var e = 0; e < 16; e++) {
      out[i * 16 + e] = storage[e];
    }
  }
  return out;
}

void main() {
  group('a mesh without joints/weights is refused', () {
    test('SkinBlend throws rather than blending nothing', () {
      final mesh = MeshData(
        layout: VertexLayout.standard,
        vertices: Float32List(VertexLayout.standard.floatsPerVertex),
        indices: Uint32List.fromList(<int>[0, 0, 0]),
      );
      expect(() => SkinBlend(mesh), throwsArgumentError);
    });
  });

  group('blending moves rigidly bound vertices with their joint', () {
    test('a vertex weighted entirely to one joint follows it exactly', () {
      final skin = SkinBlend(_triangle());
      final matrices = _jointMatrices(<int, Matrix4>{
        0: Matrix4.translation(Vector3(2.0, 0.0, 0.0)),
        1: Matrix4.translation(Vector3(0.0, 3.0, 0.0)),
      });
      skin.blend(matrices);

      // Mutation: swap which joint a vertex's weight names — vertex 0 would
      // then read joint 1's translation instead of joint 0's.
      expect(skin.vertices[0], closeTo(3.0, 1e-6), reason: 'vertex 0 x');
      expect(skin.vertices[1], closeTo(0.0, 1e-6), reason: 'vertex 0 y');
      expect(skin.vertices[24], closeTo(0.0, 1e-6), reason: 'vertex 1 x');
      expect(skin.vertices[25], closeTo(4.0, 1e-6), reason: 'vertex 1 y');
    });

    test('an unevenly-weighted vertex is renormalized before blending', () {
      final skin = SkinBlend(_triangle());
      final matrices = _jointMatrices(<int, Matrix4>{
        0: Matrix4.translation(Vector3(10.0, 0.0, 0.0)),
        1: Matrix4.translation(Vector3(0.0, 10.0, 0.0)),
      });
      skin.blend(matrices);

      // Vertex 2 names joints 0 and 1 at 0.3 each — renormalized to 0.5/0.5,
      // so it lands exactly halfway between the two translations rather than
      // 0.3 of the way (which not renormalizing would produce).
      final at = 2 * VertexLayout.skinned.floatsPerVertex;
      // Mutation: use the raw (un-renormalized) weights straight from the
      // vertex buffer — this reads (3.0, 3.0, 1.0) instead of (5.0, 5.0, 1.0).
      expect(skin.vertices[at], closeTo(5.0, 1e-6), reason: 'vertex 2 x');
      expect(skin.vertices[at + 1], closeTo(5.0, 1e-6), reason: 'vertex 2 y');
      expect(skin.vertices[at + 2], closeTo(1.0, 1e-6), reason: 'vertex 2 z');
    });

    test('weights summing to nothing fall back to full influence on the '
        'first joint', () {
      const layout = VertexLayout.skinned;
      final data = Float32List(layout.floatsPerVertex)
        ..[0] = 1.0 // position.x
        ..[4] = 1.0; // normal.y
      final mesh = MeshData(
        layout: layout,
        vertices: data,
        indices: Uint32List.fromList(<int>[0, 0, 0]),
      );
      final skin = SkinBlend(mesh);
      final matrices = _jointMatrices(<int, Matrix4>{
        0: Matrix4.translation(Vector3(7.0, 0.0, 0.0)),
      });
      skin.blend(matrices);

      // Mutation: leave the vertex at the origin instead of falling back to
      // joint 0 at full weight — a vertex with all-zero weights is a decoder
      // gap (fmt-15's own kind of thing), not a reason to collapse it to the
      // origin.
      expect(skin.vertices[0], closeTo(8.0, 1e-6));
    });
  });

  group('normals and tangents rotate, but never translate', () {
    test('a pure-translation joint leaves a rigidly bound normal unchanged', () {
      final skin = SkinBlend(_triangle());
      final matrices = _jointMatrices(<int, Matrix4>{
        0: Matrix4.translation(Vector3(2.0, 0.0, 0.0)),
        1: Matrix4.translation(Vector3(0.0, 3.0, 0.0)),
      });
      skin.blend(matrices);

      // Vertex 0's normal is (0, 1, 0) at rest. Mutation: apply the
      // translation term to normals the way `_transformPoint` does to
      // positions — this would shift it to (2, 1, 0).
      expect(skin.vertices[3], closeTo(0.0, 1e-6), reason: 'normal.x');
      expect(skin.vertices[4], closeTo(1.0, 1e-6), reason: 'normal.y');
      expect(skin.vertices[5], closeTo(0.0, 1e-6), reason: 'normal.z');
    });

    test('a rotating joint carries the normal with it', () {
      const layout = VertexLayout.skinned;
      final data = Float32List(layout.floatsPerVertex);
      data[2] = 1.0; // position = (0, 0, 1)
      data[5] = 1.0; // normal = (0, 0, 1)
      data[16] = 0.0; // joint 0
      data[20] = 1.0; // weight 1.0
      final mesh = MeshData(
        layout: layout,
        vertices: data,
        indices: Uint32List.fromList(<int>[0, 0, 0]),
      );
      final skin = SkinBlend(mesh);

      final rotation = Matrix4.rotationY(3.14159265358979 / 2);
      skin.blend(_jointMatrices(<int, Matrix4>{0: rotation}));

      // An independent oracle — vector_math's own `transformed3` — rather
      // than a hand-derived expectation, so this cannot pass by SkinBlend
      // and the check sharing the same mistake.
      final expected = rotation.transformed3(Vector3(0.0, 0.0, 1.0));
      expect(skin.vertices[3], closeTo(expected.x, 1e-5), reason: 'normal.x');
      expect(skin.vertices[4], closeTo(expected.y, 1e-5), reason: 'normal.y');
      expect(skin.vertices[5], closeTo(expected.z, 1e-5), reason: 'normal.z');
    });
  });

  group('nothing is recomputed when the pose has not moved', () {
    test('blend returns false for matrices equal in value, not identity', () {
      final skin = SkinBlend(_triangle());
      final first = _jointMatrices(<int, Matrix4>{
        0: Matrix4.translation(Vector3(1.0, 0.0, 0.0)),
      });
      expect(skin.blend(first), isTrue);

      // A distinct object, same values — `_differs` must compare content,
      // not identity, or a caller rebuilding the array fresh each frame
      // (which every caller does) would never see the skip.
      final second = _jointMatrices(<int, Matrix4>{
        0: Matrix4.translation(Vector3(1.0, 0.0, 0.0)),
      });
      // Mutation: compare `identical(applied, jointMatrices)` instead of
      // the elements — this would return true here instead of false.
      expect(skin.blend(second), isFalse);

      final third = _jointMatrices(<int, Matrix4>{
        0: Matrix4.translation(Vector3(2.0, 0.0, 0.0)),
      });
      expect(skin.blend(third), isTrue);
    });
  });
}
