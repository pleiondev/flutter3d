import 'dart:typed_data';

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
