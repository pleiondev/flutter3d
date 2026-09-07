/// `mesh.vert` and `mesh_skinned.vert`: the two vertex stages every lit model
/// shares, one of them with a joint blend in front of it.
library;

import 'dart:typed_data';

import 'package:vector_math/vector_math.dart';

import 'cpu_shader.dart';
import 'cpu_shaders_layout.dart';
import 'cpu_shaders_morph.dart';

/// One scratch for every mesh stage in this library.
///
/// The stages are `const` — they are registered as constants and hold no state
/// — so the vectors a morph needs cannot live on them. A vertex stage runs once
/// per vertex per draw, so allocating three vectors inside it would be hundreds
/// of thousands of allocations a frame, which is the pattern every hot loop
/// here is written to avoid.
///
/// Safe because this backend rasterises one draw at a time on one thread: the
/// encoder walks its primitives in a loop and nothing here is reentrant. A
/// second thread rasterising would need one of these apiece, and would need a
/// great deal else besides.
final MorphScratch _morphScratch = MorphScratch();

/// The mesh vertex stage — `mesh.vert`.
final class MeshVertexShader implements CpuVertexShaderByIndex {
  const MeshVertexShader();

  @override
  int get varyingCount => kMeshVaryings;

  /// Without an index, which is a caller that cannot morph — see
  /// [CpuVertexShaderByIndex]. A negative index reads as "no vertex", and the
  /// morph is skipped rather than reading column minus one.
  @override
  Vector4 run(Float32List a, ShaderBindings bindings, Float32List out) =>
      runAt(-1, 0, a, bindings, out);

  @override
  Vector4 runAt(
    int vertexIndex,
    int instanceIndex,
    Float32List a,
    ShaderBindings bindings,
    Float32List out,
  ) {
    final mvp = bindings.mat4('FrameInfo', 'mvp');
    final model = bindings.mat4('FrameInfo', 'model');
    final normalMatrix = bindings.mat4('FrameInfo', 'normal_matrix');

    // Morphed first and in the mesh's own space, which is the order the GLSL
    // uses and the order glTF specifies.
    final morphed =
        vertexIndex >= 0 &&
        _morphScratch.load(
          vertexIndex,
          a,
          bindings,
          positionAt: kPosition,
          normalAt: kNormal,
          tangentAt: kTangent,
        );

    final local = morphed
        ? Vector4(
            _morphScratch.position.x,
            _morphScratch.position.y,
            _morphScratch.position.z,
            1.0,
          )
        : Vector4(a[kPosition], a[kPosition + 1], a[kPosition + 2], 1.0);
    final Vector4 world = model * local;
    out[kVWorld] = world.x;
    out[kVWorld + 1] = world.y;
    out[kVWorld + 2] = world.z;

    // `mat3(normal_matrix) * normal`: the upper-left three by three, so the
    // translation does not move a direction.
    final Vector3 n =
        normalMatrix.getRotation() *
        (morphed
            ? _morphScratch.normal
            : Vector3(a[kNormal], a[kNormal + 1], a[kNormal + 2]));
    out[kVNormal] = n.x;
    out[kVNormal + 1] = n.y;
    out[kVNormal + 2] = n.z;

    out[kVUv] = a[kTexcoord];
    out[kVUv + 1] = a[kTexcoord + 1];
    for (var i = 0; i < 4; i++) {
      out[kVColour + i] = a[kColour + i];
    }
    out[kVLightmap] = 0.0;
    out[kVLightmap + 1] = 0.0;

    // The tangent transforms with the model matrix, not the normal matrix: it
    // lies *in* the surface, so it stretches with the geometry rather than
    // staying perpendicular to it.
    final Vector3 t =
        model.getRotation() *
        (morphed
            ? Vector3(
                _morphScratch.tangent.x,
                _morphScratch.tangent.y,
                _morphScratch.tangent.z,
              )
            : Vector3(a[kTangent], a[kTangent + 1], a[kTangent + 2]));
    out[kVTangent] = t.x;
    out[kVTangent + 1] = t.y;
    out[kVTangent + 2] = t.z;
    out[kVTangent + 3] = a[kTangent + 3];

    return mvp * local;
  }
}

/// `mesh_lightmapped.vert`: the mesh stage reading its colour as a place in
/// the level's lightmap.
///
/// Everything `mesh.vert` does, then the colour handed on as the coordinate
/// and the tint held at white — which is exactly what the GLSL does, and
/// reusing the plain stage keeps the two from drifting on the arithmetic
/// they share.
final class MeshLightmappedVertexShader implements CpuVertexShaderByIndex {
  const MeshLightmappedVertexShader();

  static const MeshVertexShader _plain = MeshVertexShader();

  @override
  int get varyingCount => kMeshVaryings;

  @override
  Vector4 run(Float32List a, ShaderBindings bindings, Float32List out) =>
      runAt(-1, 0, a, bindings, out);

  @override
  Vector4 runAt(
    int vertexIndex,
    int instanceIndex,
    Float32List a,
    ShaderBindings bindings,
    Float32List out,
  ) {
    final clip = _plain.runAt(vertexIndex, instanceIndex, a, bindings, out);
    out[kVLightmap] = a[kColour];
    out[kVLightmap + 1] = a[kColour + 1];
    for (var i = 0; i < 4; i++) {
      out[kVColour + i] = 1.0;
    }
    return clip;
  }
}

/// `mesh_skinned.vert`: the mesh stage with a joint blend in front of it.
///
/// The skinned layout is the standard one with joints and weights appended, so
/// the first sixteen floats are read at the same offsets as `mesh.vert` reads
/// them.
/// `mesh_instanced.vert`: the standard mesh, placed by a per-instance affine
/// transform and tinted by a per-instance colour.
///
/// The assembled attributes are slot 0's sixteen floats and then slot 1's
/// sixteen — three rows of the transform and the colour — in the order
/// `cpu_vertex_fetch.dart` says: every attribute of slot 0, then every
/// attribute of slot 1.
final class MeshInstancedVertexShader implements CpuVertexShaderByIndex {
  const MeshInstancedVertexShader();

  static const int _row0 = 16;
  static const int _row1 = 20;
  static const int _row2 = 24;
  static const int _colour = 28;

  @override
  int get varyingCount => kMeshVaryings;

  @override
  Vector4 run(Float32List a, ShaderBindings bindings, Float32List out) =>
      runAt(-1, 0, a, bindings, out);

  @override
  Vector4 runAt(
    int vertexIndex,
    int instanceIndex,
    Float32List a,
    ShaderBindings bindings,
    Float32List out,
  ) {
    final mvp = bindings.mat4('FrameInfo', 'mvp');
    final model = bindings.mat4('FrameInfo', 'model');
    final normalMatrix = bindings.mat4('FrameInfo', 'normal_matrix');

    // The rows as the buffer holds them; `Matrix4` wants columns, so each
    // argument below is one row's worth of a column.
    final instance = Matrix4(
      a[_row0],
      a[_row1],
      a[_row2],
      0.0, // column 0
      a[_row0 + 1],
      a[_row1 + 1],
      a[_row2 + 1],
      0.0, // column 1
      a[_row0 + 2],
      a[_row1 + 2],
      a[_row2 + 2],
      0.0, // column 2
      a[_row0 + 3],
      a[_row1 + 3],
      a[_row2 + 3],
      1.0, // column 3
    );
    // Morphed in the mesh's own space, before the instance transform: every
    // instance of a batch shares the mesh, which is what the GLSL says at the
    // same point. What they need not share is the shape — the instance index
    // goes in, and a batch that gives each copy its own weights is read a row
    // at a time out of a second texture.
    final morphed =
        vertexIndex >= 0 &&
        _morphScratch.load(
          vertexIndex,
          a,
          bindings,
          positionAt: kPosition,
          normalAt: kNormal,
          tangentAt: kTangent,
          instanceIndex: instanceIndex,
        );
    final Vector4 local =
        instance *
        (morphed
            ? Vector4(
                _morphScratch.position.x,
                _morphScratch.position.y,
                _morphScratch.position.z,
                1.0,
              )
            : Vector4(a[kPosition], a[kPosition + 1], a[kPosition + 2], 1.0));
    final Vector4 world = model * local;
    out[kVWorld] = world.x;
    out[kVWorld + 1] = world.y;
    out[kVWorld + 2] = world.z;

    final rotation = instance.getRotation();
    final rotated = rotation.transformed(
      morphed
          ? _morphScratch.normal
          : Vector3(a[kNormal], a[kNormal + 1], a[kNormal + 2]),
    )..normalize();
    final n = normalMatrix.getRotation().transformed(rotated);
    out[kVNormal] = n.x;
    out[kVNormal + 1] = n.y;
    out[kVNormal + 2] = n.z;

    out[kVUv] = a[kTexcoord];
    out[kVUv + 1] = a[kTexcoord + 1];
    for (var i = 0; i < 4; i++) {
      out[kVColour + i] = a[kColour + i] * a[_colour + i];
    }
    out[kVLightmap] = 0.0;
    out[kVLightmap + 1] = 0.0;

    final Vector3 t =
        model.getRotation() *
        (rotation *
            (morphed
                ? Vector3(
                    _morphScratch.tangent.x,
                    _morphScratch.tangent.y,
                    _morphScratch.tangent.z,
                  )
                : Vector3(a[kTangent], a[kTangent + 1], a[kTangent + 2])));
    out[kVTangent] = t.x;
    out[kVTangent + 1] = t.y;
    out[kVTangent + 2] = t.z;
    out[kVTangent + 3] = a[kTangent + 3];

    return mvp * local;
  }
}

final class MeshSkinnedVertexShader implements CpuVertexShaderByIndex {
  const MeshSkinnedVertexShader();

  static const int _joints = 16; // vec4
  static const int _weights = 20; // vec4

  @override
  int get varyingCount => kMeshVaryings;

  @override
  Vector4 run(Float32List a, ShaderBindings bindings, Float32List out) =>
      runAt(-1, 0, a, bindings, out);

  @override
  Vector4 runAt(
    int vertexIndex,
    int instanceIndex,
    Float32List a,
    ShaderBindings bindings,
    Float32List out,
  ) {
    // The weights are renormalised rather than trusted: an exporter that
    // writes three of four and leaves the fourth at zero is common, and a
    // total below one shrinks the vertex towards the origin.
    final total =
        a[_weights] + a[_weights + 1] + a[_weights + 2] + a[_weights + 3];
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
      final joint = bindings.mat4(
        'SkinInfo',
        'joint_matrices',
        at: a[_joints + i].toInt(),
      );
      for (var e = 0; e < 16; e++) {
        skin[e] = skin[e] + joint[e] * w[i];
      }
    }

    final model = bindings.mat4('FrameInfo', 'model');
    final mvp = bindings.mat4('FrameInfo', 'mvp');
    final normalMatrix = bindings.mat4('FrameInfo', 'normal_matrix');

    // Morphed in the rest pose and skinned afterwards, which is the order glTF
    // specifies and the only one that composes: a face morphs where it was
    // modelled and the skeleton then carries it.
    final morphed =
        vertexIndex >= 0 &&
        _morphScratch.load(
          vertexIndex,
          a,
          bindings,
          positionAt: kPosition,
          normalAt: kNormal,
          tangentAt: kTangent,
        );
    final local = morphed
        ? Vector4(
            _morphScratch.position.x,
            _morphScratch.position.y,
            _morphScratch.position.z,
            1.0,
          )
        : Vector4(a[kPosition], a[kPosition + 1], a[kPosition + 2], 1.0);
    final Vector4 skinned = skin * local;
    final Vector4 world = model * skinned;
    out[kVWorld] = world.x;
    out[kVWorld + 1] = world.y;
    out[kVWorld + 2] = world.z;

    final skinRotation = skin.getRotation();
    final Vector3 n =
        normalMatrix.getRotation() *
        (skinRotation *
            (morphed
                ? _morphScratch.normal
                : Vector3(a[kNormal], a[kNormal + 1], a[kNormal + 2])));
    out[kVNormal] = n.x;
    out[kVNormal + 1] = n.y;
    out[kVNormal + 2] = n.z;

    out[kVUv] = a[kTexcoord];
    out[kVUv + 1] = a[kTexcoord + 1];
    for (var i = 0; i < 4; i++) {
      out[kVColour + i] = a[kColour + i];
    }
    out[kVLightmap] = 0.0;
    out[kVLightmap + 1] = 0.0;

    final Vector3 t =
        model.getRotation() *
        (skinRotation *
            (morphed
                ? Vector3(
                    _morphScratch.tangent.x,
                    _morphScratch.tangent.y,
                    _morphScratch.tangent.z,
                  )
                : Vector3(a[kTangent], a[kTangent + 1], a[kTangent + 2])));
    out[kVTangent] = t.x;
    out[kVTangent + 1] = t.y;
    out[kVTangent + 2] = t.z;
    out[kVTangent + 3] = a[kTangent + 3];

    return mvp * skinned;
  }
}
