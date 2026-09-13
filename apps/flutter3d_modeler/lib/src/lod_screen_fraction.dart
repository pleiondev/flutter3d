/// Meters ↔ screen fraction, for the LOD panel — `pro-lod-03`'s own row.
///
/// **The same math [LodGroup.screenFraction] already runs, not a second
/// formula next to it.** That method answers "how much of the frame does
/// *this object's actual bounding sphere* cover", which needs a live scene
/// node to ask; a person typing a LOD threshold into the editor has no
/// bounding sphere yet, only a size in meters they have in mind and a
/// camera to preview it against. [screenFractionForSize] and
/// [sizeForScreenFraction] below are that same perspective-divide, applied
/// to a size handed in directly rather than read off a node, so a project
/// file's `LodSpec.maxScreenFraction` means exactly what
/// `package:flutter3d`'s own `LodLevel.maxScreenFraction` already means —
/// there is one true conversion between the two units, not an editor's
/// approximation of the engine's.
library;

import 'dart:math' as math;

import 'package:flutter3d/flutter3d.dart';

/// The fraction of the viewport's height an object [diameterMeters] wide
/// would cover, seen through [projection] from [distanceMeters] away.
///
/// Mirrors [LodGroup.screenFraction] exactly: an orthographic projection's
/// answer does not depend on distance at all, since parallel projection
/// draws every depth at the same size; a perspective one scales by how far
/// the half-height of the view volume has grown at that distance, using
/// [Projection.verticalFieldOfView] the same way the engine's own LOD
/// selection does — through the abstraction, not an `is` check that would
/// go quietly wrong for `OffAxisProjection` or `TiledProjection`.
double screenFractionForSize({
  required double diameterMeters,
  required double distanceMeters,
  required Projection projection,
}) {
  if (diameterMeters <= 0.0) return 0.0;
  final double radius = diameterMeters / 2.0;

  if (projection is OrthographicProjection) {
    if (projection.height <= 0.0) return 0.0;
    return diameterMeters / projection.height;
  }

  final double fov = projection.verticalFieldOfView ?? math.pi / 4;
  // Inside the sphere the object fills the frame — see `LodGroup`'s own
  // comment for why the formula below would otherwise divide by a distance
  // smaller than the radius and blow up.
  if (distanceMeters <= radius) return 1.0;
  final double halfHeight = math.tan(fov * 0.5) * distanceMeters;
  if (halfHeight <= 0.0) return 1.0;
  return math.min(1.0, radius / halfHeight);
}

/// The inverse of [screenFractionForSize]: the real-world diameter, in
/// meters, that would cover [screenFraction] of the viewport's height at
/// [distanceMeters] through [projection] — what the editor solves for when
/// someone drags a preview distance instead of typing a screen-fraction
/// number directly, or previews what a `LodSpec.maxScreenFraction` a file
/// already holds means in the units a person actually thinks in.
double sizeForScreenFraction({
  required double screenFraction,
  required double distanceMeters,
  required Projection projection,
}) {
  if (screenFraction <= 0.0) return 0.0;

  if (projection is OrthographicProjection) {
    return screenFraction * projection.height;
  }

  final double fov = projection.verticalFieldOfView ?? math.pi / 4;
  final double halfHeight = math.tan(fov * 0.5) * distanceMeters;
  return screenFraction * halfHeight * 2.0;
}
