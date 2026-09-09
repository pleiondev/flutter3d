/// Turning a drawable mesh back into an editable one.
///
/// **The direction that loses nothing is the other one.** `EditMesh` knows what
/// is next to what and hands a renderer a `MeshData` by throwing that away —
/// splitting a corner per face normal, per UV island, per material. Coming back
/// means rebuilding what was discarded from what survived, and every step of it
/// is a guess that has to be reported rather than made silently:
///
///   * **Welding.** A cube arrives as twenty-four vertices standing in eight
///     places. Whether two of them are one corner or two corners that happen to
///     coincide is not in the file; the answer this takes is distance, with the
///     tolerance scaled to the model so that a millimetre on a building and a
///     millimetre on a bolt are not the same question.
///   * **Orientation.** Half the models in the world have a face wound the
///     other way, and a mesh where neighbours disagree has no consistent
///     outside — normals flip, the volume comes out wrong, and an extrusion
///     goes inwards. Fixed by walking the faces and flipping the ones that
///     disagree with the neighbour they were reached from.
///   * **Non-manifold edges.** Three faces meeting along one edge is a shape a
///     half-edge structure cannot hold: a half-edge has one twin. The edge is
///     split — the third face gets its own copies of the two vertices — and the
///     count says how often, because a model that needed it is a model somebody
///     should look at.
///
/// Everything the import decided is in the [ImportReport]. Nothing here is
/// silent, and that is the difference between an importer and a black box.
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter3d_geometry/flutter3d_geometry.dart';
import 'package:vector_math/vector_math.dart';

import 'attributes.dart';
import 'edit_mesh.dart';

/// What an import had to decide, and how often.
final class ImportReport {
  const ImportReport({
    required this.sourceVertices,
    required this.weldedVertices,
    required this.faces,
    required this.flippedFaces,
    required this.splitNonManifold,
    required this.droppedDegenerate,
    required this.weldEpsilon,
  });

  /// Vertices the `MeshData` held.
  final int sourceVertices;

  /// How many of them were merged away — twenty-four to eight for a cube.
  final int weldedVertices;

  /// Faces the mesh ended up with.
  final int faces;

  /// Faces turned around so their neighbours agree with them.
  ///
  /// A number of zero on a model from a working exporter, and a number equal to
  /// half the faces on one that was mirrored without its winding being fixed.
  final int flippedFaces;

  /// Edges that had a third face on them, each of which cost a pair of
  /// duplicated vertices.
  ///
  /// **Not an error and not nothing.** The mesh that comes back is a valid
  /// half-edge mesh, and it is not quite the mesh in the file: the third face
  /// is no longer attached along that edge. A caller shows this.
  final int splitNonManifold;

  /// Triangles thrown away for naming the same vertex twice after welding.
  final int droppedDegenerate;

  /// The distance under which two vertices were taken for one.
  final double weldEpsilon;

  /// Whether anything happened that a person should be told about.
  bool get worthReporting =>
      flippedFaces > 0 || splitNonManifold > 0 || droppedDegenerate > 0;

  @override
  String toString() =>
      'ImportReport(${sourceVertices - weldedVertices} vertices from '
      '$sourceVertices, $faces faces, $flippedFaces flipped, '
      '$splitNonManifold edges split, $droppedDegenerate degenerate dropped)';
}

/// Rebuilds an editable mesh from a drawable one.
///
/// [weldEpsilon] defaults to a millionth of the model's diagonal, which is
/// under the precision a float carries at that size and over the drift an
/// exporter introduces. Pass zero to weld only exact matches.
(EditMesh, ImportReport) importMeshData(MeshData mesh, {double? weldEpsilon}) {
  final layout = mesh.layout;
  final stride = layout.floatsPerVertex;
  final positionAt = layout.floatOffsetOf(VertexLayout.position.name);
  final uvAt = layout.floatOffsetOf(VertexLayout.texcoord.name);
  final colourAt = layout.floatOffsetOf(VertexLayout.color.name);
  final sourceVertices = mesh.vertexCount;

  final bounds = mesh.computeBounds();
  final diagonal = (bounds.max - bounds.min).length;
  final epsilon = weldEpsilon ?? math.max(diagonal * 1e-6, 1e-9);

  // ------------------------------------------------------------------ welding

  // A grid of cells one epsilon across, so two vertices within epsilon are
  // either in the same cell or in one of the twenty-six around it. Checking all
  // twenty-seven is what keeps two points on either side of a cell boundary
  // from being missed — the failure a plain hash of quantised coordinates has,
  // and the reason a seam sometimes welds on one machine and not another.
  final cells = <int, List<int>>{};
  final welded = Int32List(sourceVertices);
  final unique = <Vector3>[];

  int cellKey(int x, int y, int z) =>
      // Three coordinates into one int, which Dart holds at 64 bits on every
      // platform this runs on except the web — where the doubles are exact to
      // 2^53 and these fit inside it for any model with a sane bounding box.
      (x & 0x1FFFFF) | ((y & 0x1FFFFF) << 21) | ((z & 0x1FFFFF) << 42);

  final scale = epsilon > 0 ? 1 / epsilon : 0.0;
  for (var vertex = 0; vertex < sourceVertices; vertex++) {
    final base = vertex * stride + positionAt;
    final x = mesh.vertices[base];
    final y = mesh.vertices[base + 1];
    final z = mesh.vertices[base + 2];

    final cx = epsilon > 0 ? (x * scale).floor() : 0;
    final cy = epsilon > 0 ? (y * scale).floor() : 0;
    final cz = epsilon > 0 ? (z * scale).floor() : 0;

    var found = -1;
    search:
    for (var dx = -1; dx <= 1; dx++) {
      for (var dy = -1; dy <= 1; dy++) {
        for (var dz = -1; dz <= 1; dz++) {
          final bucket = cells[cellKey(cx + dx, cy + dy, cz + dz)];
          if (bucket == null) continue;
          for (final candidate in bucket) {
            final at = unique[candidate];
            if ((at.x - x).abs() <= epsilon &&
                (at.y - y).abs() <= epsilon &&
                (at.z - z).abs() <= epsilon) {
              found = candidate;
              break search;
            }
          }
        }
      }
    }

    if (found < 0) {
      found = unique.length;
      unique.add(Vector3(x, y, z));
      cells.putIfAbsent(cellKey(cx, cy, cz), () => <int>[]).add(found);
    }
    welded[vertex] = found;
  }

  // ------------------------------------------------------------------- faces

  // Triangles over welded vertices, with the source corners kept so the UVs and
  // colours can follow. A triangle that names one vertex twice after welding
  // has no area and no winding; keeping it would make every normal and every
  // twin around it meaningless.
  final triangles = <List<int>>[];
  final sourceCorners = <List<int>>[];
  var dropped = 0;
  for (var i = 0; i + 2 < mesh.indices.length; i += 3) {
    final a = welded[mesh.indices[i]];
    final b = welded[mesh.indices[i + 1]];
    final c = welded[mesh.indices[i + 2]];
    if (a == b || b == c || a == c) {
      dropped++;
      continue;
    }
    triangles.add(<int>[a, b, c]);
    sourceCorners.add(<int>[
      mesh.indices[i],
      mesh.indices[i + 1],
      mesh.indices[i + 2],
    ]);
  }

  final flipped = _repairOrientation(triangles, sourceCorners);

  // ------------------------------------------------------- non-manifold split

  final builder = EditMeshBuilder();
  for (final point in unique) {
    builder.addVertex(point);
  }

  // Directed edges already taken. A second face using `a -> b` the same way
  // round is the third face on that edge: two faces sharing an edge use it in
  // opposite directions, which is what makes them twins.
  final taken = <int>{};
  var split = 0;
  final faceCorners = <List<int>>[];

  int edgeKey(int from, int to) => from * 0x100000000 + to;

  for (var index = 0; index < triangles.length; index++) {
    final loop = List<int>.of(triangles[index]);
    // Duplicating a vertex frees every edge that used it, so this repeats until
    // the whole triangle fits. Three passes is the most it can need.
    for (var attempt = 0; attempt < 3; attempt++) {
      var conflict = -1;
      for (var corner = 0; corner < 3; corner++) {
        final from = loop[corner];
        final to = loop[(corner + 1) % 3];
        if (taken.contains(edgeKey(from, to))) {
          conflict = corner;
          break;
        }
      }
      if (conflict < 0) break;

      // The third face gets its own copies of the two vertices the contested
      // edge runs between, which detaches it along that edge and leaves the
      // first two joined.
      split++;
      final from = conflict;
      final to = (conflict + 1) % 3;
      loop[from] = builder.addVertex(unique[loop[from]]);
      loop[to] = builder.addVertex(unique[loop[to]]);
    }

    for (var corner = 0; corner < 3; corner++) {
      taken.add(edgeKey(loop[corner], loop[(corner + 1) % 3]));
    }
    builder.addFace(loop);
    faceCorners.add(sourceCorners[index]);
  }

  final result = builder.build();

  // ------------------------------------------------------------------ corners

  // UVs and colours are per corner in both representations, so they copy across
  // directly — and only where the source had them. A layout with no texcoord,
  // or a mesh whose every UV is the origin, leaves the layer uncreated.
  if (uvAt >= 0 || colourAt >= 0) {
    final uv = Vector2.zero();
    final colour = Vector4.zero();
    result.beginStep();
    for (var face = 0; face < faceCorners.length; face++) {
      final corners = faceCorners[face];
      var corner = 0;
      result.forEachHalfEdge(face, (int half) {
        final source = corners[corner++];
        if (uvAt >= 0) {
          uv.setValues(
            mesh.vertices[source * stride + uvAt],
            mesh.vertices[source * stride + uvAt + 1],
          );
        }
        if (colourAt >= 0) {
          colour.setValues(
            mesh.vertices[source * stride + colourAt],
            mesh.vertices[source * stride + colourAt + 1],
            mesh.vertices[source * stride + colourAt + 2],
            mesh.vertices[source * stride + colourAt + 3],
          );
        }
        result.setCorner(half, CornerAttributes(uv: uv, colour: colour));
      });
    }
    result.endStep();
    // An import is not an edit: what it produced is the document's starting
    // point, and there is nothing before it to go back to.
    result.clearJournal();
  }

  return (
    result,
    ImportReport(
      sourceVertices: sourceVertices,
      weldedVertices: unique.length,
      faces: triangles.length,
      flippedFaces: flipped,
      splitNonManifold: split,
      droppedDegenerate: dropped,
      weldEpsilon: epsilon,
    ),
  );
}

/// Makes neighbours agree about which way round they are wound, and returns how
/// many faces were turned.
///
/// **A walk rather than a rule, because there is no rule.** Which way round a
/// single triangle should be is not a local question — a lone triangle is
/// neither inside out nor the right way round — so the answer is consistency:
/// pick a face, and every face reached across a shared edge must use that edge
/// in the *opposite* direction. Using it the same way round means it is
/// mirrored, and it is flipped.
///
/// One walk per connected component, since two islands say nothing about each
/// other. Whether a component as a whole is inside out is a separate question —
/// `mesh-27`'s signed volume answers it, and this does not, because a surface
/// with a boundary has no inside to be out of.
int _repairOrientation(List<List<int>> triangles, List<List<int>> corners) {
  // Undirected edge to the faces on it. A key that does not depend on direction,
  // so the two faces of an edge land in the same bucket however they are wound.
  final onEdge = <int, List<int>>{};
  int undirected(int a, int b) =>
      a < b ? a * 0x100000000 + b : b * 0x100000000 + a;

  for (var face = 0; face < triangles.length; face++) {
    final loop = triangles[face];
    for (var corner = 0; corner < 3; corner++) {
      onEdge
          .putIfAbsent(
            undirected(loop[corner], loop[(corner + 1) % 3]),
            () => <int>[],
          )
          .add(face);
    }
  }

  var flipped = 0;
  final seen = List<bool>.filled(triangles.length, false);
  final queue = <int>[];

  void flip(int face) {
    final loop = triangles[face];
    final swap = loop[1];
    loop[1] = loop[2];
    loop[2] = swap;
    final source = corners[face];
    final swapSource = source[1];
    source[1] = source[2];
    source[2] = swapSource;
    flipped++;
  }

  /// Whether [face] uses the edge from [a] to [b] in that direction.
  bool usesForwards(int face, int a, int b) {
    final loop = triangles[face];
    for (var corner = 0; corner < 3; corner++) {
      if (loop[corner] == a && loop[(corner + 1) % 3] == b) return true;
    }
    return false;
  }

  for (var start = 0; start < triangles.length; start++) {
    if (seen[start]) continue;
    seen[start] = true;
    queue
      ..clear()
      ..add(start);

    while (queue.isNotEmpty) {
      final face = queue.removeLast();
      final loop = triangles[face];
      for (var corner = 0; corner < 3; corner++) {
        final a = loop[corner];
        final b = loop[(corner + 1) % 3];
        for (final other in onEdge[undirected(a, b)] ?? const <int>[]) {
          if (other == face || seen[other]) continue;
          // The neighbour must use this edge the other way round. If it uses it
          // the same way, it is mirrored relative to the face it was reached
          // from, and turning it round is the whole repair.
          if (usesForwards(other, a, b)) flip(other);
          seen[other] = true;
          queue.add(other);
        }
      }
    }
  }
  return flipped;
}
