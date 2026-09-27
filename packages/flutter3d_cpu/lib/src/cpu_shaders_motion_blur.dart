/// `velocity_tile_max.frag`, `velocity_neighbor_max.frag` and
/// `motion_blur.frag` on the software rasteriser — `R6`.
///
/// Line for line, ties included: each search keeps the first longest motion
/// it meets, in the GLSL's order, so two equal motions pick the same winner
/// here as on a GPU. See the GLSL for why each step is there.
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:vector_math/vector_math.dart';

import 'cpu_shader.dart';
import 'cpu_shaders_color.dart' show smoothstep;
import 'cpu_shaders_reflections.dart' show pixelNoise;

/// `HalfMotion`: [x], [y] scaled by [scale] into pixels and no longer than
/// [most].
Vector2 _halfMotion(double x, double y, Vector4 scale, double most) {
  final pixels = Vector2(x * scale.x, y * scale.y);
  final span = pixels.length;
  final limit = math.max(most, 0.0);
  return span > limit ? pixels * (limit / span) : pixels;
}

/// `velocity_tile_max.frag`: the longest motion along one axis of a tile.
final class VelocityTileMaxShader implements CpuFragmentShader {
  const VelocityTileMaxShader();

  @override
  Vector4? run(Float32List v, ShaderBindings b, FragmentContext c) {
    final velocity = b.textures['velocity_texture'];
    if (velocity == null) return Vector4(0.0, 0.0, 0.0, 1.0);
    final source = b.vec4('TileMaxInfo', 'source', Vector4.zero());
    final params = b.vec4('TileMaxInfo', 'params', Vector4.zero());
    final target = b.vec4('TileMaxInfo', 'target', Vector4.zero());

    final taps = (params.w + 0.5).floor();
    final tileX = (v[0] * target.x).floorToDouble();
    final tileY = (v[1] * target.y).floorToDouble();
    // `mix(1, taps, walk)`, per axis.
    final startX = tileX * (1.0 + (taps - 1.0) * source.z);
    final startY = tileY * (1.0 + (taps - 1.0) * source.w);

    var longest = Vector2.zero();
    var longestSpan = 0.0;
    for (var i = 0; i < 64 && i < taps; i++) {
      final at = velocity.sample(
        (startX + source.z * i + 0.5) * source.x,
        (startY + source.w * i + 0.5) * source.y,
      );
      final motion = _halfMotion(at.x, at.y, params, params.z);
      final span = motion.dot(motion);
      if (span > longestSpan) {
        longest = motion;
        longestSpan = span;
      }
    }
    return Vector4(longest.x, longest.y, 0.0, 1.0);
  }
}

/// `velocity_neighbor_max.frag`: the longest motion in a tile and the eight
/// around it.
final class VelocityNeighborMaxShader implements CpuFragmentShader {
  const VelocityNeighborMaxShader();

  @override
  Vector4? run(Float32List v, ShaderBindings b, FragmentContext c) {
    final tiles = b.textures['tile_texture'];
    if (tiles == null) return Vector4(0.0, 0.0, 0.0, 1.0);
    final texel = b.vec4('NeighborMaxInfo', 'texel', Vector4.zero());

    var longest = Vector2.zero();
    var longestSpan = 0.0;
    for (var dy = -1; dy <= 1; dy++) {
      for (var dx = -1; dx <= 1; dx++) {
        final at = tiles.sample(v[0] + dx * texel.x, v[1] + dy * texel.y);
        final span = at.x * at.x + at.y * at.y;
        if (span > longestSpan) {
          longest = Vector2(at.x, at.y);
          longestSpan = span;
        }
      }
    }
    return Vector4(longest.x, longest.y, 0.0, 1.0);
  }
}

/// `motion_blur.frag`: the gather along each neighbourhood's dominant
/// motion, composited as the time each sample covers the pixel.
final class MotionBlurShader implements CpuFragmentShader {
  const MotionBlurShader();

  static double _far(double depth) => depth <= 0.0 ? 1e9 : depth;

  static Vector3 _mix(Vector3 a, Vector3 b, double t) => a * (1.0 - t) + b * t;

  static double _reaches(double gap, double span) =>
      1.0 - smoothstep(span - 0.5, span + 0.5, gap);

  @override
  Vector4? run(Float32List v, ShaderBindings b, FragmentContext c) {
    final scene = b.textures['scene_texture'];
    if (scene == null) return Vector4(0.0, 0.0, 0.0, 1.0);
    final centre = scene.sample(v[0], v[1]);
    final velocity = b.textures['velocity_texture'];
    final surface = b.textures['surface_texture'];
    final neighbors = b.textures['neighbor_texture'];
    if (velocity == null || surface == null || neighbors == null) {
      return centre;
    }

    final size = b.vec4('MotionBlurInfo', 'scene', Vector4.zero());
    final params = b.vec4('MotionBlurInfo', 'params', Vector4.zero());
    final tiles = b.vec4('MotionBlurInfo', 'tiles', Vector4.zero());

    final hereX = v[0] * size.z;
    final hereY = v[1] * size.w;
    final tileWidth = math.max(tiles.z, 1.0);
    final dominant = neighbors.sample(
      ((hereX / tileWidth).floorToDouble() + 0.5) / tiles.x,
      ((hereY / tileWidth).floorToDouble() + 0.5) / tiles.y,
    );
    final reach = math.sqrt(dominant.x * dominant.x + dominant.y * dominant.y);
    final samples = (params.w + 0.5).floor();
    if (reach <= 0.5 || samples < 1) {
      return centre;
    }

    double spanAt(double u, double w) {
      final motion = velocity.sample(u, w);
      return math.max(
        _halfMotion(motion.x, motion.y, params, params.z).length,
        0.5,
      );
    }

    final ownSpan = spanAt(v[0], v[1]);
    final ownDepth = _far(surface.sample(v[0], v[1]).w);
    final extent = math.max(tiles.w, 1e-4);
    final stride = 2.0 * reach / (samples + 1);

    final ownShare = math.min(math.max(stride, 1.0) / (2.0 * ownSpan), 1.0);
    final front = Vector3.zero();
    var frontCover = 0.0;
    final level = Vector3(centre.x, centre.y, centre.z) * ownShare;
    var levelCover = ownShare;
    final back = Vector3.zero();
    var backWeight = 0.0;

    final jitter = pixelNoise(b, c.coord.x, c.coord.y) - 0.5;
    final middle = (samples - 1) ~/ 2;
    for (var i = 0; i < 64 && i < samples; i++) {
      if (i == middle) continue;
      final t = -1.0 + 2.0 * ((i + jitter + 1.0) / (samples + 1));
      final thereX = (hereX + dominant.x * t).floorToDouble() + 0.5;
      final thereY = (hereY + dominant.y * t).floorToDouble() + 0.5;
      final atU = thereX * size.x;
      final atW = thereY * size.y;
      final gap = math.sqrt(
        (thereX - hereX) * (thereX - hereX) +
            (thereY - hereY) * (thereY - hereY),
      );

      final tapColor = scene.sample(atU, atW);
      final tap = Vector3(tapColor.x, tapColor.y, tapColor.z);
      final tapSpan = spanAt(atU, atW);
      final tapDepth = _far(surface.sample(atU, atW).w);

      final nearer = ((ownDepth - tapDepth) / extent).clamp(0.0, 1.0);
      final behind = ((tapDepth - ownDepth) / extent).clamp(0.0, 1.0);
      final share =
          _reaches(gap, tapSpan) * math.min(stride / (2.0 * tapSpan), 1.0);
      front.addScaled(tap, nearer * share);
      frontCover += nearer * share;
      level.addScaled(tap, (1.0 - nearer - behind) * share);
      levelCover += (1.0 - nearer - behind) * share;
      final nearness = behind / math.max(gap * gap, 1.0);
      back.addScaled(tap, nearness);
      backWeight += nearness;
    }

    final own = level / levelCover;
    final behindColor = backWeight > 0.0 ? back / backWeight : own;
    final under = _mix(behindColor, own, math.min(levelCover, 1.0));
    final over = frontCover > 0.0 ? front / frontCover : under;
    final blurred = _mix(under, over, math.min(frontCover, 1.0));
    return Vector4(blurred.x, blurred.y, blurred.z, centre.w);
  }
}
