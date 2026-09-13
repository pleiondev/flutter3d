import 'dart:typed_data';

import 'package:flutter3d_geometry/flutter3d_geometry.dart';

/// Skins a mesh's positions, normals and tangent directions on the CPU, into
/// a copy of its vertex buffer — `anim-02`'s own row, the skinning half of
/// what [MorphBlend] already does for morph targets.
///
/// **Mirrors `mesh_skinned.vert`'s own arithmetic exactly, not an
/// approximation of it**: the same four-joint weighted blend, the same
/// renormalization for weights an exporter left not quite summing to one,
/// the same "rotation only" treatment of a joint's own 3×3 for normals and
/// tangents (a joint that only rotates and translates, which is every rig in
/// practice — see that shader's own comment on why a non-uniformly scaled
/// joint is the trade this does not make).
/// `cpu_skin_blend_test.dart` holds this to `MeshSkinnedVertexShader`, the
/// software rasteriser's own copy of that shader — from `flutter3d_cpu`,
/// dev-depended on for this one test rather than assuming two arithmetic
/// paths agree because they were written to look alike.
///
/// **Nothing is recomputed when nothing moved.** [blend] returns false when
/// the joint matrices it was handed are the ones already applied, the same
/// skip [MorphBlend.blend] does for weights and for the identical reason: a
/// paused animation, or a rig that has settled, costs one comparison a call
/// rather than a pass over every vertex.
final class SkinBlend {
  SkinBlend(this.mesh) : _blended = Float32List.fromList(mesh.vertices) {
    if (!mesh.layout.isSkinned) {
      throw ArgumentError(
        'SkinBlend needs a mesh with joints and weights; ${mesh.layout} has '
        'neither.',
      );
    }
  }

  final MeshData mesh;

  /// The skinned vertices, in the mesh's own layout and stride.
  ///
  /// Starts as a copy of the bind pose, so a mesh nobody has [blend]ed yet
  /// reads exactly as it would without this.
  Float32List get vertices => _blended;
  final Float32List _blended;

  /// The joint matrices [vertices] currently reflects, or null before the
  /// first [blend].
  Float32List? _applied;

  /// Blends [jointMatrices] into [vertices], and says whether anything
  /// changed.
  ///
  /// [jointMatrices] is `Skeleton.matrices`/`Pose.jointMatrices`'s own
  /// shape: sixteen column-major floats a joint, joint `i` starting at
  /// `i * 16`, however many joints the caller has padded it to.
  bool blend(Float32List jointMatrices) {
    if (!_differs(jointMatrices)) return false;
    _applied = Float32List.fromList(jointMatrices);

    final layout = mesh.layout;
    final stride = layout.floatsPerVertex;
    final positionAt = layout.floatOffsetOf(VertexLayout.position.name);
    final normalAt = layout.floatOffsetOf(VertexLayout.normal.name);
    final tangentAt = layout.floatOffsetOf(VertexLayout.tangent.name);
    final jointsAt = layout.floatOffsetOf(VertexLayout.joints.name);
    final weightsAt = layout.floatOffsetOf(VertexLayout.weights.name);

    final base = mesh.vertices;
    final skin = _skinScratch;

    for (var v = 0; v < mesh.vertexCount; v++) {
      final at = v * stride;
      _skinMatrixAt(base, at + jointsAt, at + weightsAt, jointMatrices, skin);

      if (positionAt >= 0) {
        _transformPoint(skin, base, at + positionAt, _blended, at + positionAt);
      }
      if (normalAt >= 0) {
        _transformDirection(skin, base, at + normalAt, _blended, at + normalAt);
      }
      if (tangentAt >= 0) {
        // xyz only — w is the tangent's handedness, untouched by anything
        // that only rotates and translates, the same reason `mesh_skinned
        // .vert` writes `morphed_tangent.w` straight through.
        _transformDirection(
          skin,
          base,
          at + tangentAt,
          _blended,
          at + tangentAt,
        );
      }
    }
    return true;
  }

  /// Scratch for the blended 4×4, reused across vertices rather than
  /// allocated per one: `blend` runs the whole mesh every time it runs at
  /// all, and a `Float32List(16)` per vertex is exactly the allocation
  /// pattern this engine's hot loops are written to avoid.
  final Float32List _skinScratch = Float32List(16);

  /// The blended bone transform for one vertex — the same renormalization
  /// `mesh_skinned.vert`'s own `SkinMatrix()` does, including the fallback
  /// to full influence on the first joint when the weights sum to nothing.
  void _skinMatrixAt(
    Float32List base,
    int jointsAt,
    int weightsAt,
    Float32List jointMatrices,
    Float32List skin,
  ) {
    final w0 = base[weightsAt];
    final w1 = base[weightsAt + 1];
    final w2 = base[weightsAt + 2];
    final w3 = base[weightsAt + 3];
    final total = w0 + w1 + w2 + w3;
    final weights = total > 1e-5
        ? <double>[w0 / total, w1 / total, w2 / total, w3 / total]
        : const <double>[1.0, 0.0, 0.0, 0.0];

    for (var e = 0; e < 16; e++) {
      skin[e] = 0.0;
    }
    for (var i = 0; i < 4; i++) {
      final w = weights[i];
      // Skipped rather than blended at zero weight: a vertex naming a joint
      // this pose has no matrix for — a mesh authored against a bigger rig
      // than the one that loaded — would otherwise read past the array for
      // a contribution that adds nothing anyway.
      if (w == 0.0) continue;
      final joint = base[jointsAt + i].toInt() * 16;
      for (var e = 0; e < 16; e++) {
        skin[e] += jointMatrices[joint + e] * w;
      }
    }
  }

  static void _transformPoint(
    Float32List m,
    Float32List from,
    int fromAt,
    Float32List into,
    int intoAt,
  ) {
    final x = from[fromAt], y = from[fromAt + 1], z = from[fromAt + 2];
    into[intoAt] = m[0] * x + m[4] * y + m[8] * z + m[12];
    into[intoAt + 1] = m[1] * x + m[5] * y + m[9] * z + m[13];
    into[intoAt + 2] = m[2] * x + m[6] * y + m[10] * z + m[14];
  }

  /// The rotation-only 3×3 of [m], applied to a direction rather than a
  /// point — no translation term, the same treatment `mat3(skin)` gets in
  /// the shader.
  static void _transformDirection(
    Float32List m,
    Float32List from,
    int fromAt,
    Float32List into,
    int intoAt,
  ) {
    final x = from[fromAt], y = from[fromAt + 1], z = from[fromAt + 2];
    into[intoAt] = m[0] * x + m[4] * y + m[8] * z;
    into[intoAt + 1] = m[1] * x + m[5] * y + m[9] * z;
    into[intoAt + 2] = m[2] * x + m[6] * y + m[10] * z;
  }

  bool _differs(Float32List jointMatrices) {
    final applied = _applied;
    if (applied == null || applied.length != jointMatrices.length) {
      return true;
    }
    for (var i = 0; i < jointMatrices.length; i++) {
      if (applied[i] != jointMatrices[i]) return true;
    }
    return false;
  }
}
