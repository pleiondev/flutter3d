import 'dart:math' as math;

import 'package:flame/collisions.dart';
import 'package:flame/components.dart';
import 'package:flutter3d/flutter3d.dart' hide Material;

import '../transform/object3d_component.dart';

/// Draws every hitbox under [root] that belongs to a bridged component into
/// [lines], on its component's plane at its component's elevation: green,
/// and red while it is colliding.
///
/// **Flame's `debugMode` draws hitboxes where Flame thinks they are**, flat
/// on its own canvas, which under a perspective 3D camera is nowhere near
/// the craft they belong to. These are drawn in the scene, among the craft,
/// so a hit that seems to miss can be seen to miss, or not.
///
/// A rectangle or a polygon is drawn through its corners, a circle as a
/// ring of [circleSegments] sides. A hitbox with no bridged ancestor has no
/// plane to be drawn on and is left out.
void addHitboxes3d(DebugDraw lines, Component root, {int circleSegments = 24}) {
  for (final hitbox in root.descendants().whereType<ShapeHitbox>()) {
    final owner = hitbox.ancestors().whereType<Object3dComponent>().firstOrNull;
    if (owner == null || !shownInFlame(owner)) continue;
    final plane = owner.plane;
    final at = plane.constant + owner.elevation;
    final colour = hitbox.isColliding ? _colliding : _clear;

    final List<Vector2> outline = switch (hitbox) {
      final PolygonComponent polygon => polygon.globalVertices(),
      final CircleHitbox circle => <Vector2>[
        for (var i = 0; i < circleSegments; i++)
          circle.absoluteCenter +
              Vector2(
                    math.cos(2.0 * math.pi * i / circleSegments),
                    math.sin(2.0 * math.pi * i / circleSegments),
                  ) *
                  (circle.radius * circle.absoluteScale.x.abs()),
      ],
      _ => const <Vector2>[],
    };
    for (var i = 0; i < outline.length; i++) {
      lines.addLine(
        plane.to3d(outline[i], at: at),
        plane.to3d(outline[(i + 1) % outline.length], at: at),
        colour,
      );
    }
  }
}

Vector4 get _clear => Vector4(0.3, 1.0, 0.4, 1.0);
Vector4 get _colliding => Vector4(1.0, 0.3, 0.25, 1.0);
