/// Which light marker a ray meets — `mat-24`'s own "источники как пикаемые
/// маркеры": pure ray-versus-sphere arithmetic over positions a caller
/// already knows, the same split `transform_gizmo.dart`'s own `GizmoHit`
/// keeps between where a marker is and what a widget does about the answer.
///
/// **Positions arrive as an argument, not out of a light.** `ProjectLight`
/// (`scene_lighting.dart`) has no position of its own yet — its fields stop
/// at colour, intensity, range and the two cone angles, because nothing
/// before this row has asked to move a light — so a caller that knows where
/// a light's own runtime node stands (`LightNode.readWorldPosition`, once a
/// project's lights are given a place to live) hands it in here rather than
/// this file inventing a document field that does not exist. Kept this way
/// on purpose: a picking function that reached into `ProjectLight` for a
/// field it does not have would either crash today or have to grow one just
/// to compile, and growing the document model is not this file's job.
library;

import 'dart:math' as math;

import 'package:vector_math/vector_math.dart';

import 'transform_gizmo.dart' show GizmoView;

/// How big a light marker reads on screen, in logical pixels — the same
/// idea `kGizmoGrabPixels` gives a gizmo arrow's own slack, sized here
/// against [GizmoView] because a marker's hit target has to shrink and grow
/// with distance the way an arrow's does: fixed in world units, a light far
/// from the camera would keep a hand-sized target nothing could miss, and
/// one close up would keep a target too small to land a press on.
const double kLightMarkerPixels = 14.0;

/// The index into [positions] the ray from [eye] along the unit vector
/// [along] meets first, or null when it meets none.
///
/// Each marker is a sphere [markerPixels] wide on screen, sized by [view]
/// the way [GizmoView.worldSize] already sizes a gizmo arrow. Ties go to the
/// nearer marker, which is the only tie a person can mean: two markers one
/// behind the other are picked by whichever one is in front.
int? pickLightMarker({
  required List<Vector3> positions,
  required Vector3 eye,
  required Vector3 along,
  required GizmoView view,
  double markerPixels = kLightMarkerPixels,
}) {
  int? found;
  var nearest = double.infinity;
  for (var i = 0; i < positions.length; i++) {
    final Vector3 position = positions[i];
    final double radius = view.worldSize(markerPixels, position);
    final double? distance = _sphereHit(position, radius, eye, along);
    if (distance == null || distance >= nearest) continue;
    nearest = distance;
    found = i;
  }
  return found;
}

/// How far along [along] from [from] the ray first enters the sphere at
/// [center] with radius [radius], or null when it never does.
///
/// The standard ray-sphere quadratic, solved for the nearer root. A ray that
/// starts inside the sphere answers zero rather than a negative number — the
/// same "already inside counts as a hit" rule `transform_gizmo.dart`'s own
/// `_boxHit` gives a gizmo handle.
double? _sphereHit(Vector3 center, double radius, Vector3 from, Vector3 along) {
  final Vector3 toCenter = center - from;
  final double projected = toCenter.dot(along);
  final double closestSquared = toCenter.length2 - projected * projected;
  final double radiusSquared = radius * radius;
  if (closestSquared > radiusSquared) return null;
  final double reach = math.sqrt(radiusSquared - closestSquared);
  final double enter = projected - reach;
  return enter < 0.0 ? 0.0 : enter;
}
