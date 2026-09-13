/// Drawing the collision shapes a played-back simulation collides against —
/// `pro-sim-04`'s other half.
///
/// A thin visualisation layer over data two other rows already made real:
/// `pro-sim-01`'s cloth solver in `flutter3d_physics` solves against
/// `ClothObstacle`s, each one a `CollisionShape` from the same package at a
/// position, and this
/// engine's own `DebugDraw` (`packages/flutter3d/lib/src/engine/render/
/// debug_draw.dart`) already accumulates line segments into one buffer for
/// exactly this kind of overlay — bounds, normals, gizmos, frusta. Nothing
/// here is a new physics feature: it reads [ClothObstacle.shape] and
/// [ClothObstacle.position], which already exist, and turns them into lines.
library;

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_physics/flutter3d_physics.dart';
import 'package:vector_math/vector_math.dart';

/// Draws a wireframe box around the world-space bounds of every obstacle in
/// [obstacles] into [draw].
///
/// Every [CollisionShape] answers [CollisionShape.computeBounds] regardless
/// of its concrete kind (box, sphere, capsule, wedge, heightfield) — it is
/// the one query the sealed hierarchy makes total rather than a `switch` this
/// package would have to keep exhaustive. Drawing that box rather than each
/// shape's exact silhouette is deliberately the cheap, always-correct answer:
/// a wedge's own doc comment already warns that its bounding box is not its
/// true shape (a ramp is not its box), but the box is still an honest, if
/// loose, "collision happens somewhere in here" — which is what a cache
/// scrub overlay needs to show, not a mesh-accurate collider render.
void drawClothObstacles(
  DebugDraw draw,
  List<ClothObstacle> obstacles, {
  Vector4? color,
}) {
  for (final obstacle in obstacles) {
    drawClothObstacle(draw, obstacle, color: color);
  }
}

/// Draws a wireframe box around one obstacle's world-space bounds.
void drawClothObstacle(DebugDraw draw, ClothObstacle obstacle, {Vector4? color}) {
  final bounds = Aabb3();
  obstacle.shape.computeBounds(obstacle.position, bounds);
  _drawWireBox(draw, bounds, color ?? DebugColors.bounds);
}

/// The twelve edges of [box], as six pairs of parallel lines — the same shape
/// [DebugDraw] itself has no built-in for (its own overlays draw a mesh's
/// bounds by looping this same way at the call site of `bounds`, so this
/// mirrors that rather than inventing a second convention).
void _drawWireBox(DebugDraw draw, Aabb3 box, Vector4 color) {
  final min = box.min;
  final max = box.max;

  final corners = <Vector3>[
    Vector3(min.x, min.y, min.z),
    Vector3(max.x, min.y, min.z),
    Vector3(max.x, max.y, min.z),
    Vector3(min.x, max.y, min.z),
    Vector3(min.x, min.y, max.z),
    Vector3(max.x, min.y, max.z),
    Vector3(max.x, max.y, max.z),
    Vector3(min.x, max.y, max.z),
  ];

  const edges = [
    // Bottom face.
    [0, 1], [1, 2], [2, 3], [3, 0],
    // Top face.
    [4, 5], [5, 6], [6, 7], [7, 4],
    // Verticals joining the two.
    [0, 4], [1, 5], [2, 6], [3, 7],
  ];

  for (final edge in edges) {
    draw.addLine(corners[edge[0]], corners[edge[1]], color);
  }
}
