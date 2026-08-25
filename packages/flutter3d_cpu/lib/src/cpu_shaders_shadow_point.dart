/// `PointShadowFactor` from `shadow.glsl`: the cube-atlas lookup for point and
/// spot lights, with a PCSS-style blocker search for the soft-shadow radius.
///
/// See `cpu_shaders_shadow_directional.dart` for why this is a separate file
/// from the cascaded lookup rather than a second branch in one.
library;

import 'dart:math' as math;

import 'package:vector_math/vector_math.dart';

import 'cpu_shader.dart';
import 'cpu_shaders_color.dart';

/// Atlas rows, from `kShadowSlots` in `surface.glsl`.
const int shadowSlots = 4;

/// The Poisson disk the cube filter rotates, from `PointShadowDiskTap`.
const List<List<double>> diskTaps = <List<double>>[
  <double>[-0.94201624, -0.39906216],
  <double>[0.94558609, -0.76890725],
  <double>[-0.09418410, -0.92938870],
  <double>[0.34495938, 0.29387760],
  <double>[-0.91588581, 0.45771432],
  <double>[-0.81544232, -0.87912464],
  <double>[-0.38277543, 0.27676845],
  <double>[0.97484398, 0.75648379],
];

/// `PointShadowDistance`: one comparison against the atlas.
///
/// The clamp is applied **after** the offset, holding each tap inside its own
/// tile individually. Clamping the centre and then offsetting would let the
/// outer taps walk into a distance measured from a different face, or from a
/// different light.
double atlasDistance(ShaderBindings b, double u, double v, double ox,
    double oy, double tileX, double tileY, double range, double inset) {
  final localU = (u + ox).clamp(inset, 1.0 - inset);
  final localV = (v + oy).clamp(inset, 1.0 - inset);
  final atlasU = (localU + tileX) / 6.0;
  final atlasV = (localV + tileY) / shadowSlots;

  final dynamicMap = b.textures['point_shadow_texture'];
  final staticMap = b.textures['point_shadow_static_texture'];
  var nearest = 1.0;
  if (dynamicMap != null) nearest = dynamicMap.sample(atlasU, atlasV).x;
  if (staticMap != null) {
    // Whichever is nearer occludes: a wall in front of a monster shadows, and
    // so does a monster in front of a wall.
    nearest = math.min(nearest, staticMap.sample(atlasU, atlasV).x);
  }
  return nearest * range;
}

/// `PointShadowFactor`: how lit a point is by the light that owns the atlas.
double pointShadowFactor(
    ShaderBindings b, Vector3 world, Vector3 normal, int lightIndex,
    FragmentContext c) {
  final slotEntry =
      b.vec4('PointShadow', 'slots', Vector4(-1, 0, 0, 0), at: lightIndex);
  if (slotEntry.x < 0.0) return 1.0;
  final slot = (slotEntry.x + 0.5).floor();

  final params = b.vec4('PointShadow', 'params', Vector4.zero());
  final strength = params.z;
  if (strength <= 0.0) return 1.0;

  final light = b.vec4('PointShadow', 'lights', Vector4.zero(), at: slot);
  final lightPos = Vector3(light.x, light.y, light.z);

  // Offset along the normal, scaled by how steeply the surface leans away.
  // A soft kernel on a tilted surface straddles a depth gradient, so a flat
  // offset that clears the surface head-on leaves acne at a grazing angle. The
  // cap matters: uncapped, the lift detaches the shadow from its caster.
  final toLight = lightPos - world;
  final toLightLength = math.max(toLight.length, 1e-6);
  final nDotL = math.max(normal.dot(toLight / toLightLength), 0.15);
  final slope =
      math.min(math.sqrt(math.max(1.0 - nDotL * nDotL, 0.0)) / (nDotL * nDotL),
          8.0);
  final origin = world + normal * (params.w * (1.0 + slope));
  final toFragment = origin - lightPos;
  final distance = toFragment.length;
  final range = math.max(light.w, 1e-4);
  if (distance >= range) return 1.0;

  // The dominant axis picks the face, in the order the renderer wrote them:
  // +X, -X, +Y, -Y, +Z, -Z, left to right then top to bottom. A spot has one
  // column and no choice to make — and asking anyway would send most of a
  // downlight's cone to column 3, which for a spot is deliberately blank.
  final int face;
  if (slotEntry.y >= 0.5) {
    face = 0;
  } else {
    final a =
        Vector3(toFragment.x.abs(), toFragment.y.abs(), toFragment.z.abs());
    if (a.x >= a.y && a.x >= a.z) {
      face = toFragment.x > 0.0 ? 0 : 1;
    } else if (a.y >= a.z) {
      face = toFragment.y > 0.0 ? 2 : 3;
    } else {
      face = toFragment.z > 0.0 ? 4 : 5;
    }
  }

  final matrix = b.mat4('PointShadow', 'faces', at: slot * 6 + face);
  final Vector4 clip = matrix * Vector4(origin.x, origin.y, origin.z, 1.0);
  if (clip.w <= 0.0) return 1.0;
  final ndcX = clip.x / clip.w;
  final ndcY = clip.y / clip.w;
  if (ndcX.abs() > 1.0 || ndcY.abs() > 1.0) return 1.0;

  // v is flipped, as the directional map does it: the texture's origin is at
  // the top, where row zero of the render target is.
  final u = ndcX * 0.5 + 0.5;
  final vv = 0.5 - ndcY * 0.5;
  final tileX = face.toDouble();
  final tileY = slot.toDouble();
  final inset = params.x;
  final receiver = distance - params.y;

  // One rotation per fragment, shared by the search and the filter, so eight
  // samples read as a soft edge rather than as eight copies of the silhouette.
  final noise = fract(52.9829189 *
      fract(c.coord.x * 0.06711056 + c.coord.y * 0.00583715));
  final angle = noise * 6.28318530718;
  final ca = math.cos(angle);
  final sa = math.sin(angle);

  final params2 = b.vec4('PointShadow', 'params2', Vector4.zero());
  final lightRadius = params2.y;
  final minRadius = params2.x;
  final maxRadius = params2.z;

  // The tangent of half the frustum's opening angle, which turns a world width
  // into a fraction of a tile. Exactly one for a cube face — ninety degrees —
  // and guarded because zero is what an unwritten channel holds, and a division
  // by it would come back NaN rather than merely wrong.
  final tanHalf = math.max(slotEntry.z, 1e-4);

  double radius;
  if (lightRadius <= 0.0) {
    radius = minRadius;
  } else {
    // The blocker search runs at the widest penumbra allowed: a blocker
    // outside that circle cannot widen the result, and searching narrower
    // would miss the very blockers that make an edge soft.
    var sum = 0.0;
    var count = 0.0;
    for (var i = 0; i < 8; i++) {
      final p = diskTaps[i];
      final ox = (p[0] * ca - p[1] * sa) * maxRadius;
      final oy = (p[0] * sa + p[1] * ca) * maxRadius;
      final stored =
          atlasDistance(b, u, vv, ox, oy, tileX, tileY, range, inset);
      if (stored >= range * 0.999) continue;
      if (stored >= receiver) continue;
      sum += stored;
      count += 1.0;
    }
    // Nothing in front of this fragment anywhere in the search.
    if (count < 0.5) return 1.0;
    final blocker = math.max(sum / count, 1e-4);
    final worldWidth = lightRadius * math.max(receiver - blocker, 0.0) / blocker;
    // `2 * r` is the span of a right-angled frustum at distance r; in general
    // it is `2 * r * tan(θ/2)`. A narrower cone covers less world per tile, so
    // the same width is a larger fraction of it.
    radius =
        (worldWidth / (2.0 * receiver * tanHalf)).clamp(minRadius, maxRadius);
  }

  double tap(double ox, double oy) {
    final stored = atlasDistance(b, u, vv, ox, oy, tileX, tileY, range, inset);
    // Nothing was drawn in that direction by either map.
    if (stored >= range * 0.999) return 1.0;
    return receiver > stored ? 0.0 : 1.0;
  }

  var lit = tap(0.0, 0.0);
  if (radius > 0.0) {
    for (var i = 0; i < 8; i++) {
      final p = diskTaps[i];
      lit += tap((p[0] * ca - p[1] * sa) * radius,
          (p[0] * sa + p[1] * ca) * radius);
    }
    lit /= 9.0;
  }
  return 1.0 + (lit - 1.0) * strength.clamp(0.0, 1.0);
}
