/// The reactive mask, on the software rasteriser — `R4`.
///
/// `post/reactive.frag` and `post/reactive_sprite.frag` line for line: how
/// much of a pixel a blended surface, a particle or a splat covers, written
/// into blue for the temporal resolve to keep less history by, and nothing
/// written behind what the opaque scene drew there.
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:vector_math/vector_math.dart';

import 'cpu_shader.dart';
import 'cpu_shaders_color.dart';

const String _block = 'ReactiveInfo';

/// Whether a fragment [depth] along the camera's axis lies behind what the
/// surface buffer holds at [c]'s pixel — the test both stages share.
bool _hidden(ShaderBindings b, FragmentContext c, double depth) {
  final surface = b.textures['surface_texture'];
  if (surface == null) return false;
  final target = b.vec4(_block, 'target', Vector4.zero());
  // `FragCoordFromTop`.
  final y = target.z > 0.0 ? target.z - c.coord.y : c.coord.y;
  final stored = surface.sample(c.coord.x * target.x, y * target.y).w;
  return stored > 0.0 && depth > stored * (1.0 + target.w) + 1e-3;
}

/// `post/reactive.frag`: a blended surface, drawn through the velocity
/// vertex stages — `v_depth` is varying eight.
final class ReactiveShader implements CpuFragmentShader {
  const ReactiveShader();

  @override
  Vector4? run(Float32List v, ShaderBindings b, FragmentContext c) {
    final params = b.vec4(_block, 'params', Vector4.zero());
    final coverage = params.x * params.z;
    if (_hidden(b, c, v[8]) || coverage <= 0.0) return null;
    return Vector4(0.0, 0.0, coverage, 0.0);
  }
}

/// `post/reactive_sprite.frag`: a particle or a splat, through
/// `particle.vert` — colour in 0..3, the quad's coordinates in 4..5, the
/// world position in 6..8.
final class ReactiveSpriteShader implements CpuFragmentShader {
  const ReactiveSpriteShader();

  @override
  Vector4? run(Float32List v, ShaderBindings b, FragmentContext c) {
    // `texture()` picks its level from the screen derivatives, so the sprite
    // is read through its chain here too, from the footprint of varyings four
    // and five the way `ParticleTexturedShader` reads it for colour.
    final sprite = b.textures['sprite_texture'];
    final ddx = c.ddx;
    final ddy = c.ddy;
    final (du, dv) = ddx != null && ddy != null
        ? (
            math.max(ddx[4].abs(), ddy[4].abs()),
            math.max(ddx[5].abs(), ddy[5].abs()),
          )
        : (0.0, 0.0);
    final spriteAlpha = sprite?.sample(v[4], v[5], du: du, dv: dv).w ?? 1.0;

    final cx = v[4] * 2.0 - 1.0;
    final cy = v[5] * 2.0 - 1.0;
    final falloff = 1.0 - smoothstep(0.0, 1.0, math.sqrt(cx * cx + cy * cy));
    final disc = falloff * falloff;

    final power = -0.5 * (v[4] * v[4] + v[5] * v[5]);
    final gaussian = power < -4.5 ? 0.0 : math.exp(power);

    final params = b.vec4(_block, 'params', Vector4.zero());
    final shape = params.y;
    final coverage =
        v[3] *
        (shape < 0.5
            ? disc
            : shape < 1.5
            ? gaussian
            : spriteAlpha);

    final eye = b.vec4(_block, 'eye', Vector4.zero());
    final forward = b.vec4(_block, 'forward', Vector4.zero());
    final depth =
        (v[6] - eye.x) * forward.x +
        (v[7] - eye.y) * forward.y +
        (v[8] - eye.z) * forward.z;
    final reactive = params.x * coverage;
    if (_hidden(b, c, depth) || reactive <= 0.0) return null;
    return Vector4(0.0, 0.0, reactive, 0.0);
  }
}
