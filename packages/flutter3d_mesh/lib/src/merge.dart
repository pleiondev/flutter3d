/// Welding vertices together, and what that does to the faces around them.
///
/// **A merge rebuilds, and dissolving does not.** [EditMesh.dissolveEdge] and
/// [EditMesh.dissolveVertex] rewire a few links and are one step of history
/// each; a weld cannot be. Bringing two vertices together turns some faces into
/// polygons with a corner fewer, some into things that are not polygons at all,
/// and some edges into edges with three faces on them — and re-pairing the
/// twins through all of that is exactly the job `EditMeshBuilder` already does
/// once, correctly. So a merge produces a new mesh with new numbers and an
/// [IdRemap] saying where everything went, the way `EditMesh.compact` does, and
/// like it the result has no history: `doc-08` is where what that means for
/// undo is decided.
///
/// **Three things happen to faces, and each is counted.**
///
///   * A face whose corners collapse onto each other loses them. A triangle
///     with two of its corners welded is not a thin triangle; it is two points,
///     and it goes.
///   * Two faces standing on the same points, wound against each other, are the
///     wall between two solids that have just become one. Both go — keeping
///     them leaves a partition inside a box that nothing can see and every
///     volume, every raycast and every exporter has to deal with.
///   * An edge that ends up with a third face on it is split, the way an import
///     splits one, because a half-edge has one twin.
///
/// Nothing here is silent. What a merge decided is in the [MergeReport], and a
/// caller shows it.
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:vector_math/vector_math.dart';

import 'attributes.dart';
import 'edit_mesh.dart';
import 'selection.dart';

/// What a merge had to decide, and how often.
final class MergeReport {
  const MergeReport({
    required this.sourceVertices,
    required this.vertices,
    required this.droppedDegenerate,
    required this.droppedCoincident,
    required this.splitNonManifold,
    required this.distance,
    required this.remap,
  });

  /// Vertices the mesh had before.
  final int sourceVertices;

  /// Vertices it has now.
  final int vertices;

  /// Faces that stopped being polygons when their corners came together.
  final int droppedDegenerate;

  /// Faces thrown away for standing on the same points as another.
  ///
  /// Two at a time, because a wall has two sides: what this counts is the faces
  /// removed, so gluing two boxes face to face reports two.
  final int droppedCoincident;

  /// Edges that came out with a third face on them, each costing a pair of
  /// duplicated vertices.
  final int splitNonManifold;

  /// The distance under which two vertices were taken for one, or zero for a
  /// merge that was told which vertices to weld rather than asked to find them.
  final double distance;

  /// Where every old vertex and face went, or [EditMesh.none] where it did not.
  final IdRemap remap;

  /// How many vertices disappeared.
  int get merged => sourceVertices - vertices;

  /// Whether anything happened that a person should be told about.
  bool get worthReporting =>
      droppedDegenerate > 0 || droppedCoincident > 0 || splitNonManifold > 0;

  @override
  String toString() =>
      'MergeReport($merged of $sourceVertices vertices merged, '
      '$droppedDegenerate degenerate and $droppedCoincident coincident faces '
      'dropped, $splitNonManifold edges split)';
}

/// Welds every pair of vertices closer together than [distance].
///
/// [distance] defaults to a millionth of the mesh's own diagonal — under what a
/// float carries at that size and over the drift an editing session leaves
/// behind. With [within] given, only the vertices it names are candidates, so a
/// person can close a seam without collapsing the rest of the model.
///
/// A welded group lands on its own centre. Taking the first vertex's position
/// instead would make the answer depend on which one the arrays happened to
/// hold first, which is not a thing a person can predict or a test can pin.
(EditMesh, MergeReport) mergeByDistance(
  EditMesh mesh, {
  double? distance,
  Selection? within,
}) {
  final live = <int>[
    for (var vertex = 0; vertex < mesh.vertexSlotCount; vertex++)
      if (mesh.isVertexAlive(vertex)) vertex,
  ];
  final eligible = within?.convertedTo(mesh, ElementLevel.vertex);

  final epsilon = distance ?? _defaultDistance(mesh, live);
  final groupOf = Int32List(mesh.vertexSlotCount)
    ..fillRange(0, mesh.vertexSlotCount, EditMesh.none);
  final members = <List<int>>[];

  // A grid of cells one epsilon across, so two vertices within epsilon are
  // either in the same cell or in one of the twenty-six around it. Quantising
  // and looking in one cell is what puts two points either side of a boundary
  // in different groups, and it is why a seam sometimes closes and sometimes
  // does not.
  final cells = <int, List<int>>{};
  final scale = epsilon > 0 ? 1 / epsilon : 0.0;
  final at = Vector3.zero();
  final candidate = Vector3.zero();

  for (final vertex in live) {
    mesh.positionOf(vertex, at);
    if (eligible != null && !eligible.contains(vertex)) {
      groupOf[vertex] = members.length;
      members.add(<int>[vertex]);
      continue;
    }

    final cx = epsilon > 0 ? (at.x * scale).floor() : 0;
    final cy = epsilon > 0 ? (at.y * scale).floor() : 0;
    final cz = epsilon > 0 ? (at.z * scale).floor() : 0;

    var found = EditMesh.none;
    search:
    for (var dx = -1; dx <= 1; dx++) {
      for (var dy = -1; dy <= 1; dy++) {
        for (var dz = -1; dz <= 1; dz++) {
          final bucket = cells[_cellKey(cx + dx, cy + dy, cz + dz)];
          if (bucket == null) continue;
          for (final group in bucket) {
            mesh.positionOf(members[group].first, candidate);
            if ((candidate.x - at.x).abs() <= epsilon &&
                (candidate.y - at.y).abs() <= epsilon &&
                (candidate.z - at.z).abs() <= epsilon) {
              found = group;
              break search;
            }
          }
        }
      }
    }

    if (found == EditMesh.none) {
      found = members.length;
      members.add(<int>[]);
      cells.putIfAbsent(_cellKey(cx, cy, cz), () => <int>[]).add(found);
    }
    members[found].add(vertex);
    groupOf[vertex] = found;
  }

  return _rebuild(mesh, groupOf, members, _centres(mesh, members), epsilon);
}

/// Welds the vertices [selection] names into one, standing at [at].
///
/// The other half of a merge: [mergeByDistance] finds what to weld, and this is
/// told. Merging at a point a person chose — the cursor, the middle, the vertex
/// they clicked last — is the same operation with the search left out.
(EditMesh, MergeReport) mergeAt(
  EditMesh mesh,
  Selection selection,
  Vector3 at,
) {
  final chosen = selection.convertedTo(mesh, ElementLevel.vertex);
  final groupOf = Int32List(mesh.vertexSlotCount)
    ..fillRange(0, mesh.vertexSlotCount, EditMesh.none);
  final members = <List<int>>[];
  final positions = <Vector3>[];

  var welded = EditMesh.none;
  for (var vertex = 0; vertex < mesh.vertexSlotCount; vertex++) {
    if (!mesh.isVertexAlive(vertex)) continue;
    if (chosen.contains(vertex)) {
      if (welded == EditMesh.none) {
        welded = members.length;
        members.add(<int>[]);
        positions.add(Vector3.copy(at));
      }
      members[welded].add(vertex);
      groupOf[vertex] = welded;
      continue;
    }
    groupOf[vertex] = members.length;
    members.add(<int>[vertex]);
    positions.add(mesh.positionOf(vertex));
  }

  return _rebuild(mesh, groupOf, members, positions, 0);
}

int _cellKey(int x, int y, int z) =>
    // Three coordinates into one int, which Dart holds at 64 bits everywhere
    // this runs except the web — where doubles are exact to 2^53 and these fit
    // inside it for any model with a sane bounding box.
    (x & 0x1FFFFF) | ((y & 0x1FFFFF) << 21) | ((z & 0x1FFFFF) << 42);

double _defaultDistance(EditMesh mesh, List<int> live) {
  if (live.isEmpty) return 1e-9;
  final low = mesh.positionOf(live.first);
  final high = Vector3.copy(low);
  final at = Vector3.zero();
  for (final vertex in live) {
    mesh.positionOf(vertex, at);
    Vector3.min(low, at, low);
    Vector3.max(high, at, high);
  }
  return math.max((high - low).length * 1e-6, 1e-9);
}

List<Vector3> _centres(EditMesh mesh, List<List<int>> members) {
  final at = Vector3.zero();
  final centres = <Vector3>[];
  for (final group in members) {
    final centre = Vector3.zero();
    for (final vertex in group) {
      centre.add(mesh.positionOf(vertex, at));
    }
    centres.add(centre..scale(1 / group.length));
  }
  return centres;
}

/// Builds the mesh the grouping describes, and reports what it cost.
(EditMesh, MergeReport) _rebuild(
  EditMesh mesh,
  Int32List groupOf,
  List<List<int>> members,
  List<Vector3> positions,
  double distance,
) {
  final builder = EditMeshBuilder();
  final points = <Vector3>[];
  for (final point in positions) {
    builder.addVertex(point);
    points.add(point);
  }
  // Which old vertex each new one takes its skin from. A duplicate made by a
  // non-manifold split points at the same one as the vertex it copied.
  final origins = <int>[for (final group in members) group.first];

  // ------------------------------------------------------------------ faces

  final loops = <List<int>>[];
  final corners = <List<int>>[];
  final sourceFaces = <int>[];
  var droppedDegenerate = 0;

  for (var face = 0; face < mesh.faceSlotCount; face++) {
    if (!mesh.isFaceAlive(face)) continue;
    final loop = <int>[];
    final source = <int>[];
    mesh.forEachHalfEdge(face, (int half) {
      final vertex = groupOf[mesh.originOf(half)];
      // Two corners of one face welded together leave one corner, not an edge
      // of no length.
      if (loop.isNotEmpty && loop.last == vertex) return;
      loop.add(vertex);
      source.add(half);
    });
    while (loop.length > 1 && loop.first == loop.last) {
      loop.removeLast();
      source.removeLast();
    }
    // A vertex the loop names twice without the two being neighbours pinches
    // the face into a figure of eight, which is not a polygon either.
    if (loop.length < 3 || loop.toSet().length != loop.length) {
      droppedDegenerate++;
      continue;
    }
    loops.add(loop);
    corners.add(source);
    sourceFaces.add(face);
  }

  final keep = _dropCoincident(loops);
  final droppedCoincident = loops.length - keep.length;

  // -------------------------------------------------------- non-manifold split

  // Directed edges already taken. Two faces sharing an edge use it in opposite
  // directions, so a second face using `a -> b` the same way round is the third
  // face on that edge.
  final taken = <int>{};
  var split = 0;
  final faceMap = Int32List(mesh.faceSlotCount)
    ..fillRange(0, mesh.faceSlotCount, EditMesh.none);
  final builtCorners = <List<int>>[];
  final builtSources = <int>[];

  for (final index in keep) {
    final loop = List<int>.of(loops[index]);
    for (var attempt = 0; attempt <= loop.length; attempt++) {
      var conflict = -1;
      for (var corner = 0; corner < loop.length; corner++) {
        final from = loop[corner];
        final to = loop[(corner + 1) % loop.length];
        if (taken.contains(_edgeKey(from, to))) {
          conflict = corner;
          break;
        }
      }
      if (conflict < 0) break;

      // The extra face gets its own copies of the two vertices the contested
      // edge runs between, which detaches it there and leaves the first two
      // joined.
      split++;
      final to = (conflict + 1) % loop.length;
      for (final corner in <int>[conflict, to]) {
        final was = loop[corner];
        final copy = builder.addVertex(points[was]);
        points.add(points[was]);
        origins.add(origins[was]);
        loop[corner] = copy;
      }
    }

    for (var corner = 0; corner < loop.length; corner++) {
      taken.add(_edgeKey(loop[corner], loop[(corner + 1) % loop.length]));
    }
    faceMap[sourceFaces[index]] = builder.faceCount;
    builder.addFace(loop);
    builtCorners.add(corners[index]);
    builtSources.add(sourceFaces[index]);
  }

  final result = builder.build();

  // ------------------------------------------------------------- attributes

  _carryAttributes(mesh, result, builtCorners, builtSources, origins);
  // A merge is a rebuild, and the mesh it produced has no state before it —
  // the same rule `EditMesh.compact` follows, and for the same reason: a
  // journal is indices into arrays that have just been renumbered.
  result.clearJournal();

  final vertexMap = Int32List(mesh.vertexSlotCount)
    ..fillRange(0, mesh.vertexSlotCount, EditMesh.none);
  for (var vertex = 0; vertex < mesh.vertexSlotCount; vertex++) {
    if (mesh.isVertexAlive(vertex)) vertexMap[vertex] = groupOf[vertex];
  }

  return (
    result,
    MergeReport(
      sourceVertices: mesh.vertexCount,
      vertices: result.vertexCount,
      droppedDegenerate: droppedDegenerate,
      droppedCoincident: droppedCoincident,
      splitNonManifold: split,
      distance: distance,
      remap: IdRemap(vertices: vertexMap, faces: faceMap),
    ),
  );
}

int _edgeKey(int from, int to) => from * 0x100000000 + to;

/// Which faces survive once the pairs standing on the same points are gone.
///
/// **A pair wound against each other is a wall, and a pair wound the same way
/// is an exporter's mistake.** The first is the partition between two solids
/// that have just been welded into one, and both sides of it go. The second is
/// the same face written twice, and one of them stays — throwing away both
/// would put a hole in the surface.
List<int> _dropCoincident(List<List<int>> loops) {
  final byPoints = <String, List<int>>{};
  for (var index = 0; index < loops.length; index++) {
    final sorted = List<int>.of(loops[index])..sort();
    byPoints.putIfAbsent(sorted.join(','), () => <int>[]).add(index);
  }

  final keep = <int>[];
  for (final bucket in byPoints.values) {
    if (bucket.length == 1) {
      keep.add(bucket.first);
      continue;
    }
    // One entry per winding: the same face written twice collapses to one.
    final byWinding = <String, int>{};
    for (final index in bucket) {
      byWinding.putIfAbsent(_windingKey(loops[index]), () => index);
    }
    if (byWinding.length == 2) {
      final both = byWinding.values.toList(growable: false);
      final one = loops[both.first];
      final other = loops[both.last];
      if (_windingKey(one.reversed.toList(growable: false)) ==
          _windingKey(other)) {
        continue; // a wall, seen from both sides
      }
    }
    keep.addAll(byWinding.values);
  }
  return keep..sort();
}

/// The loop written from its smallest vertex, so two faces wound the same way
/// read the same however they were entered.
String _windingKey(List<int> loop) {
  var start = 0;
  for (var i = 1; i < loop.length; i++) {
    if (loop[i] < loop[start]) start = i;
  }
  return <int>[
    for (var i = 0; i < loop.length; i++) loop[(start + i) % loop.length],
  ].join(',');
}

/// Copies every layer the old mesh had onto the new one.
void _carryAttributes(
  EditMesh mesh,
  EditMesh result,
  List<List<int>> corners,
  List<int> sourceFaces,
  List<int> origins,
) {
  final hasUv = mesh.hasLayer(MeshDomain.corner, MeshAttribute.uv0);
  final hasColour = mesh.hasLayer(MeshDomain.corner, MeshAttribute.colour);
  final hasCrease = mesh.hasLayer(MeshDomain.edge, MeshAttribute.crease);
  final hasEdgeFlags = mesh.hasLayer(MeshDomain.edge, MeshAttribute.flags);
  final hasFaceFlags = mesh.hasLayer(MeshDomain.face, MeshAttribute.flags);
  final hasSlots = mesh.hasLayer(MeshDomain.face, MeshAttribute.materialSlot);
  final hasSkin =
      mesh.hasLayer(MeshDomain.vertex, MeshAttribute.weights) ||
      mesh.hasLayer(MeshDomain.vertex, MeshAttribute.joints);
  if (!hasUv &&
      !hasColour &&
      !hasCrease &&
      !hasEdgeFlags &&
      !hasFaceFlags &&
      !hasSlots &&
      !hasSkin) {
    return;
  }

  result.beginStep();
  for (var face = 0; face < sourceFaces.length; face++) {
    final was = sourceFaces[face];
    if (hasFaceFlags) {
      result.setFaceFlag(
        face,
        FaceFlags.smooth,
        on: mesh.faceHas(was, FaceFlags.smooth),
      );
    }
    if (hasSlots) result.setMaterialSlot(face, mesh.materialSlotOf(was));

    var corner = 0;
    result.forEachHalfEdge(face, (int half) {
      final source = corners[face][corner++];
      if (hasUv || hasColour) {
        result.setCorner(half, mesh.cornerOf(source));
      }
      if (hasCrease) result.setCrease(half, mesh.creaseOf(source));
      if (hasEdgeFlags) {
        for (final flag in <int>[EdgeFlags.sharp, EdgeFlags.seam]) {
          result.setEdgeFlag(half, flag, on: mesh.edgeHas(source, flag));
        }
      }
    });
  }
  if (hasSkin) {
    for (var vertex = 0; vertex < result.vertexSlotCount; vertex++) {
      result.setSkin(vertex, mesh.skinOf(origins[vertex]));
    }
  }
  result.endStep();
}
