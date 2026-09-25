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
import 'cpu_shaders_evsm.dart';
import 'cpu_shaders_surface.dart';

/// `ShadowFactor`: how much of the directional light survives here.
///
/// One — not zero — outside the map, off the caster, or with shadows off. A
/// fragment beyond the shadow volume is unshadowed, and getting that backwards
/// puts a hard edge across the scene at the edge of the map.
///
/// [lightNDotL] is the light's `n_dot_l`, which `ShadowFactor` is handed with
/// the light and no longer reads: the offset measures the slope along the
/// map's own axes instead.
double shadowFactor(
  Surface s,
  ShaderBindings b,
  int lightIndex,
  double lightNDotL, [
  FragmentContext? c,
]) {
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
  // distance plus a texel and a half of the cascade times the sine of the
  // slope along each axis of the map, measured per cascade below, for the
  // reason `shadow.glsl` gives.

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
  var cascadeIndex = 0;
  Vector3? projected;
  // `S3`: metres per texel across, and per unit of stored depth along the
  // light, of the cascade the fragment lands in.
  var cascadeTexel = 1.0;
  var cascadeDepth = 1.0;
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
    // projection is 2 / width. The rows are the map's axes in the world, and
    // the normal's share along each is the sine of the slope that way.
    final axisX = Vector3(
      matrix.entry(0, 0),
      matrix.entry(0, 1),
      matrix.entry(0, 2),
    );
    final axisY = Vector3(
      matrix.entry(1, 0),
      matrix.entry(1, 1),
      matrix.entry(1, 2),
    );
    final rowX = math.max(axisX.length, 1e-6);
    final rowY = math.max(axisY.length, 1e-6);
    final tileTexel = cascades.w > 0.0 ? cascades.w : params.x;
    final texelMetres = 2.0 * tileTexel / rowX;
    final reach =
        1.5 *
        2.0 *
        tileTexel *
        (s.normal.dot(axisX).abs() / (rowX * rowX) +
            s.normal.dot(axisY).abs() / (rowY * rowY));
    final origin = s.world + s.normal * (params.z + reach);
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
    cascadeIndex = which;
    projected = candidate;
    cascadeTexel = texelMetres;
    cascadeDepth =
        1.0 /
        math.max(
          Vector3(
            matrix.entry(2, 0),
            matrix.entry(2, 1),
            matrix.entry(2, 2),
          ).length,
          1e-6,
        );
    break;
  }
  if (projected == null) return 1.0;

  // Each cascade's own bias — `shadow_bias` in `surface.glsl`.
  final bias = b.vec4('FragInfo', 'shadow_bias', Vector4.zero())[cascadeIndex];
  // Horizontally a texel of the atlas, vertically a texel of a tile.
  final texelU = params.x;
  final texelV = cascades.w > 0.0 ? cascades.w : params.x;
  // Every tap held inside its own cascade's tile — see `shadow.glsl`.
  final loU = cascadeIndex / count + 0.5 * texelU;
  final hiU = (cascadeIndex + 1) / count - 0.5 * texelU;
  final loV = 0.5 * texelV;
  final hiV = 1.0 - 0.5 * texelV;
  double tap(double du, double dv) =>
      map.sample((u + du).clamp(loU, hiU), (vv + dv).clamp(loV, hiV)).x;

  // `gfx-15n`: the directional light's apparent size, riding in
  // `ambient_ground.w` for the reason `surface.glsl` gives. Zero is the 3×3
  // kernel this has always had.
  // Below zero is the `evsm` filter (`S2`): the texture is the moments
  // atlas, one filtered tap is the kernel, and how far under minus one the
  // value sits is the light-bleeding cut.
  final softness = b.vec4('FragInfo', 'ambient_ground', Vector4.zero()).w;

  var lit = 0.0;
  if (softness < 0.0) {
    final moments = map.sample(u.clamp(loU, hiU), vv.clamp(loV, hiV));
    lit = evsmVisibility(
      moments,
      projected.z - bias,
      (-softness - 1.0).clamp(0.0, 0.95),
    );
  } else if (softness <= 0.0) {
    // PCF 3x3: four samples band visibly at this map size and nine is the
    // smallest kernel that reads as a soft edge rather than as stair steps.
    for (var y = -1; y <= 1; y++) {
      for (var x = -1; x <= 1; x++) {
        final occluder = tap(x * texelU, y * texelV);
        lit += projected.z - bias > occluder ? 0.0 : 1.0;
      }
    }
    lit /= 9.0;
  } else {
    // `S3`: sixteen taps each way on a Vogel disc turned per pixel, and the
    // penumbra in metres — mirroring `shadow.glsl` step for step.
    final spread = 2.0 * math.tan(math.min(softness, 0.5));
    final turn = shadowNoise(b, c) * 6.2831853;
    final searchRadius = (spread * projected.z * cascadeDepth / cascadeTexel)
        .clamp(1.0, 16.0);
    var blockerSum = 0.0;
    var blockerCount = 0.0;
    for (var i = 0; i < 16; i++) {
      final (dx, dy) = vogelDisc(i, 16, turn);
      final occluder = tap(
        dx * texelU * searchRadius,
        dy * texelV * searchRadius,
      );
      if (projected.z - bias > occluder) {
        blockerSum += occluder;
        blockerCount += 1.0;
      }
    }
    if (blockerCount <= 0.0) return 1.0;

    final averaged = projected.z - blockerSum / blockerCount;
    final gap = (averaged > 0.0 ? averaged : 0.0) * cascadeDepth;
    final radius = (spread * gap / cascadeTexel).clamp(1.0, 16.0);
    for (var i = 0; i < 16; i++) {
      final (dx, dy) = vogelDisc(i, 16, turn + 1.0);
      final occluder = tap(dx * texelU * radius, dy * texelV * radius);
      lit += projected.z - bias > occluder ? 0.0 : 1.0;
    }
    lit /= 16.0;
  }
  return 1.0 + (lit - 1.0) * strength.clamp(0.0, 1.0);
}

/// `VogelDisc` from `shadow.glsl` — `S3`.
(double, double) vogelDisc(int i, int n, double turn) {
  final r = math.sqrt((i + 0.5) / n);
  final theta = i * 2.3999632 + turn;
  return (r * math.cos(theta), r * math.sin(theta));
}

/// `ShadowNoise` from `shadow.glsl` — `S3`: interleaved gradient noise at
/// the pixel, stepped by the frame's slice while a resolve runs.
double shadowNoise(ShaderBindings b, FragmentContext? c) {
  if (c == null) return 0.0;
  final slice = b.vec4('FragInfo', 'target_origin', Vector4.zero()).w;
  final step = 5.588238 * (slice > 0.0 ? slice : 0.0);
  final x = c.coord.x + step;
  final y = c.coord.y + step;
  double fract(double v) => v - v.floorToDouble();
  return fract(52.9829189 * fract(x * 0.06711056 + y * 0.00583715));
}
