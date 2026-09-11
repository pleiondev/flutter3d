/// Repair, not just diagnosis — `mesh-81n`'s own row, complementing
/// `MeshChecks`, which finds every one of these and fixes none of them.
///
/// **What is here: `fillHoles`, in its "по границе" (boundary) form** —
/// one new face per hole, its loop read straight off the mesh's own
/// existing boundary half-edges rather than re-derived, and welded back to
/// every one of them so the hole is actually closed rather than merely
/// covered.
///
/// **What is not, and why.**
/// - **`fillHoles`'s "веером" (fan) form** — triangulating a hole from one
///   anchor vertex instead of leaving it an n-gon — needs the same
///   boundary welding this file already does correctly, plus a second
///   round of welds between the fan's own internal "spoke" edges. Getting
///   both right, precisely indexed, without a fixture that actually
///   distinguishes a fan from an n-gon (a simple removed cube face does
///   not), is a real chance to ship a mesh that reads as closed and is
///   not. Left out rather than risked.
/// - **`splitNonManifoldEdges`** — `checks.dart`'s own doc comment already
///   says why a non-manifold *edge* cannot exist in this structure at all
///   (`importMeshData` splits one on the way in); the case people mean by
///   the name is `MeshChecks.nonManifoldVertices`, and fixing it means
///   giving one mesh vertex two numbers — rewiring a fan's own origin
///   pointers — which is a change to `EditMesh`'s own internals this row's
///   one operation did not need to make.
/// - **`flipShells`** needed no new code at all: `EditMesh.makeConsistent`
///   already winds every closed island outward and says whether anything
///   turned, which is this sub-row exactly, under a different name —
///   `anim-26`'s own shape, a status flip rather than a function.
library;

import 'checks.dart';
import 'edit_mesh.dart';

/// Closes every hole in [mesh] with one face per boundary loop, welded to
/// the half-edges that were already there — the mesh's own boundary,
/// walked and reversed rather than re-triangulated. Returns how many holes
/// were closed.
///
/// A [mesh] with no open edges returns `0` and changes nothing.
int fillHoles(EditMesh mesh) {
  final chains = boundaryChains(mesh);
  for (final chain in chains) {
    final loop = <int>[for (final half in chain) mesh.originOf(mesh.nextOf(half))];
    final first = mesh.halfEdgeSlotCount;
    mesh.addFace(loop);
    for (var i = 0; i < chain.length; i++) {
      mesh.weldTwins(first + i, chain[i]);
    }
  }
  return chains.length;
}

/// Every closed loop of boundary half-edges in [mesh], each returned as
/// the *original* half-edges in hole order — [fillHoles]'s own building
/// block, and public because a caller wanting to preview or pick a hole
/// before filling it needs the same walk.
///
/// **Read as a chain of half-edges, not vertices, on purpose.** A new
/// face's `i`-th half-edge is the exact reverse of `chain[i]`, which is
/// what makes welding it back a matter of pairing up indices rather than
/// searching the mesh a second time for which original edge a new one
/// belongs to.
///
/// **The reversal, in one sentence.** A boundary half-edge `h` belongs to
/// a live face and runs one way; the hole on its other side, if it had a
/// face, would run the opposite way — so the hole's own next edge, after
/// `h`, is whichever other boundary half-edge starts where `h` does:
/// `chain[i + 1]` is the boundary half-edge whose own destination is
/// `originOf(chain[i])`.
List<List<int>> boundaryChains(EditMesh mesh) {
  final boundary = MeshChecks(mesh).boundaryEdges()?.ids ?? const <int>[];
  if (boundary.isEmpty) return const <List<int>>[];

  final byDestination = <int, int>{
    for (final half in boundary) mesh.originOf(mesh.nextOf(half)): half,
  };

  final visited = <int>{};
  final chains = <List<int>>[];
  for (final start in boundary) {
    if (visited.contains(start)) continue;
    final chain = <int>[start];
    visited.add(start);
    var current = start;
    while (true) {
      final next = byDestination[mesh.originOf(current)];
      if (next == null || next == start) break;
      chain.add(next);
      visited.add(next);
      current = next;
    }
    chains.add(chain);
  }
  return chains;
}
