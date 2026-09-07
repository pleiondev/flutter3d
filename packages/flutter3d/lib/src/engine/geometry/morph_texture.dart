import 'dart:typed_data';

import 'mesh_data.dart';

/// A mesh's morph deltas, packed the way `lib/morph.glsl` reads them.
///
/// **A texture rather than vertex attributes, and the layout is structural.**
/// The `in` declarations of `mesh.vert` *are* the vertex layout, and one layout
/// serves every model so that a lighting model costs one pipeline instead of
/// one per attribute set. Deltas as attributes would mean a second layout, and
/// with it a second vertex shader for each of six lighting models. A texture
/// costs one sampler and no layout — which is only an option because a vertex
/// stage can sample one, measured on all three backends by
/// `checkVertexTextureSampling` rather than assumed.
///
/// ## The layout
///
/// `r32g32b32a32Float`, width the mesh's vertex count, height three rows per
/// target:
///
///     row + 0   position delta, xyz, w unused
///     row + 1   normal delta
///     row + 2   tangent delta, xyz only — w is a handedness and glTF does not
///               morph it
///
/// Three rows always, even for a target that morphs positions alone. That
/// costs two rows of zeros and buys arithmetic instead of a lookup table: the
/// shader finds a target's first row by multiplying. A face of ten thousand
/// vertices with four targets is 10000 × 12 texels — about two megabytes, once,
/// for the life of the mesh.
///
/// **Full floats and not halves.** A delta is small next to the vertex it moves
/// — a millimetre on a model measured in metres — and a half float's precision
/// is relative to its own value, so the deltas themselves would survive. What
/// would not is the sum: eight targets at a weight apiece, each rounded, added
/// onto a position that is already large. The surface buffer paid for exactly
/// that arithmetic two days ago.
final class MorphTexture {
  MorphTexture._({
    required this.width,
    required this.height,
    required this.pixels,
    required this.targetCount,
    required this.reaches,
  });

  /// Packs [mesh]'s targets, or null when it has none.
  ///
  /// [limit] is the most targets the shader can blend — `kMorphMax` in
  /// `lib/morph.glsl`. A mesh carrying more is packed up to it rather than
  /// refused, and [dropped] says how many were left out, so a caller can warn
  /// once instead of a model failing to load over an expression nobody uses.
  static MorphTexture? pack(MeshData mesh, {int limit = 8}) {
    if (mesh.morphTargets.isEmpty) return null;

    final used = mesh.morphTargets.length < limit
        ? mesh.morphTargets.length
        : limit;
    final width = mesh.vertexCount;
    final height = used * rowsPerTarget;
    final pixels = Float32List(width * height * 4);

    for (var t = 0; t < used; t++) {
      final target = mesh.morphTargets[t];
      final base = t * rowsPerTarget;
      _row(pixels, width, base, target.positions);
      _row(pixels, width, base + 1, target.normals);
      _row(pixels, width, base + 2, target.tangents);
    }

    return MorphTexture._(
      width: width,
      height: height,
      pixels: pixels,
      targetCount: used,
      reaches: <double>[
        for (var t = 0; t < used; t++) mesh.morphTargets[t].maxDisplacement,
      ],
    );
  }

  /// Rows one target occupies. Matches `kMorphRows` in `lib/morph.glsl`, and
  /// the two have to move together.
  static const int rowsPerTarget = 3;

  /// Three floats a vertex into one row of four-float texels.
  ///
  /// A null stream leaves the row as zeros, which is what a target that morphs
  /// only positions means: the shader adds nothing to the normal.
  static void _row(
    Float32List pixels,
    int width,
    int row,
    Float32List? deltas,
  ) {
    if (deltas == null) return;
    final start = row * width * 4;
    for (var v = 0; v < width; v++) {
      final from = v * 3;
      final into = start + v * 4;
      pixels[into] = deltas[from];
      pixels[into + 1] = deltas[from + 1];
      pixels[into + 2] = deltas[from + 2];
    }
  }

  final int width;
  final int height;

  /// The texels, four floats each, ready for `createTextureFromPixels`.
  final Float32List pixels;

  /// How many targets are in the texture, which is what the shader is told.
  final int targetCount;

  /// How far each packed target moves the vertex it moves most, so a bounding
  /// box can be told what an expression reaches — see `MorphState.reach`.
  final List<double> reaches;

  /// How many the mesh had that did not fit.
  int dropped(MeshData mesh) => mesh.morphTargets.length - targetCount;

  ByteData get bytes =>
      pixels.buffer.asByteData(pixels.offsetInBytes, pixels.lengthInBytes);

  @override
  String toString() =>
      'MorphTexture($targetCount targets, $width x $height texels)';
}
