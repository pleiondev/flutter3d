/// Screen 15's own viewport half: one point per shape key, drawn into a
/// [MeshOverlay] the same way `uv_seam_overlay.dart`'s own
/// [emitUvSeamOverlay] reuses the primitive [MeshOverlayBuilder]'s own
/// vertex handles already draw with — `overlay.point`/`overlay.ribbon`,
/// coloured, rather than a new drawing mechanism for a fourth kind of
/// marker.
///
/// **One point per shape, not the deformed mesh.** A [ShapeKey] holds a
/// whole vertex-position copy, not a single point of its own — but drawing
/// every vertex a shape moves would be the mesh's own wireframe again in
/// another colour, and would say nothing about *which* shape is which. This
/// draws the centroid of a shape's own displaced positions instead: one
/// handle a person can find in the viewport for each row `MorphsPanel`
/// draws, the same "one thing per row" a `WeightPaintPanel` bone row already
/// gives its own list.
///
/// **No live morph deformation.** Building the actually-blended mesh these
/// points describe is `S6`'s own explicit gap — `SceneSync` has no morph
/// pipeline yet, so the object in the viewport never moves when a shape's
/// own weight changes; only these markers, and the panel's own slider, say
/// anything about it in this pass.
library;

import 'dart:ui' show Color;

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_mesh/flutter3d_mesh.dart' show ShapeKey;
import 'package:vector_math/vector_math.dart';

/// One shape's own marker: where it sits, in the object's own local space,
/// and whether it is the one a person is looking at in `MorphsPanel` right
/// now.
typedef ShapeMarker = ({Vector3 position, bool active});

/// The centroid of [key]'s own displaced positions — one point standing in
/// for a whole vertex-position copy, the same way a bone's own head stands
/// in for everything it deforms.
Vector3 shapePointOf(ShapeKey key) {
  final Vector3 sum = Vector3.zero();
  for (var v = 0; v < key.vertexCount; v++) {
    sum.add(key.positionOf(v));
  }
  final int count = key.vertexCount;
  return count == 0 ? sum : sum / count.toDouble();
}

/// Draws one point per marker in [markers] into [overlay] — [active] for
/// whichever one is flagged [ShapeMarker.active], [primary] for every other.
void emitShapePointsOverlay(
  MeshOverlay overlay,
  List<ShapeMarker> markers, {
  required Vector4 primary,
  required Vector4 active,
}) {
  for (final ShapeMarker marker in markers) {
    overlay.point(marker.position, marker.active ? active : primary);
  }
}

/// [colour]'s own channels as a debug-line [Vector4], 0 to 1 each — the one
/// place a [ColorScheme] role (`ui/theme.dart`'s own `kModelerScheme`) needs
/// to reach a [MeshOverlay] rather than a widget, so the morphs sub-mode's
/// own markers read the same primary/secondary hues a person already sees
/// in the panel, rather than a second literal naming the same colour again.
Vector4 colourAsVector4(Color colour) =>
    Vector4(colour.r, colour.g, colour.b, colour.a);
