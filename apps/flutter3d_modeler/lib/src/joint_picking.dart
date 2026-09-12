/// Turning a click near a skeleton overlay into the joint it meant —
/// `anim-08`'s own picker.
///
/// **A joint has no area, the same reason a vertex has none in
/// `element_picking.dart`.** What a person means by clicking near an
/// octahedron drawn at a joint's own position is the nearest one within some
/// screen distance of where they clicked, not a hit test on a shape nothing
/// here draws — the overlay is `DebugDraw`'s own job, and this only answers
/// which joint a point on screen was closest to.
///
/// Nothing here is a widget. A joint's own world position is looked up
/// however the caller already has it — a project's `ProjectSkeleton` names
/// joints by `ModelObject` id, and turning an id into a world position is
/// `SceneSync.nodeOf` and a world matrix, neither of which this file needs to
/// know about.
library;

import 'dart:ui' show Offset;

import 'package:vector_math/vector_math.dart';

import 'element_picking.dart';

/// The joint nearest [at], among [joints]' own world positions, within
/// [radius] logical pixels of the point on screen its position projects to.
///
/// [EditMesh.none]-style absence is a plain `null` here rather than a shared
/// sentinel: joint ids are `ModelObject.id`s, a different id space from a
/// mesh's own vertex, edge and face slots, and borrowing that sentinel would
/// invite a caller to compare the two kinds of "nothing" as though they were
/// one.
int? pickJointAt(
  PickingView view,
  Offset at, {
  required Map<int, Vector3> joints,
  double radius = 8.0,
}) {
  int? best;
  var nearest = double.infinity;
  for (final MapEntry<int, Vector3> entry in joints.entries) {
    final Offset? screen = view.project(entry.value);
    if (screen == null) continue;
    final double distance = (screen - at).distance;
    if (distance > radius || distance >= nearest) continue;
    nearest = distance;
    best = entry.key;
  }
  return best;
}
