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

/// `motion_blur.frag`: the reconstruction gather along each neighbourhood's
/// dominant motion and each pixel's own.
final class MotionBlurShader implements CpuFragmentShader {
  const MotionBlurShader();

  static double _far(double depth) => depth <= 0.0 ? 1e9 : depth;

  static double _cone(double gap, double span) =>
      (1.0 - gap / span).clamp(0.0, 1.0);

  static double _cylinder(double gap, double span) =>
      1.0 - smoothstep(0.95 * span, 1.05 * span, gap);

  /// `Along`: how far a motion of [span] pixels runs along the unit line
  /// ([lineX], [lineY]).
  static double _along(
    Vector2 motion,
    double span,
    double lineX,
    double lineY,
  ) => span < 0.5 ? 1.0 : ((motion.x * lineX + motion.y * lineY) / span).abs();

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
    final pixelX = c.coord.x;
    final pixelY = c.coord.y;
    final tileWidth = math.max(tiles.z, 1.0);
    final nudgeX = pixelNoise(b, pixelX + 2.0, pixelY + 1.0) - 0.5;
    final nudgeY = pixelNoise(b, pixelX + 1.0, pixelY + 3.0) - 0.5;
    final tileX = ((hereX + nudgeX * 0.5 * tileWidth) / tileWidth)
        .floorToDouble()
        .clamp(0.0, math.max(tiles.x - 1.0, 0.0));
    final tileY = ((hereY + nudgeY * 0.5 * tileWidth) / tileWidth)
        .floorToDouble()
        .clamp(0.0, math.max(tiles.y - 1.0, 0.0));
    final dominant = neighbors.sample(
      (tileX + 0.5) / tiles.x,
      (tileY + 0.5) / tiles.y,
    );
    final samples = (params.w + 0.5).floor();
    final reachFar = math.sqrt(
      dominant.x * dominant.x + dominant.y * dominant.y,
    );
    if (reachFar <= 0.5 || samples < 1) {
      return centre;
    }

    Vector2 motionAt(double u, double w) {
      final motion = velocity.sample(u, w);
      return _halfMotion(motion.x, motion.y, params, params.z);
    }

    final own = motionAt(v[0], v[1]);
    final ownLength = own.length;
    final ownSpan = math.max(ownLength, 0.5);
    final ownDepth = _far(surface.sample(v[0], v[1]).w);
    final extent = math.max(tiles.w, 1e-4);

    final acrossX = dominant.x / reachFar;
    final acrossY = dominant.y / reachFar;
    final flip = -acrossY * own.x + acrossX * own.y < 0.0 ? -1.0 : 1.0;
    final sideX = -acrossY * flip;
    final sideY = acrossX * flip;
    final ownLineX = ownLength > 1e-6 ? own.x / ownLength : sideX;
    final ownLineY = ownLength > 1e-6 ? own.y / ownLength : sideY;
    final turn = ((ownLength - 0.5) / 1.5).clamp(0.0, 1.0);
    final mixedX = sideX + (ownLineX - sideX) * turn;
    final mixedY = sideY + (ownLineY - sideY) * turn;
    final mixedLength = math.sqrt(mixedX * mixedX + mixedY * mixedY);
    final mineX = mixedX / mixedLength;
    final mineY = mixedY / mixedLength;

    var weight = samples / (40.0 * ownSpan);
    var totalX = centre.x * weight;
    var totalY = centre.y * weight;
    var totalZ = centre.z * weight;

    final jitter = pixelNoise(b, pixelX, pixelY) - 0.5;
    for (var i = 0; i < 64 && i < samples; i++) {
      final onMine = i % 2 == 1;
      final lineX = onMine ? mineX : acrossX;
      final lineY = onMine ? mineY : acrossY;
      final t = -1.0 + 2.0 * ((i + jitter + 1.0) / (samples + 1));
      final thereX = (hereX + lineX * (t * reachFar)).floorToDouble() + 0.5;
      final thereY = (hereY + lineY * (t * reachFar)).floorToDouble() + 0.5;
      final atU = thereX * size.x;
      final atW = thereY * size.y;
      final gap = math.sqrt(
        (thereX - hereX) * (thereX - hereX) +
            (thereY - hereY) * (thereY - hereY),
      );

      final tap = scene.sample(atU, atW);
      final tapMotion = motionAt(atU, atW);
      final tapLength = tapMotion.length;
      final tapSpan = math.max(tapLength, 0.5);
      final tapDepth = _far(surface.sample(atU, atW).w);

      final ownAlong = (mineX * lineX + mineY * lineY).abs();
      final tapAlong = _along(tapMotion, tapLength, lineX, lineY);

      final front = (1.0 - (tapDepth - ownDepth) / extent).clamp(0.0, 1.0);
      final back = (1.0 - (ownDepth - tapDepth) / extent).clamp(0.0, 1.0);
      final reach =
          front * _cone(gap, tapSpan) * tapAlong +
          back * _cone(gap, ownSpan) * ownAlong +
          _cylinder(gap, tapSpan) *
              _cylinder(gap, ownSpan) *
              math.max(ownAlong, tapAlong) *
              2.0;
      totalX += tap.x * reach;
      totalY += tap.y * reach;
      totalZ += tap.z * reach;
      weight += reach;
    }

    return Vector4(totalX / weight, totalY / weight, totalZ / weight, centre.w);
  }
}
