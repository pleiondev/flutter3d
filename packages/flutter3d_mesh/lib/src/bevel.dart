/// Cutting a corner off every selected edge or vertex, walling the gap with a
/// new face per edge and a new n-gon per vertex.
///
/// **Every touched face insets by the same mitred amount [insetFaces] uses,
/// independently of its neighbours — the gap between two faces that both
/// moved is bridged rather than one side staying put.** A single face with
/// every one of its own edges beveled shrinks exactly the way
/// [insetCornerPositions] already describes; the only new work bevel does is
/// what happens at the seam between two such faces (a new quad, one per
/// beveled edge, connecting each side's own shrunk corner) and at a vertex
/// where several beveled edges meet (a new n-gon, one per vertex, connecting
/// every incident face's own shrunk corner there) — `mesh-44`'s own
/// "угловые n-гоны" (corner n-gons).
///
/// **Scope: a selection has to be a closed region.** Every face touching a
/// beveled edge must have all of its own edges beveled too, and every face
/// around a beveled vertex must be one of those fully-beveled faces. A
/// selection that stops partway across a face, or partway around a vertex's
/// own fan of faces, is refused rather than built wrong — the shape a
/// partial bevel needs at the boundary between beveled and untouched
/// geometry is a real, different construction (an edge that only moves on
/// one side) that nothing here builds yet. Beveling every edge of a closed
/// mesh, or every edge of a face group cut cleanly out of a larger one, both
/// satisfy this; beveling one edge in the middle of an otherwise untouched
/// grid does not.
///
/// **Not built: `segments` above `1` and the `profile` that would shape
/// them.** A single flat chamfer is `mesh-44`'s own acceptance number; a
/// rounded, multi-segment bevel needs an arc computed at every beveled
/// vertex and is refused rather than silently flattened. `profile` is left
/// out of the signature entirely rather than accepted and ignored — there is
/// nothing for it to shape until segments above one exist.
library;

import 'dart:typed_data';

import 'package:vector_math/vector_math.dart';

import 'attributes.dart';
import 'edit_mesh.dart';
import 'inset.dart';
import 'operations.dart';
import 'selection.dart';

/// Bevels every edge [selection] converts to, by [width].
///
/// [clampOverlap] scales [width] down when the shortest beveled edge is not
/// long enough to hold it — see the library doc comment for [segments] and
/// the closed-region requirement both share with [bevelVertices].
OpResult bevelEdges(
  EditMesh mesh,
  Selection selection, {
  required double width,
  int segments = 1,
  bool clampOverlap = true,
}) {
  final edges = selection.convertedTo(mesh, ElementLevel.edge);
  if (edges.isEmpty) {
    return OpResult.refused(
      'no edges are selected to bevel',
      selection: selection,
    );
  }
  return _bevel(
    mesh,
    edges.ids.toSet(),
    selection,
    width: width,
    segments: segments,
    clampOverlap: clampOverlap,
  );
}

/// Bevels every edge touching a vertex [selection] converts to, by [width].
///
/// **Not the same conversion [Selection.convertedTo] itself would give.**
/// Going from a vertex selection up to edges keeps only an edge whose *both*
/// endpoints are selected — right for "the region this vertex selection
/// spans," wrong for "every edge this vertex touches," which is what a
/// vertex bevel means. So this walks each selected vertex's own edges
/// directly rather than converting the selection.
OpResult bevelVertices(
  EditMesh mesh,
  Selection selection, {
  required double width,
  int segments = 1,
  bool clampOverlap = true,
}) {
  final vertices = selection.convertedTo(mesh, ElementLevel.vertex);
  if (vertices.isEmpty) {
    return OpResult.refused(
      'no vertices are selected to bevel',
      selection: selection,
    );
  }
  final edgeIds = <int>{};
  for (final v in vertices.ids) {
    final start = mesh.outgoingOf(v);
    if (start == EditMesh.none) continue;
    var he = start;
    while (true) {
      edgeIds.add(mesh.edgeOf(he));
      if (!mesh.hasLiveTwin(he)) break;
      he = mesh.nextOf(mesh.twinOf(he));
      if (he == start) break;
    }
  }
  return _bevel(
    mesh,
    edgeIds,
    selection,
    width: width,
    segments: segments,
    clampOverlap: clampOverlap,
  );
}

OpResult _bevel(
  EditMesh mesh,
  Set<int> beveledEdges,
  Selection originalSelection, {
  required double width,
  required int segments,
  required bool clampOverlap,
}) {
  if (segments != 1) {
    return OpResult.refused(
      'bevelEdges/bevelVertices only supports segments: 1 today — a '
      'rounded, multi-segment bevel is not built yet',
      selection: originalSelection,
    );
  }

  // Every face with at least one of its own edges beveled.
  final touchedFaces = <int>{};
  for (final e in beveledEdges) {
    if (!mesh.isFaceAlive(mesh.faceOf(e))) continue;
    touchedFaces.add(mesh.faceOf(e));
    if (mesh.hasLiveTwin(e)) touchedFaces.add(mesh.faceOf(mesh.twinOf(e)));
  }

  // Closed-region check: every touched face must have every one of its own
  // edges beveled.
  for (final f in touchedFaces) {
    var whole = true;
    mesh.forEachHalfEdge(f, (int he) {
      if (!beveledEdges.contains(mesh.edgeOf(he))) whole = false;
    });
    if (!whole) {
      return OpResult.refused(
        'bevel needs every edge of a touched face selected — a bevel that '
        'stops partway across a face is not built yet',
        selection: originalSelection,
      );
    }
  }

  final touchedVertices = <int>{};
  for (final e in beveledEdges) {
    touchedVertices.add(mesh.originOf(e));
    touchedVertices.add(mesh.originOf(mesh.nextOf(e)));
  }

  // Closed-region check at each vertex: every face around it has to be one
  // of the already-fully-beveled ones, and the fan may not run off a
  // boundary.
  for (final v in touchedVertices) {
    final start = mesh.outgoingOf(v);
    if (start == EditMesh.none) {
      return OpResult.refused(
        'a selected vertex has nothing around it to bevel',
        selection: originalSelection,
      );
    }
    var he = start;
    while (true) {
      if (!touchedFaces.contains(mesh.faceOf(he))) {
        return OpResult.refused(
          'bevel needs every face around a beveled vertex fully selected — '
          'a bevel that stops partway around a vertex is not built yet',
          selection: originalSelection,
        );
      }
      if (!mesh.hasLiveTwin(he)) {
        return OpResult.refused(
          'a boundary vertex cannot be beveled yet',
          selection: originalSelection,
        );
      }
      he = mesh.nextOf(mesh.twinOf(he));
      if (he == start) break;
    }
  }

  // Snapshotted before anything moves: `originOf` is about to stop meaning
  // "the original vertex" for every beveled edge's own half-edge, once the
  // face it belongs to gets its corners remapped in the pass below.
  final endpointsOf = <int, (int, int)>{
    for (final e in beveledEdges)
      e: (mesh.originOf(e), mesh.originOf(mesh.nextOf(e))),
  };

  var effectiveWidth = width;
  if (clampOverlap) {
    var shortest = double.infinity;
    for (final e in beveledEdges) {
      final (from, to) = endpointsOf[e]!;
      final length = (mesh.positionOf(to) - mesh.positionOf(from)).length;
      if (length < shortest) shortest = length;
    }
    // Leaves a hair's width of the original edge rather than letting two
    // bevels meet exactly, which is a degenerate (zero-length) edge the rest
    // of this still has to build a valid face over.
    final cap = shortest / 2 * 0.999;
    if (effectiveWidth > cap) effectiveWidth = cap;
  }

  // Pass 1: every touched face insets its own corners by `effectiveWidth`,
  // independently — the same mitred position [insetCornerPositions] gives
  // [insetFaces], just never walled back to this face's own original
  // boundary the way an ordinary inset is.
  final newRing = <(int, int), int>{}; // (face, original vertex) -> new id
  final movedVertices = <int>[];
  for (final f in touchedFaces) {
    final boundary = <int>[];
    mesh.forEachHalfEdge(f, boundary.add);
    final n = boundary.length;
    final originalVertices = <int>[
      for (final he in boundary) mesh.originOf(he),
    ];
    final positions = <Vector3>[
      for (final v in originalVertices) mesh.positionOf(v),
    ];
    final normal = mesh.normalOf(f);
    final ring = insetCornerPositions(positions, normal, effectiveWidth, 0.0);
    for (var i = 0; i < n; i++) {
      final id = mesh.addVertex(ring[i]);
      mesh.setOrigin(boundary[i], id);
      newRing[(f, originalVertices[i])] = id;
      movedVertices.add(id);
    }
  }

  // Pass 2: one n-gon's own vertex loop per beveled vertex, connecting every
  // incident face's own new corner there. Walked in the same rotational
  // order every half-edge walk in this package uses — `nextOf(twinOf(he))`
  // from an outgoing half-edge, the technique `smooth.dart`'s own
  // `_neighborsOf` states in full — **and then reversed**: that rotation
  // visits a vertex's own faces in the opposite sense to the one a cap
  // needs, since it is built to answer "who is my neighbour," not "what
  // winding does a new face here need to be wound outward." Reversed, each
  // of a cap's own edges runs opposite to the matching bridge's own edge at
  // that same vertex — the pairing the auto-weld below depends on, and
  // (found the same way) the direction that keeps the cap's own normal
  // pointing out of the solid rather than into it.
  //
  // **Walked now, before pass 3 below rewelds any twin**: the rotation
  // reads `twinOf` at every step, and once a beveled edge's own twin
  // becomes a bridge quad's half-edge instead of the neighbouring face's,
  // the same walk would cross into the wrong geometry. The loop itself is
  // only built here; the face it becomes is added after pass 3, once every
  // original twin this walk still depends on has been read for every
  // touched vertex.
  final capLoops = <int, List<int>>{};
  for (final v in touchedVertices) {
    final start = mesh.outgoingOf(v);
    final loop = <int>[];
    var he = start;
    while (true) {
      loop.add(newRing[(mesh.faceOf(he), v)]!);
      he = mesh.nextOf(mesh.twinOf(he));
      if (he == start) break;
    }
    capLoops[v] = loop.reversed.toList();
  }

  // Pass 3: one bridge quad per beveled edge, connecting the two touched
  // faces' own new corners at each of the edge's endpoints.
  //
  // **Wound `[f1From, f2From, f2To, f1To]`, not `f1`'s own two corners
  // adjacent** — a twin runs the *opposite* direction from the half-edge it
  // pairs with, not the same one, so the quad edge that welds to `e` (which
  // now runs `f1From → f1To`, the same direction `e` always ran its own
  // face's loop in) has to run `f1To → f1From` instead: that is this loop's
  // own closing edge, index 3. Index 1 (`f2From → f2To`) is the same answer
  // for `twin`, which after its own face's remap runs `f2To → f2From`. The
  // other two — 0 and 2, the ones that run *along* the new corner at each
  // endpoint rather than along the original edge — are left for the vertex
  // caps below to weld, since which cap sits on their other side is not
  // decided until that pass runs.
  final pendingHalfEdges = <int>[];
  final createdFaces = <int>[];
  for (final e in beveledEdges) {
    final (from, to) = endpointsOf[e]!;
    final twin = mesh.twinOf(e); // still valid: never rewritten above
    final f1 = mesh.faceOf(e);
    final f2 = mesh.faceOf(twin);
    final f1From = newRing[(f1, from)]!;
    final f1To = newRing[(f1, to)]!;
    final f2From = newRing[(f2, from)]!;
    final f2To = newRing[(f2, to)]!;

    final first = mesh.halfEdgeSlotCount;
    final bridge = mesh.addFace(<int>[f1From, f2From, f2To, f1To]);
    mesh.weldTwins(first + 3, e);
    mesh.weldTwins(first + 1, twin);
    pendingHalfEdges.addAll(<int>[first, first + 2]);
    createdFaces.add(bridge);
    _inheritPatch(mesh, bridge, first, f1, square: true);
  }

  // Pass 4: the cap face itself, over the loop pass 2 already worked out —
  // built only now, once every bridge above has taken the twin it needed
  // from a beveled edge's own two original half-edges, so a cap's own edges
  // are never mistaken for one of those.
  for (final v in touchedVertices) {
    final loop = capLoops[v]!;
    final first = mesh.halfEdgeSlotCount;
    final cap = mesh.addFace(loop);
    for (var i = 0; i < loop.length; i++) {
      pendingHalfEdges.add(first + i);
    }
    createdFaces.add(cap);
    _inheritPatch(
      mesh,
      cap,
      first,
      mesh.faceOf(mesh.outgoingOf(v)),
      square: false,
    );
    mesh.deleteVertex(v);
  }

  // The bridges' own vertex-side edges and every cap edge still have no
  // twin; every one of them is shared with exactly one other half-edge in
  // this same set, found the way `EditMeshBuilder.addFace` finds a whole
  // mesh's own twins — by the vertex pair it runs between.
  final byPair = <int, int>{};
  for (final he in pendingHalfEdges) {
    if (mesh.hasLiveTwin(he)) continue;
    final from = mesh.originOf(he);
    final to = mesh.originOf(mesh.nextOf(he));
    final key = from * 0x100000000 + to;
    final oppositeKey = to * 0x100000000 + from;
    final partner = byPair.remove(oppositeKey);
    if (partner != null) {
      mesh.weldTwins(he, partner);
    } else {
      byPair[key] = he;
    }
  }

  return OpResult.done(
    selection: Selection.of(ElementLevel.face, <int>[
      ...touchedFaces,
      ...createdFaces,
    ]),
    movedVertices: Int32List.fromList(movedVertices..sort()),
    topologyChanged: true,
  );
}

/// Gives a bridge or a cap the material and shading of the face it grew out
/// of — the same choice [insetFaces]' own walls make, and the same
/// documented gap: colour is not carried.
///
/// [square] is true for a bridge, always a quad, which gets the same unit
/// square of UV [insetFaces]' own walls do; a cap is an n-gon with no
/// "unit square" to give it, so every one of its corners gets a plain zero
/// UV instead — a new face with no source to derive one from, the same
/// answer `mesh-12`'s own row gives for the general case.
void _inheritPatch(
  EditMesh mesh,
  int patch,
  int first,
  int source, {
  required bool square,
}) {
  if (mesh.hasLayer(MeshDomain.face, MeshAttribute.materialSlot)) {
    mesh.setMaterialSlot(patch, mesh.materialSlotOf(source));
  }
  if (mesh.hasLayer(MeshDomain.face, MeshAttribute.flags)) {
    mesh.setFaceFlag(
      patch,
      FaceFlags.smooth,
      on: mesh.faceHas(source, FaceFlags.smooth),
    );
  }
  if (!mesh.hasLayer(MeshDomain.corner, MeshAttribute.uv0)) return;
  if (square) {
    mesh
      ..setUv(first, Vector2(0, 0))
      ..setUv(first + 1, Vector2(1, 0))
      ..setUv(first + 2, Vector2(1, 1))
      ..setUv(first + 3, Vector2(0, 1));
    return;
  }
  var he = mesh.halfEdgeOf(patch);
  for (var i = 0; i < mesh.valencyOf(patch); i++) {
    mesh.setUv(he, Vector2.zero());
    he = mesh.nextOf(he);
  }
}
