import 'dart:typed_data';

import 'package:vector_math/vector_math.dart';

/// One shape a mesh can be blended towards, as deltas from its base vertices.
///
/// **Deltas, not poses, because that is what glTF stores and what blends.** A
/// face with a smile target and a blink target has to be able to do both at
/// once; adding two deltas does that and interpolating between two absolute
/// poses does not. The vertex a renderer draws is
///
///     base + Σ weightᵢ × deltaᵢ
///
/// which is linear in the weights, so the order they are applied in cannot
/// matter and a weight of nought costs exactly nothing.
///
/// **Positions always, normals and tangents when the file carries them.** glTF
/// allows a target to morph POSITION alone, and most do: a delta of a few
/// millimetres barely turns a normal, and an exporter that leaves them out is
/// making that judgement rather than losing data. A target with no normals
/// leaves the base normals alone, which is the same answer the file intends.
///
/// **Tangent deltas are three floats and not four.** The vertex tangent is a
/// `vec4` whose w is the bitangent sign — a handedness, not a direction — and
/// glTF morphs only the xyz. Blending the sign would be blending a decision.
final class MorphTarget {
  MorphTarget({
    required this.vertexCount,
    required this.positions,
    this.normals,
    this.tangents,
    this.name,
  }) {
    _check('positions', positions, 3);
    _check('normals', normals, 3);
    _check('tangents', tangents, 3);
  }

  void _check(String what, Float32List? values, int components) {
    if (values == null) return;
    if (values.length != vertexCount * components) {
      throw ArgumentError(
        'morph target $what has ${values.length} floats for $vertexCount '
        'vertices at $components each, which is not '
        '${vertexCount * components}. A target that does not cover the mesh '
        'would blend some vertices and leave others behind it.',
      );
    }
  }

  /// How many vertices the target covers, which is the mesh's own count.
  final int vertexCount;

  /// Position deltas, three floats a vertex.
  final Float32List positions;

  /// Normal deltas, three floats a vertex, or null when the file had none.
  final Float32List? normals;

  /// Tangent deltas, three floats a vertex — see the class doc on the w.
  final Float32List? tangents;

  /// The box this target's position deltas span, in the mesh's own space.
  ///
  /// **What a bounding box has to be told about.** A mesh's bounds describe its
  /// base vertices, and a morphed vertex is somewhere else — so a face that
  /// opens its jaw past the box around its rest pose is culled while it is on
  /// screen, and its shadow falls out of the cascade fitted to that box. That
  /// is exactly the trap skinning has, where `MeshNode.skinReach` closes it.
  ///
  /// **Per axis rather than a radius**, which is not fussiness: a target that
  /// only lifts a jaw moves nothing sideways, and a sphere of that radius grows
  /// the box in two directions it never reaches. On a model whose deltas are
  /// large next to its own size — `AnimatedMorphCube`, whose targets are twice
  /// the cube — a radius put the camera far enough back to shrink the subject
  /// to a third of the frame.
  ///
  /// Measured once, lazily, and only over positions: a normal or a tangent
  /// delta turns a vertex without moving it. A target whose deltas are all
  /// nought spans nothing, which grows nothing.
  late final Aabb3 displacement = () {
    var minX = 0.0, minY = 0.0, minZ = 0.0;
    var maxX = 0.0, maxY = 0.0, maxZ = 0.0;
    for (var v = 0; v < vertexCount; v++) {
      final x = positions[v * 3];
      final y = positions[v * 3 + 1];
      final z = positions[v * 3 + 2];
      if (x < minX) minX = x;
      if (y < minY) minY = y;
      if (z < minZ) minZ = z;
      if (x > maxX) maxX = x;
      if (y > maxY) maxY = y;
      if (z > maxZ) maxZ = z;
    }
    return Aabb3.minMax(Vector3(minX, minY, minZ), Vector3(maxX, maxY, maxZ));
  }();

  /// What the file called it, when it said.
  ///
  /// glTF puts target names in `mesh.extras.targetNames`, which is a convention
  /// rather than part of the format, so this is often null. A game that drives
  /// a face by name needs it; one driving it by index does not.
  final String? name;

  @override
  String toString() =>
      'MorphTarget(${name ?? 'unnamed'}, $vertexCount vertices'
      '${normals != null ? ', normals' : ''}'
      '${tangents != null ? ', tangents' : ''})';
}
