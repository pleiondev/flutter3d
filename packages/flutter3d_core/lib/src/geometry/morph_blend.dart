import 'dart:typed_data';

import 'mesh_data.dart';
import 'vertex_layout.dart';

/// Blends a mesh's morph targets into a copy of its vertices.
///
/// **On the CPU, and that is a decision with a cost worth naming.** The vertex
/// layout in this engine is *structural* — the `in` declarations of `mesh.vert`
/// are the layout, and one layout serves every model so that a lighting model
/// does not need a pipeline per attribute set. Morphing on the GPU means either
/// a second layout, and with it a second vertex shader per lighting model, or
/// the deltas in a texture the vertex stage samples by vertex id. No vertex
/// stage in this engine samples anything today, and whether flutter_gpu binds a
/// texture to one is unmeasured rather than known.
///
/// So this blends where every backend can already draw the result: into the
/// vertex buffer, which is then uploaded like any other. What it costs is a
/// pass over the mesh and an upload on every frame the weights change, which is
/// affordable for the thing morph targets are actually for — a face, a few
/// thousand vertices, one of them on screen — and is not affordable for a crowd.
/// A GPU path would replace this for the two hardware backends and leave it
/// here for the software one, which has no other way to do it.
///
/// **Nothing is recomputed when nothing moved.** [blend] returns false when the
/// weights it was handed are the ones already applied, so a face holding an
/// expression costs one comparison a frame rather than a pass and an upload.
final class MorphBlend {
  MorphBlend(this.mesh)
    : _blended = Float32List.fromList(mesh.vertices),
      _applied = Float64List(mesh.morphTargets.length);

  final MeshData mesh;

  /// The blended vertices, in the mesh's own layout and stride.
  ///
  /// Starts as a copy of the base, so a mesh whose weights are all nought draws
  /// exactly as it would without any of this.
  Float32List get vertices => _blended;
  final Float32List _blended;

  /// The weights [_blended] currently holds.
  ///
  /// **Sixty-four bits, and the thirty-two-bit version was a defect the test
  /// found.** A weight arrives as a `double`; stored in a `Float32List`, 0.4
  /// comes back as 0.4000000059604645, so the comparison below never matched
  /// and every frame rebuilt the whole mesh and re-uploaded it. The skip is the
  /// entire point of keeping these, so keeping them in a form that cannot
  /// compare equal made it a slower way of doing the same work.
  final Float64List _applied;

  /// What the weights were when the vertices were last written.
  List<double> get appliedWeights => List<double>.unmodifiable(_applied);

  /// Blends [weights] into [vertices], and says whether anything changed.
  ///
  /// Weights beyond the targets the mesh has are ignored rather than refused: a
  /// clip authored against a newer version of a model is a thing that happens,
  /// and drawing the shapes that do exist is better than drawing nothing.
  bool blend(List<double> weights) {
    if (!_differs(weights)) return false;

    for (var i = 0; i < _applied.length; i++) {
      _applied[i] = i < weights.length ? weights[i] : 0.0;
    }

    // From the base every time rather than by undoing the last blend: deltas
    // accumulate rounding, and a face that has smiled a thousand times would
    // drift away from the shape it started as.
    _blended.setAll(0, mesh.vertices);

    final stride = mesh.layout.floatsPerVertex;
    final positionAt = mesh.layout.floatOffsetOf(VertexLayout.position.name);
    final normalAt = mesh.layout.floatOffsetOf(VertexLayout.normal.name);
    final tangentAt = mesh.layout.floatOffsetOf(VertexLayout.tangent.name);

    for (var t = 0; t < mesh.morphTargets.length; t++) {
      final weight = _applied[t];
      if (weight == 0.0) continue;
      final target = mesh.morphTargets[t];

      if (positionAt >= 0) {
        _add(target.positions, positionAt, stride, weight, 3);
      }
      if (normalAt >= 0 && target.normals != null) {
        _add(target.normals!, normalAt, stride, weight, 3);
      }
      // Three components into a four-component attribute: the tangent's w is a
      // handedness and is left exactly as the base had it. See [MorphTarget].
      if (tangentAt >= 0 && target.tangents != null) {
        _add(target.tangents!, tangentAt, stride, weight, 3);
      }
    }
    return true;
  }

  void _add(
    Float32List deltas,
    int offset,
    int stride,
    double weight,
    int components,
  ) {
    final count = mesh.vertexCount;
    for (var v = 0; v < count; v++) {
      final into = v * stride + offset;
      final from = v * components;
      for (var c = 0; c < components; c++) {
        _blended[into + c] += deltas[from + c] * weight;
      }
    }
  }

  bool _differs(List<double> weights) {
    for (var i = 0; i < _applied.length; i++) {
      final wanted = i < weights.length ? weights[i] : 0.0;
      if (_applied[i] != wanted) return true;
    }
    return false;
  }
}
