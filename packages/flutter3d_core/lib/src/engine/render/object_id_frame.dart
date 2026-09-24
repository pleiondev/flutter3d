import 'dart:typed_data';

import '../scene/mesh_node.dart';

/// Which mesh drew every pixel of one frame — what
/// `Renderer.captureObjectIds` answers with.
///
/// **The pick pass read back whole.** `Renderer.pickPixel` asks the id
/// target for one pixel; this is the same target, the same ids and the same
/// rules — a masked hole is a hole, a blended surface counts as a surface, an
/// instanced batch is one id — kept for the whole frame, so a tool with no
/// pointer can ask what is on the screen everywhere at once: how many pixels
/// a wall owns, where on the screen it is, and what stands in front of it.
///
/// Rows run from the top, like every picture this engine reads back.
final class ObjectIdFrame {
  const ObjectIdFrame({
    required this.width,
    required this.height,
    required this.ids,
    required this.nodes,
  });

  final int width;
  final int height;

  /// One id per pixel, row-major from the top: zero where nothing was drawn,
  /// otherwise a one-based index into [nodes].
  final Uint32List ids;

  /// Every mesh the id pass drew this frame, in the order drawn. Id `n` is
  /// `nodes[n - 1]`.
  final List<MeshNode> nodes;

  /// The id at ([x], [y]), zero for nothing.
  int idAt(int x, int y) => ids[y * width + x];

  /// The mesh drawn at ([x], [y]), or null where nothing was.
  MeshNode? nodeAt(int x, int y) {
    final id = idAt(x, y);
    return id == 0 ? null : nodes[id - 1];
  }

  /// How many pixels each id owns, indexed by id; entry zero is the pixels
  /// nothing reached.
  Uint32List pixelCounts() {
    final counts = Uint32List(nodes.length + 1);
    for (final id in ids) {
      counts[id]++;
    }
    return counts;
  }
}
