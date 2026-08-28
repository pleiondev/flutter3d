/// The fullscreen-quad vertex stage and the passes that composite the frame:
/// `composite.frag`, which adds bloom and ambient occlusion and tone maps, and
/// `mrt_probe.frag`, which exists only to prove a backend writes a second
/// attachment.
///
/// Screen-space effects that *read* the surface buffer — `ssao.frag` and
/// `reflections.frag` — are `cpu_shaders_screenspace.dart`: a different
/// concern, marching rays rather than compositing layers.
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:vector_math/vector_math.dart';

import 'cpu_shader.dart';
import 'cpu_shaders_color.dart';

/// `fullscreen.vert`.
///
/// The uv is an attribute, not something derived from the position. Deriving
/// it — which the first version did — puts the composite's sampling a flip
/// away from the engine's on any backend whose framebuffer disagrees, and
/// there is no way to see that in a fixture whose picture is roughly
/// symmetric.
final class FullscreenVertexShader implements CpuVertexShader {
  const FullscreenVertexShader();

  @override
  int get varyingCount => 2;

  @override
  Vector4 run(Float32List a, ShaderBindings bindings, Float32List out) {
    out[0] = a[2];
    out[1] = a[3];
    return Vector4(a[0], a[1], 0.0, 1.0);
  }
}

/// `composite.frag`: add the bloom, expose, tone map, encode.
final class CompositeShader implements CpuFragmentShader {
  const CompositeShader();

  @override
  Vector4? run(Float32List v, ShaderBindings bindings, FragmentContext c) {
    final scene = bindings.textures['scene_texture'];
    if (scene == null) return Vector4(0.0, 0.0, 0.0, 1.0);
    final params = bindings.vec4(
      'CompositeInfo',
      'params',
      Vector4(1.0, 0.0, 1.0, 0.0),
    );

    final look = bindings.vec4(
      'CompositeInfo',
      'look',
      Vector4(1.0, 1.0, 0.0, 0.0),
    );
    final lookMore = bindings.vec4(
      'CompositeInfo',
      'look_more',
      Vector4(0.0, 0.0, 0.0, 1.0),
    );

    // Dispersion at sampling, because that is where a lens does it — see the
    // note in `composite.frag`, which this mirrors operation for operation.
    final sampled = scene.sample(v[0], v[1]);
    var colour = Vector3(sampled.x, sampled.y, sampled.z);
    if (look.w > 0.0) {
      final ox = (v[0] - 0.5) * look.w;
      final oy = (v[1] - 0.5) * look.w;
      colour.x = scene.sample(v[0] + ox, v[1] + oy).x;
      colour.z = scene.sample(v[0] - ox, v[1] - oy).z;
    }

    // Occlusion first, then the glow — the order matters and it is the order
    // `composite.frag` uses. Four taps in a 2×2, sized to the artefact rather
    // than tuned against it: the occlusion pass rotates its kernel by the
    // parity of the pixel, and this averages exactly that pattern away.
    //
    // Applied to the scene and **not** to the glow, so a lit crack in a corner
    // keeps glowing. Adding the bloom first and scaling both — which is what
    // the first draft of this function did — dims the one thing in a dark
    // corner that should not dim.
    final ao = bindings.textures['ao_texture'];
    final strength = params.w.clamp(0.0, 1.0);
    if (ao != null && strength > 0.0) {
      final texel = bindings.vec4('CompositeInfo', 'ao_texel', Vector4.zero());
      final hx = texel.x * 0.5;
      final hy = texel.y * 0.5;
      final occlusion =
          0.25 *
          (ao.sample(v[0] + hx, v[1] + hy).x +
              ao.sample(v[0] - hx, v[1] + hy).x +
              ao.sample(v[0] + hx, v[1] - hy).x +
              ao.sample(v[0] - hx, v[1] - hy).x);
      colour.scale(1.0 + (occlusion - 1.0) * strength);
    }

    // Additive, and unconditional: the engine binds a black texture when bloom
    // is off rather than leaving the sampler unbound, so there is no branch to
    // make here either.
    final bloom = bindings.textures['bloom_texture'];
    if (bloom != null) {
      final b = bloom.sample(v[0], v[1]);
      colour += Vector3(b.x, b.y, b.z) * params.y;
    }

    colour.scale(math.max(params.x, 0.0));
    if (params.z > 0.5) colour = tonemapNeutral(colour);

    // Grading after the tone map, then the barrel, then the film. The order is
    // the one a camera imposes and it is the order `composite.frag` uses; the
    // two are compared by thirty golden images and have to agree.
    colour = Vector3(
      (colour.x - 0.5) * look.x + 0.5,
      (colour.y - 0.5) * look.x + 0.5,
      (colour.z - 0.5) * look.x + 0.5,
    );
    final luma = 0.2126 * colour.x + 0.7152 * colour.y + 0.0722 * colour.z;
    colour = Vector3(
      luma + (colour.x - luma) * look.y,
      luma + (colour.y - luma) * look.y,
      luma + (colour.z - luma) * look.y,
    );
    colour.x *= 1.0 + look.z * 0.1;
    colour.z *= 1.0 - look.z * 0.1;

    if (lookMore.x > 0.0) {
      final aspect = math.max(lookMore.w, 1e-4);
      final fx = (v[0] - 0.5) * (1.0 + (aspect - 1.0) * lookMore.y);
      final fy = v[1] - 0.5;
      final radius = (math.sqrt(fx * fx + fy * fy) * 1.41421356).clamp(
        0.0,
        1.0,
      );
      colour.scale(1.0 - lookMore.x * radius);
    }

    if (lookMore.z > 0.0) {
      // **Not bit-identical to the GPU's, and it cannot be.** The hash is a
      // sine of a large product, so single and double precision diverge in the
      // fraction this keeps. The two golden sets are independent for exactly
      // this class of difference; what has to match is the shape of the noise,
      // not the bits.
      final noise = _hash(c.coord.x, c.coord.y) - 0.5;
      final amount = noise * lookMore.z;
      colour = Vector3(colour.x + amount, colour.y + amount, colour.z + amount);
    }

    return Vector4(
      toSrgb(math.max(colour.x, 0.0)),
      toSrgb(math.max(colour.y, 0.0)),
      toSrgb(math.max(colour.z, 0.0)),
      sampled.w,
    );
  }
}

/// `Hash` from `composite.frag`: a value in [0, 1) from a screen position.
///
/// Static by construction — no frame counter, so a golden is the same on every
/// run. `LookSettings.grain` says the same thing from the other side.
double _hash(double x, double y) {
  final t = math.sin(x * 12.9898 + y * 78.233) * 43758.5453;
  return t - t.floorToDouble();
}

/// `mrt_probe.frag`: two constants into two attachments.
///
/// It exists to answer whether a backend writes the second target at all, so
/// there is nothing to get right here except writing both.
final class MrtProbeShader implements CpuFragmentShader {
  const MrtProbeShader();

  @override
  Vector4? run(Float32List v, ShaderBindings b, FragmentContext c) {
    c.surface = Vector4(0.75, 0.5, 0.25, 1.0);
    return Vector4(0.25, 0.5, 0.75, 1.0);
  }
}
