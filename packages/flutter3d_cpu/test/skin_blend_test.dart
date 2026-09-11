/// `anim-02`'s own acceptance line: `SkinBlend`'s positions equal
/// `MeshSkinnedVertexShader`'s — the software rasteriser's own copy of
/// `mesh_skinned.vert`. Checked from here rather than from `flutter3d`'s own
/// test suite, since this is the one direction the dependency runs:
/// `flutter3d_cpu` depends on `flutter3d`, never the reverse, so this is the
/// only package that can see both at once.
///
///     flutter test test/skin_blend_test.dart
library;

import 'dart:typed_data';

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_cpu/flutter3d_cpu.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart' hide Ray;

/// One triangle, skinned three ways per vertex, so the comparison below
/// exercises a rigid bind, a renormalized blend across two joints, and a
/// vertex whose joint rotates rather than only translating.
MeshData _skinnedTriangle() {
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
  vertex(1, Vector3(0, 1, 0), Vector3(1, 0, 0), <double>[
    1,
    0,
    0,
    0,
  ], <double>[1.0, 0.0, 0.0, 0.0]);
  // Weights sum to 0.7, not 1 — exercises the renormalization both
  // implementations claim to do the same way.
  vertex(2, Vector3(0, 0, 1), Vector3(0, 0, 1), <double>[
    0,
    1,
    0,
    0,
  ], <double>[0.4, 0.3, 0.0, 0.0]);

  return MeshData(
    layout: layout,
    vertices: data,
    indices: Uint32List.fromList(<int>[0, 1, 2]),
  );
}

Float32List _jointMatrices(Map<int, Matrix4> overrides, {int maxJoints = 64}) {
  final out = Float32List(maxJoints * 16);
  for (var i = 0; i < maxJoints; i++) {
    final storage = (overrides[i] ?? Matrix4.identity()).storage;
    for (var e = 0; e < 16; e++) {
      out[i * 16 + e] = storage[e];
    }
  }
  return out;
}

void main() {
  test(
    'SkinBlend agrees with MeshSkinnedVertexShader on every vertex, '
    'position and normal alike, with joints that rotate as well as move',
    () {
      final mesh = _skinnedTriangle();

      // One joint that only translates, one that rotates and translates
      // both — the case a pure-translation fixture cannot exercise, since
      // rotation is where a wrong multiplication order or a dropped
      // rotation-only treatment of normals would actually show up.
      final joint0 = Matrix4.translation(Vector3(2.0, -1.0, 0.5));
      final joint1 = Matrix4.rotationZ(0.9)
        ..setTranslation(Vector3(0.0, 3.0, -2.0));
      final matrices = _jointMatrices(<int, Matrix4>{0: joint0, 1: joint1});

      final skin = SkinBlend(mesh);
      skin.blend(matrices);

      final bindings = ShaderBindings(<String, Map<String, Float32List>>{
        'FrameInfo': <String, Float32List>{
          'mvp': Matrix4.identity().storage,
          'model': Matrix4.identity().storage,
          'normal_matrix': Matrix4.identity().storage,
        },
        'SkinInfo': <String, Float32List>{'joint_matrices': matrices},
      }, const <String, BoundTexture>{});

      const shader = MeshSkinnedVertexShader();
      final stride = mesh.layout.floatsPerVertex;

      for (var v = 0; v < mesh.vertexCount; v++) {
        final at = v * stride;
        final a = Float32List.sublistView(mesh.vertices, at, at + stride);
        final out = Float32List(kMeshVaryings);
        // vertexIndex -1: no morph target on this fixture, matching what
        // every static (unmorphed) draw hands the shader in practice.
        shader.runAt(-1, 0, a, bindings, out);

        // Mutation: swap the blended matrix's multiplication order inside
        // `SkinBlend._transformPoint` (`local * m` instead of `m * local`)
        // — with `model` at identity here, `out[kVWorld...]` is exactly the
        // shader's own `skin * local`, so this diverges the moment a joint
        // rotates rather than only translates, which joint 1 does.
        expect(
          skin.vertices[at],
          closeTo(out[kVWorld], 1e-4),
          reason: 'vertex $v position.x',
        );
        expect(
          skin.vertices[at + 1],
          closeTo(out[kVWorld + 1], 1e-4),
          reason: 'vertex $v position.y',
        );
        expect(
          skin.vertices[at + 2],
          closeTo(out[kVWorld + 2], 1e-4),
          reason: 'vertex $v position.z',
        );

        // Mutation: drop the rotation-only treatment of normals in
        // `SkinBlend._transformDirection` (apply the translation term the
        // way positions get it) — this diverges from the shader's own
        // `mat3(skin) * normal` on every vertex, translation being nonzero
        // on both joints.
        expect(
          skin.vertices[at + 3],
          closeTo(out[kVNormal], 1e-4),
          reason: 'vertex $v normal.x',
        );
        expect(
          skin.vertices[at + 4],
          closeTo(out[kVNormal + 1], 1e-4),
          reason: 'vertex $v normal.y',
        );
        expect(
          skin.vertices[at + 5],
          closeTo(out[kVNormal + 2], 1e-4),
          reason: 'vertex $v normal.z',
        );
      }
    },
  );
}
