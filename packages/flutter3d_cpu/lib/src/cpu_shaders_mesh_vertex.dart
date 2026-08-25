/// `mesh.vert` and `mesh_skinned.vert`: the two vertex stages every lit model
/// shares, one of them with a joint blend in front of it.
library;

import 'dart:typed_data';

import 'package:vector_math/vector_math.dart';

import 'cpu_shader.dart';
import 'cpu_shaders_layout.dart';

/// The mesh vertex stage — `mesh.vert`.
final class MeshVertexShader implements CpuVertexShader {
  const MeshVertexShader();

  @override
  int get varyingCount => kMeshVaryings;

  @override
  Vector4 run(Float32List a, ShaderBindings bindings, Float32List out) {
    final mvp = bindings.mat4('FrameInfo', 'mvp');
    final model = bindings.mat4('FrameInfo', 'model');
    final normalMatrix = bindings.mat4('FrameInfo', 'normal_matrix');

    final local =
        Vector4(a[kPosition], a[kPosition + 1], a[kPosition + 2], 1.0);
    final Vector4 world = model * local;
    out[kVWorld] = world.x;
    out[kVWorld + 1] = world.y;
    out[kVWorld + 2] = world.z;

    // `mat3(normal_matrix) * normal`: the upper-left three by three, so the
    // translation does not move a direction.
    final Vector3 n = normalMatrix.getRotation() *
        Vector3(a[kNormal], a[kNormal + 1], a[kNormal + 2]);
    out[kVNormal] = n.x;
    out[kVNormal + 1] = n.y;
    out[kVNormal + 2] = n.z;

    out[kVUv] = a[kTexcoord];
    out[kVUv + 1] = a[kTexcoord + 1];
    for (var i = 0; i < 4; i++) {
      out[kVColour + i] = a[kColour + i];
    }

    // The tangent transforms with the model matrix, not the normal matrix: it
    // lies *in* the surface, so it stretches with the geometry rather than
    // staying perpendicular to it.
    final Vector3 t = model.getRotation() *
        Vector3(a[kTangent], a[kTangent + 1], a[kTangent + 2]);
    out[kVTangent] = t.x;
    out[kVTangent + 1] = t.y;
    out[kVTangent + 2] = t.z;
    out[kVTangent + 3] = a[kTangent + 3];

    return mvp * local;
  }
}

/// `mesh_skinned.vert`: the mesh stage with a joint blend in front of it.
///
/// The skinned layout is the standard one with joints and weights appended, so
/// the first sixteen floats are read at the same offsets as `mesh.vert` reads
/// them.
final class MeshSkinnedVertexShader implements CpuVertexShader {
  const MeshSkinnedVertexShader();

  static const int _joints = 16; // vec4
  static const int _weights = 20; // vec4

  @override
  int get varyingCount => kMeshVaryings;

  @override
  Vector4 run(Float32List a, ShaderBindings bindings, Float32List out) {
    // The weights are renormalised rather than trusted: an exporter that
    // writes three of four and leaves the fourth at zero is common, and a
    // total below one shrinks the vertex towards the origin.
    final total = a[_weights] + a[_weights + 1] + a[_weights + 2] + a[_weights + 3];
    final w = total > 1e-5
        ? <double>[
            a[_weights] / total,
            a[_weights + 1] / total,
            a[_weights + 2] / total,
            a[_weights + 3] / total,
          ]
        : <double>[1.0, 0.0, 0.0, 0.0];

    final skin = Matrix4.zero();
    for (var i = 0; i < 4; i++) {
      if (w[i] == 0.0) continue;
      final joint = bindings.mat4('SkinInfo', 'joint_matrices',
          at: a[_joints + i].toInt());
      for (var e = 0; e < 16; e++) {
        skin[e] = skin[e] + joint[e] * w[i];
      }
    }

    final model = bindings.mat4('FrameInfo', 'model');
    final mvp = bindings.mat4('FrameInfo', 'mvp');
    final normalMatrix = bindings.mat4('FrameInfo', 'normal_matrix');

    final local =
        Vector4(a[kPosition], a[kPosition + 1], a[kPosition + 2], 1.0);
    final Vector4 skinned = skin * local;
    final Vector4 world = model * skinned;
    out[kVWorld] = world.x;
    out[kVWorld + 1] = world.y;
    out[kVWorld + 2] = world.z;

    final skinRotation = skin.getRotation();
    final Vector3 n = normalMatrix.getRotation() *
        (skinRotation * Vector3(a[kNormal], a[kNormal + 1], a[kNormal + 2]));
    out[kVNormal] = n.x;
    out[kVNormal + 1] = n.y;
    out[kVNormal + 2] = n.z;

    out[kVUv] = a[kTexcoord];
    out[kVUv + 1] = a[kTexcoord + 1];
    for (var i = 0; i < 4; i++) {
      out[kVColour + i] = a[kColour + i];
    }

    final Vector3 t = model.getRotation() *
        (skinRotation *
            Vector3(a[kTangent], a[kTangent + 1], a[kTangent + 2]));
    out[kVTangent] = t.x;
    out[kVTangent + 1] = t.y;
    out[kVTangent + 2] = t.z;
    out[kVTangent + 3] = a[kTangent + 3];

    return mvp * skinned;
  }
}
