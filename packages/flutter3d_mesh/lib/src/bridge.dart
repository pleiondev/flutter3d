/// Joining two open borders with a ring of quads — `ux-39`.
///
/// **What it is for: two pieces that should be one.** A tube cut in half, a
/// sleeve and a body, a hole in one surface and a hole in another. Without
/// it the only way to close the gap is to add faces one at a time and get
/// the winding right by hand, which is the part nobody gets right by hand.
///
/// **Only open borders.** An edge with a face on both sides has nothing to
/// join to — bridging it would mean deciding which of the two faces to cut
/// away first, which is a different operation and a destructive one. So this
/// refuses rather than guessing, and the refusal says what to select
/// instead.
///
/// **The pairing is by distance, not by index.** Two borders come out of a
/// selection in whatever order their half-edges happened to be numbered, and
/// joining `a[0]` to `b[0]` would twist the ring by however far apart those
/// two corners are. Every rotation of one border against the other is
/// measured and the closest wins, which is the answer a person means when
/// they select two rims and ask for the obvious join.
library;

import 'dart:typed_data';

import 'package:vector_math/vector_math.dart';

import 'attributes.dart';
import 'edit_mesh.dart';
import 'operations.dart';
import 'selection.dart';

/// Joins the two open borders [selection] names with a ring of quads.
OpResult bridgeLoops(EditMesh mesh, Selection selection) {
  final edges = selection.convertedTo(mesh, ElementLevel.edge);
  if (edges.isEmpty) {
    return OpResult.refused(
      'no edges are selected to bridge',
      selection: selection,
    );
  }

  // An edge id *is* one of its half-edges — the smaller of the pair, or the
  // only one when the edge is a border. So a border edge's id is already the
  // half-edge a new face has to weld to.
  final byOrigin = <int, int>{};
  for (final int edge in edges.ids) {
    if (mesh.hasLiveTwin(edge)) {
      return OpResult.refused(
        'a selected edge has a face on both sides; bridge joins two open '
        'borders',
        selection: selection,
      );
    }
    final int from = mesh.originOf(edge);
    if (byOrigin.containsKey(from)) {
      return OpResult.refused(
        'the selected edges branch rather than forming two borders',
        selection: selection,
      );
    }
    byOrigin[from] = edge;
  }

  final List<List<int>>? loops = _loopsIn(mesh, byOrigin);
  if (loops == null) {
    return OpResult.refused(
      'the selected edges do not close into borders',
      selection: selection,
    );
  }
  if (loops.length != 2) {
    return OpResult.refused(
      'bridge joins exactly two borders, and ${loops.length} '
      '${loops.length == 1 ? 'was' : 'were'} selected',
      selection: selection,
    );
  }
  final List<int> a = loops[0];
  final List<int> b = loops[1];
  if (a.length != b.length) {
    return OpResult.refused(
      'the two borders have ${a.length} and ${b.length} edges; bridge needs '
      'the same number on each',
      selection: selection,
    );
  }

  final int n = a.length;
  if (n < 3) {
    // Two-edge and one-edge borders are the degenerate shapes a delete can
    // leave behind; a ring of quads round one would be a face with two of
    // its own edges welded to each other.
    return OpResult.refused(
      'a border of $n ${n == 1 ? 'edge' : 'edges'} is too small to bridge',
      selection: selection,
    );
  }
  final List<int> ringA = <int>[for (final int half in a) mesh.originOf(half)];
  final List<int> ringB = <int>[for (final int half in b) mesh.originOf(half)];
  // **Two borders that share a corner cannot be bridged into a surface a
  // person can go on editing.** Every quad this makes adds an edge between
  // a corner of one border and a corner of the other; where that edge
  // already exists — because the two borders meet, or because they are two
  // sides of the same strip — the result is two edges between one pair of
  // vertices, which is not a manifold and which `dissolveVertex` has no
  // sensible answer for afterwards. Found here, before anything is written.
  final Set<int> onA = ringA.toSet();
  for (final int vertex in ringB) {
    if (onA.contains(vertex)) {
      return OpResult.refused(
        'the two borders meet at a corner; bridge joins borders that are '
        'apart',
        selection: selection,
      );
    }
  }

  final (int shift, double apart) = _closestShift(mesh, ringA, ringB);
  if (apart <= 1e-9 * n) {
    // **Two borders in the same place make a ring of quads with no area.**
    // A duplicated face left where it was and then bridged is the way to
    // reach this by accident, and the mesh it leaves has edges no exporter,
    // no normal and no dissolve can make sense of. Moving one of them first
    // is what the person meant.
    return OpResult.refused(
      'the two borders are in the same place; move one of them before '
      'bridging',
      selection: selection,
    );
  }
  for (var i = 0; i < n; i++) {
    final int k = (shift - i) % n;
    if (mesh.neighborsOf(ringA[i]).contains(ringB[(k + 1) % n])) {
      return OpResult.refused(
        'a corner of one border is already joined to a corner of the other',
        selection: selection,
      );
    }
  }

  final firsts = <int>[];
  final made = <int>[];
  final moved = <int>{};
  for (var i = 0; i < n; i++) {
    final int k = (shift - i) % n;
    final int kNext = (k + 1) % n;
    final int first = mesh.halfEdgeSlotCount;
    final int quad = mesh.addFace(<int>[
      ringA[(i + 1) % n],
      ringA[i],
      ringB[kNext],
      ringB[k],
    ]);
    firsts.add(first);
    made.add(quad);
    mesh
      ..weldTwins(first, a[i])
      ..weldTwins(first + 2, b[k]);
    _inheritBridge(mesh, quad, first, mesh.faceOf(a[i]));
    moved
      ..add(ringA[i])
      ..add(ringB[k]);
  }
  for (var i = 0; i < n; i++) {
    mesh.weldTwins(firsts[i] + 3, firsts[(i + 1) % n] + 1);
  }

  return OpResult.done(
    selection: Selection.of(ElementLevel.face, made),
    movedVertices: Int32List.fromList(moved.toList()..sort()),
    topologyChanged: true,
  );
}

/// The selected half-edges split into closed loops, or null when one of them
/// runs off the end instead of coming back to where it started.
List<List<int>>? _loopsIn(EditMesh mesh, Map<int, int> byOrigin) {
  final loops = <List<int>>[];
  final seen = <int>{};
  for (final int start in byOrigin.values) {
    if (seen.contains(start)) continue;
    final loop = <int>[];
    var half = start;
    while (seen.add(half)) {
      loop.add(half);
      final int? next = byOrigin[mesh.originOf(mesh.nextOf(half))];
      if (next == null) return null;
      half = next;
    }
    // A loop that came back to anything other than its own start is two
    // borders that share a vertex, which `byOrigin` has already refused —
    // this is the belt to that braces.
    if (half != start) return null;
    loops.add(loop);
  }
  return loops;
}

/// Which rotation of [b] against [a] puts the pairs closest together.
///
/// Every rotation is measured because a border has no natural first corner:
/// the one a selection happens to start at is an accident of half-edge
/// numbering, and joining two rims at that accident twists the ring.
(int, double) _closestShift(EditMesh mesh, List<int> a, List<int> b) {
  final int n = a.length;
  final here = Vector3.zero();
  final there = Vector3.zero();
  var best = 0;
  var bestCost = double.infinity;
  for (var shift = 0; shift < n; shift++) {
    var cost = 0.0;
    for (var i = 0; i < n; i++) {
      mesh.positionOf(a[i], here);
      mesh.positionOf(b[(shift - i + 1) % n], there);
      cost += here.distanceTo(there);
      if (cost >= bestCost) break;
    }
    if (cost < bestCost) {
      bestCost = cost;
      best = shift;
    }
  }
  return (best, bestCost);
}

/// A bridging quad takes the material and the shading of the border it grew
/// from, and a unit square of texture of its own — the same choice
/// `insetFaces` and `extrudeFaces` make for their walls, for the same
/// reason: the surface did not exist, so it has no place in a texture.
void _inheritBridge(EditMesh mesh, int quad, int first, int source) {
  if (source != EditMesh.none &&
      mesh.hasLayer(MeshDomain.face, MeshAttribute.materialSlot)) {
    mesh.setMaterialSlot(quad, mesh.materialSlotOf(source));
  }
  if (source != EditMesh.none &&
      mesh.hasLayer(MeshDomain.face, MeshAttribute.flags)) {
    mesh.setFaceFlag(
      quad,
      FaceFlags.smooth,
      on: mesh.faceHas(source, FaceFlags.smooth),
    );
  }
  if (mesh.hasLayer(MeshDomain.corner, MeshAttribute.uv0)) {
    mesh
      ..setUv(first, Vector2(0, 0))
      ..setUv(first + 1, Vector2(1, 0))
      ..setUv(first + 2, Vector2(1, 1))
      ..setUv(first + 3, Vector2(0, 1));
  }
}
