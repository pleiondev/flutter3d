/// `ShadowFactor` from `shadow.glsl`: the directional/cascaded shadow lookup.
///
/// Kept apart from the point-light atlas (`cpu_shaders_shadow_point.dart`)
/// because the two share nothing but a name: this one walks a cascade of
/// orthographic matrices, that one marches a cube atlas with a PCSS-style
/// search. `cpu_shaders_lighting.dart`'s `accumulateLights` is what calls both
/// for the same fragment.
library;

import 'dart:math' as math;

import 'package:vector_math/vector_math.dart';

import 'cpu_shader.dart';
import 'cpu_shaders_surface.dart';

/// `ShadowFactor`: how much of the directional light survives here.
///
/// One — not zero — outside the map, off the caster, or with shadows off. A
/// fragment beyond the shadow volume is unshadowed, and getting that backwards
/// puts a hard edge across the scene at the edge of the map.
double shadowFactor(
  Surface s,
  ShaderBindings b,
  int lightIndex,
  double lightNDotL,
) {
  final params = b.vec4('FragInfo', 'shadow_params', Vector4.zero());
  final strength = params.w;
  if (strength <= 0.0) return 1.0;
  final frame = b.vec4('FragInfo', 'frame_params', Vector4.zero());
  if (lightIndex != (frame.z + 0.5).floor()) return 1.0;

  final map = b.textures['shadow_texture'];
  if (map == null) return 1.0;

  // Normal offset: move the sample along the normal before projecting. It
  // fixes acne a depth bias cannot, because that error is proportional to the
  // surface's slope relative to the light rather than to depth. A flat
  // distance plus one texel of the cascade scaled by the slope, for the reason
  // `shadow.glsl` gives.
  final nDotL = math.max(lightNDotL, 0.15);
  final slope = math.min(
    math.sqrt(math.max(1.0 - nDotL * nDotL, 0.0)) / (nDotL * nDotL),
    8.0,
  );

  // Which cascade covers this fragment. The mirror of shadow.glsl, and it has
  // to stay one: the parity suite compares this backend's picture against
  // Impeller's, so a difference here reads as a *rendering* bug in whichever
  // one somebody happens to be looking at.
  final cascades = b.vec4('FragInfo', 'shadow_cascades', Vector4(0, 0, 1, 0));
  final count = (cascades.z + 0.5).floor().clamp(1, 3);
  final camera = b.vec4('FragInfo', 'camera_position', Vector4.zero());
  final viewDistance = (s.world - Vector3(camera.x, camera.y, camera.z)).length;
  var cascade = 0;
  if (count > 1 && viewDistance > cascades.x) cascade = 1;
  if (count > 2 && viewDistance > cascades.y) cascade = 2;

  var u = 0.0;
  var vv = 0.0;
  Vector3? projected;
  for (var attempt = 0; attempt < 3; attempt++) {
    final which = cascade + attempt;
    if (which >= count) break;

    final matrix = b.mat4(
      'FragInfo',
      which == 0
          ? 'shadow_matrix'
          : (which == 1 ? 'shadow_matrix_far' : 'shadow_matrix_farthest'),
    );
    // One texel of this cascade in metres: the first row of an orthographic
    // projection is 2 / width.
    final rowX = Vector3(
      matrix.entry(0, 0),
      matrix.entry(0, 1),
      matrix.entry(0, 2),
    ).length;
    final tileTexel = cascades.w > 0.0 ? cascades.w : params.x;
    final texelMetres = 2.0 * tileTexel / math.max(rowX, 1e-6);
    final origin =
        s.world + s.normal * (params.z + texelMetres * (1.0 + slope));
    final Vector4 lightSpace =
        matrix * Vector4(origin.x, origin.y, origin.z, 1.0);
    if (lightSpace.w <= 0.0) continue;
    final candidate = Vector3(lightSpace.x, lightSpace.y, lightSpace.z)
      ..scale(1.0 / lightSpace.w);

    final tileU = candidate.x * 0.5 + 0.5;
    final tileV = 0.5 - candidate.y * 0.5;
    if (tileU < 0.0 || tileU > 1.0 || tileV < 0.0 || tileV > 1.0) continue;
    // Past the far plane is behind every caster: the last cascade clamps
    // rather than calling the point lit — see `shadow.glsl`.
    if (candidate.z > 1.0) {
      if (which < count - 1) continue;
      candidate.z = 1.0;
    }

    u = (tileU + which) / count;
    vv = tileV;
    projected = candidate;
    break;
  }
  if (projected == null) return 1.0;

  final bias = params.y;
  // Horizontally a texel of the atlas, vertically a texel of a tile.
  final texelU = params.x;
  final texelV = cascades.w > 0.0 ? cascades.w : params.x;

  // `gfx-15n`: the directional light's apparent size, riding in
  // `ambient_ground.w` for the reason `surface.glsl` gives. Zero is the 3×3
  // kernel this has always had.
  final softness = b.vec4('FragInfo', 'ambient_ground', Vector4.zero()).w;

  var lit = 0.0;
  if (softness <= 0.0) {
    // PCF 3x3: four samples band visibly at this map size and nine is the
    // smallest kernel that reads as a soft edge rather than as stair steps.
    for (var y = -1; y <= 1; y++) {
      for (var x = -1; x <= 1; x++) {
        final occluder = map.sample(u + x * texelU, vv + y * texelV).x;
        lit += projected.z - bias > occluder ? 0.0 : 1.0;
      }
    }
    lit /= 9.0;
  } else {
    // The blocker search, then the filter sized by what it found — mirroring
    // `shadow.glsl` step for step.
    // Bounded, not proportional: see `shadow.glsl`.
    final searchRadius = (softness * 0.25).clamp(2.0, 16.0);
    var blockerSum = 0.0;
    var blockerCount = 0.0;
    for (final (double dx, double dy) in kShadowDisc) {
      final occluder = map
          .sample(
            u + dx * texelU * searchRadius,
            vv + dy * texelV * searchRadius,
          )
          .x;
      if (projected.z - bias > occluder) {
        blockerSum += occluder;
        blockerCount += 1.0;
      }
    }
    if (blockerCount <= 0.0) return 1.0;

    final averaged = projected.z - blockerSum / blockerCount;
    final gap = averaged > 0.0 ? averaged : 0.0;
    final radius = (gap * softness).clamp(1.0, 16.0);
    for (final (double dx, double dy) in kShadowDisc) {
      final occluder = map
          .sample(u + dx * texelU * radius, vv + dy * texelV * radius)
          .x;
      lit += projected.z - bias > occluder ? 0.0 : 1.0;
    }
    lit /= 5.0;
  }
  return 1.0 + (lit - 1.0) * strength.clamp(0.0, 1.0);
}

/// `kShadowDisc` from `shadow.glsl`: the centre and four diagonals.
const List<(double, double)> kShadowDisc = <(double, double)>[
  (0.0, 0.0),
  (0.7071, 0.7071),
  (-0.7071, 0.7071),
  (0.7071, -0.7071),
  (-0.7071, -0.7071),
];
