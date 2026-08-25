import 'dart:typed_data';

/// glTF primitive topology.
///
/// The conversion to a triangle list lives here rather than as a static helper on
/// the loader: it is entirely determined by the topology, and keeping it on the
/// enum means the switch is exhaustive by construction.
enum GltfPrimitiveMode {
  points(0),
  lines(1),
  lineLoop(2),
  lineStrip(3),
  triangles(4),
  triangleStrip(5),
  triangleFan(6);

  const GltfPrimitiveMode(this.code);

  final int code;

  static GltfPrimitiveMode fromCode(int code) {
    for (final value in values) {
      if (value.code == code) return value;
    }
    throw FormatException('Unknown glTF primitive mode $code.');
  }

  /// Whether this topology produces triangles at all.
  bool get isTriangles =>
      this == triangles || this == triangleStrip || this == triangleFan;

  /// Rewrites the indices as an ordinary triangle list.
  ///
  /// Doing it here keeps the renderer on a single primitive type and avoids a
  /// pipeline permutation per topology, which matters when pipelines are built
  /// ahead of time.
  Uint32List toTriangleList(Uint32List indices) {
    switch (this) {
      case GltfPrimitiveMode.triangles:
        // Trailing indices that do not complete a triangle are dropped.
        final usable = indices.length - (indices.length % 3);
        return usable == indices.length
            ? indices
            : Uint32List.sublistView(indices, 0, usable);

      case GltfPrimitiveMode.triangleStrip:
        if (indices.length < 3) return Uint32List(0);
        final out = Uint32List((indices.length - 2) * 3);
        var w = 0;
        for (var i = 0; i + 2 < indices.length; i++) {
          // Every other triangle is wound backwards; swapping two indices
          // restores a consistent orientation for the whole strip.
          if (i.isEven) {
            out[w++] = indices[i];
            out[w++] = indices[i + 1];
            out[w++] = indices[i + 2];
          } else {
            out[w++] = indices[i + 1];
            out[w++] = indices[i];
            out[w++] = indices[i + 2];
          }
        }
        return out;

      case GltfPrimitiveMode.triangleFan:
        if (indices.length < 3) return Uint32List(0);
        final out = Uint32List((indices.length - 2) * 3);
        var w = 0;
        for (var i = 1; i + 1 < indices.length; i++) {
          out[w++] = indices[0];
          out[w++] = indices[i];
          out[w++] = indices[i + 1];
        }
        return out;

      case GltfPrimitiveMode.points:
      case GltfPrimitiveMode.lines:
      case GltfPrimitiveMode.lineLoop:
      case GltfPrimitiveMode.lineStrip:
        return Uint32List(0);
    }
  }
}
