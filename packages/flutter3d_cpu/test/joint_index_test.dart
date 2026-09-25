/// A JOINTS_0 value past the joint palette, which the loader does not refuse.
///
///     dart test test/joint_index_test.dart
///
/// Indexing a uniform array out of range is undefined on the GPU, so the
/// skinned stages clamp the index into the palette (`JointIndex`) and read
/// every slot whatever its weight. The mirror has to read the same slot: the
/// last one, which the skeleton pads with identity past its own joints.
library;

import 'dart:typed_data';

import 'package:flutter3d_core/flutter3d_core.dart';
import 'package:flutter3d_cpu/flutter3d_cpu.dart';
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart' show Matrix4, Vector4;

void main() {
  group('joint index', () {
    test('is truncated and held inside the palette', () {
      expect(MeshSkinnedVertexShader.jointIndex(0.0), 0);
      expect(MeshSkinnedVertexShader.jointIndex(5.0), 5);
      expect(MeshSkinnedVertexShader.jointIndex(63.0), 63);
      expect(MeshSkinnedVertexShader.jointIndex(64.0), 63);
      expect(MeshSkinnedVertexShader.jointIndex(70000.0), 63);
      expect(MeshSkinnedVertexShader.jointIndex(-1.0), 0);
    });

    test(
      'a vertex naming joint 200 is skinned by the palette\'s last slot',
      () {
        // Slot 63 moves five metres along z and every other slot is the
        // identity, so where the vertex lands says which slot was read.
        final palette = Float32List(MeshSkinnedVertexShader.maxJoints * 16);
        for (var j = 0; j < MeshSkinnedVertexShader.maxJoints; j++) {
          final joint = j == MeshSkinnedVertexShader.maxJoints - 1
              ? Matrix4.translationValues(0.0, 0.0, 5.0)
              : Matrix4.identity();
          palette.setAll(j * 16, joint.storage);
        }
        final identity = Matrix4.identity().storage;
        final a = Float32List(VertexLayout.skinned.floatsPerVertex)
          ..[kNormal + 2] = 1.0
          // Joints at 16, weights at 20: joint 200 at full weight.
          ..[16] = 200.0
          ..[20] = 1.0;
        final out = Float32List(kMeshVaryings);
        final clip = const MeshSkinnedVertexShader().runAt(
          -1,
          0,
          a,
          ShaderBindings(<String, Map<String, Float32List>>{
            'FrameInfo': <String, Float32List>{
              'mvp': identity,
              'model': identity,
              'normal_matrix': identity,
            },
            'SkinInfo': <String, Float32List>{'joint_matrices': palette},
          }, const <String, BoundTexture>{}),
          out,
        );

        // Mutation: `at: a[_joints + i].toInt()` asks the bindings for slot
        // 200, which they answer with the identity, and the vertex stays at the
        // origin while the GPU's clamped read moves it.
        expect(clip, Vector4(0.0, 0.0, 5.0, 1.0));
      },
    );
  });
}
