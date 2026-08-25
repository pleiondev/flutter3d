import 'dart:typed_data';

/// The triangles of every brush sharing one material *and* one answer about
/// shadows.
///
/// Plain arrays rather than the engine's `MeshData`, because this package does
/// not depend on the engine and should not: turning brushes into triangles is
/// arithmetic, and arithmetic has no business knowing about a GPU. The
/// application interleaves these into whatever vertex layout it draws with,
/// which is about twenty lines and the only place the two packages meet.
final class BrushSurface {
  BrushSurface({
    required this.material,
    required this.castsShadow,
    required this.positions,
    required this.normals,
    required this.texcoords,
    required this.tangents,
    required this.indices,
  });

  final String material;

  /// Whether the mesh built from this takes part in the shadow pass.
  ///
  /// **The reason surfaces are keyed by this as well as by material.** Brushes
  /// are batched so that a level of two hundred and fifty of them is a handful
  /// of draws, and a batch is the smallest thing that can answer — so a fence
  /// and a wall of the same stone had to stop sharing one.
  final bool castsShadow;

  /// Three floats per vertex.
  final Float32List positions;

  /// Three floats per vertex.
  final Float32List normals;

  /// Two floats per vertex.
  final Float32List texcoords;

  /// Four floats per vertex: the tangent direction, and a handedness sign.
  ///
  /// Emitted here rather than left to the caller because the generator already
  /// knows each face's two axes, and rebuilding tangents from triangles
  /// afterwards is both slower and less accurate.
  ///
  /// The sign follows glTF: `bitangent = cross(normal, tangent.xyz) * w`, and
  /// glTF's bitangent is **minus** dP/dv, because texture V grows downwards
  /// while a normal map's green channel points up. With `cross(u, v) == normal`
  /// that makes `cross(normal, u) == v`, so the sign is -1. Getting it backwards
  /// lights normal-mapped surfaces from the wrong side, and only on mirrored
  /// UVs — which is exactly the bug this project already spent a day on once.
  final Float32List tangents;

  final Uint32List indices;

  int get vertexCount => positions.length ~/ 3;
  int get triangleCount => indices.length ~/ 3;
}
