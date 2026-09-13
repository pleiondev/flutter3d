/// Which edges of a mesh are UV seams, and drawing them — `pro-uv-07`'s own
/// half of showing an unwrap in the 3D viewport it was cut from.
///
/// **Two ways an edge earns the name, matching `splitIslands`'s own two
/// reasons to cut apart** (`lscm.dart`): [EdgeFlags.seam] marks one
/// explicitly, and an edge whose two sides disagree about where the texture
/// is — a UV-space discontinuity — is one whether or not anybody flagged it,
/// the way a per-face projection ([UvProjection.box]) or a hand-edited UV can
/// leave one without ever touching the flag. A mesh boundary (no live twin)
/// is excluded from both: there is no "other side" to disagree with, and
/// drawing every silhouette edge in the seam colour would swamp the one thing
/// this is for.
///
/// **Reuses the overlay, not a new mechanism.** [emitUvSeamOverlay] draws the
/// result through a plain [MeshOverlay] the same way
/// `MeshOverlayBuilder`'s own edge-level branch already draws a selected
/// edge in `mesh_overlay_builder.dart` — a ribbon per edge, in
/// [MeshOverlayColours.seam] by default — so a UV seam and a selected edge
/// share one drawing primitive and only their colour differs.
library;

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_mesh/flutter3d_mesh.dart';
import 'package:vector_math/vector_math.dart';

import 'mesh_overlay_builder.dart';

/// How far apart two corners' own UV may read and still count as the same
/// point — generous against the float noise a solved system like [lscm] can
/// leave behind, and small next to any UV gap a real seam or pack margin
/// leaves.
const double _uvTolerance = 1e-6;

/// One half-edge per seam edge of [mesh] — [EditMesh.edgeOf]'s own
/// representative, so a closed mesh names each seam once rather than twice.
///
/// Walked over faces because that is the only way into the half-edges, the
/// same reason `MeshOverlayBuilder._emitLines` does; a face that died since
/// the mesh was last touched is skipped rather than read.
List<int> uvSeamEdges(EditMesh mesh) {
  final seams = <int>[];
  for (var face = 0; face < mesh.faceSlotCount; face++) {
    if (!mesh.isFaceAlive(face)) continue;
    mesh.forEachHalfEdge(face, (int half) {
      if (mesh.edgeOf(half) != half) return; // once per edge
      if (!mesh.hasLiveTwin(half)) return; // a mesh boundary, not a seam
      if (mesh.edgeHas(half, EdgeFlags.seam) || _uvDisagrees(mesh, half)) {
        seams.add(half);
      }
    });
  }
  return seams;
}

/// Whether the two faces sharing [half] disagree about either endpoint's own
/// place on the texture.
///
/// [half] runs from `originOf(half)` to `originOf(nextOf(half))`; its twin,
/// on a proper two-manifold half-edge mesh, runs the other way round the same
/// two vertices — so the corner this face keeps for `originOf(half)` is
/// answered on the far side by `nextOf(twin)`, and the corner for the other
/// endpoint by `twin` itself.
bool _uvDisagrees(EditMesh mesh, int half) {
  final twin = mesh.twinOf(half);
  final atOrigin = (mesh.uvOf(half) - mesh.uvOf(mesh.nextOf(twin))).length2;
  final atNext = (mesh.uvOf(mesh.nextOf(half)) - mesh.uvOf(twin)).length2;
  return atOrigin > _uvTolerance * _uvTolerance ||
      atNext > _uvTolerance * _uvTolerance;
}

/// Draws every seam [uvSeamEdges] finds into [overlay], as a ribbon per edge
/// — [MeshOverlay.ribbon], the same primitive a selected edge is drawn with.
///
/// [colour] defaults to [MeshOverlayColours.seam], the cool blue the
/// wireframe already uses for an [EdgeFlags.seam]-marked edge, so a UV seam
/// reads the same whether the 3D view is drawing it from the flag alone or
/// from this wider definition.
void emitUvSeamOverlay(MeshOverlay overlay, EditMesh mesh, {Vector4? colour}) {
  final tint = colour ?? MeshOverlayColours().seam;
  final from = Vector3.zero();
  final to = Vector3.zero();
  for (final half in uvSeamEdges(mesh)) {
    mesh.positionOf(mesh.originOf(half), from);
    mesh.positionOf(mesh.originOf(mesh.nextOf(half)), to);
    overlay.ribbon(from, to, tint);
  }
}
