/// The sky, gradient and cube-mapped: `sky.vert`, `sky_cube.vert`, `sky.frag`
/// and `sky_cube.frag`.
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:vector_math/vector_math.dart';

import 'cpu_shader.dart';
import 'cpu_shaders_color.dart';

/// `sky.vert`: a full-screen triangle at the far plane, carrying its own data.
///
/// **Everything the fragment stage needs arrives on the vertices, and it is not
/// this backend that needed that.** The GLSL this transcribes used to take a
/// matrix and a preset as uniform blocks; on Impeller those never reached the
/// sky's pipeline — see the note at the top of `sky.vert` for what was measured
/// — and a vertex attribute did. This backend could have kept reading uniforms
/// and been right on its own, which is exactly the kind of divergence that
/// makes a transcription stop being one.
///
/// The two constants that have to match the GLSL are the output depth 0.999999
/// — the far plane less a hair, so the ordinary `less` test passes against a
/// buffer cleared to 1.0 — and the layout below. `sky_frame_test.dart` pins the
/// depth against the text of the shader itself, because a drift between the two
/// is a sky that is either invisible or in front of the world.
final class SkyVertexShader implements CpuVertexShader {
  const SkyVertexShader();

  /// The ray, then the six vec4s of preset.
  @override
  int get varyingCount => 3 + 6 * 4;

  @override
  Vector4 run(Float32List a, ShaderBindings bindings, Float32List out) {
    // Attribute 0..1 is the clip-space corner; the rest is what the fragment
    // stage reads, passed straight through.
    for (var i = 0; i < varyingCount; i++) {
      out[i] = a[2 + i];
    }
    return Vector4(a[0], a[1], 0.999999, 1.0);
  }
}

/// `sky_cube.vert`: the same triangle, carrying a tint instead of a preset.
final class SkyCubeVertexShader implements CpuVertexShader {
  const SkyCubeVertexShader();

  @override
  int get varyingCount => 3 + 4;

  @override
  Vector4 run(Float32List a, ShaderBindings bindings, Float32List out) {
    for (var i = 0; i < varyingCount; i++) {
      out[i] = a[2 + i];
    }
    return Vector4(a[0], a[1], 0.999999, 1.0);
  }
}

/// `sky.frag`: the gradient, the scattering lobe and the disc.
///
/// Transcribed rather than shared with the engine's own copy of this model, and
/// that is the standing arrangement here: `flutter3d` is a dev dependency of
/// this package and not a dependency, because a software backend that needs the
/// engine to draw a triangle is not a backend. `tonemapNeutral` is the same
/// bargain. What keeps the two honest is a test that evaluates both.
final class SkyShader implements CpuFragmentShader {
  const SkyShader();

  @override
  Vector4? run(Float32List v, ShaderBindings b, FragmentContext c) {
    final length = math.sqrt(v[0] * v[0] + v[1] * v[1] + v[2] * v[2]);
    final scale = length > 0.0 ? 1.0 / length : 0.0;
    final dx = v[0] * scale;
    final dy = v[1] * scale;
    final dz = v[2] * scale;

    // The preset, off the varyings rather than out of a uniform block — see
    // [SkyVertexShader].
    final zenith = Vector4(v[3], v[4], v[5], v[6]);
    final horizon = Vector4(v[7], v[8], v[9], v[10]);
    final nadir = Vector4(v[11], v[12], v[13], v[14]);
    final sun = Vector4(v[15], v[16], v[17], v[18]);
    final glow = Vector4(v[19], v[20], v[21], v[22]);
    final disc = Vector4(v[23], v[24], v[25], v[26]);

    final height = dy.clamp(-1.0, 1.0);
    final far = height >= 0.0 ? zenith : nadir;
    final magnitude = height.abs();
    final t = magnitude * magnitude * (3.0 - 2.0 * magnitude);

    var r = horizon.x + (far.x - horizon.x) * t;
    var g = horizon.y + (far.y - horizon.y) * t;
    var bl = horizon.z + (far.z - horizon.z) * t;

    final towards = dx * sun.x + dy * sun.y + dz * sun.z;
    if (towards > 0.0) {
      final lobe = glow.w * math.pow(towards, sun.w).toDouble();
      r += glow.x * lobe;
      g += glow.y * lobe;
      bl += glow.z * lobe;
    }

    // `disc.y` is the width of the soft edge, not the outer cosine: see the
    // renderer, which writes it that way because a varying cannot carry two
    // cosines this close together.
    // A soft edge of nothing is a hard edge, not an absent sun — see the same
    // branch in `sky.frag`, which had the same hole.
    final edge =
        (disc.y > 0.0
            ? smoothstep(disc.x - disc.y, disc.x, towards)
            : (towards >= disc.x ? 1.0 : 0.0)) *
        disc.z;
    r += glow.x * edge;
    g += glow.y * edge;
    bl += glow.z * edge;

    // **The surface is left alone, and that is a transcription of a fix.** The
    // GLSL this mirrors used to declare a second output and write zero into it;
    // on Impeller, in the usual single-attachment pass, that killed the
    // process. Nothing is lost either way — the attachment is cleared to zero,
    // which is the value this was writing — and the two backends have to say
    // the same thing or the transcription stops being one.
    return Vector4(r, g, bl, 1.0);
  }
}

/// `sky_cube.frag`: the same ray, sampled out of a cube map.
///
/// The face table is `BoundTexture.sampleCube`'s, not this file's — written
/// once, where the conformance suite can check it against the other two
/// backends rather than against a reading of the code.
final class SkyCubeShader implements CpuFragmentShader {
  const SkyCubeShader();

  @override
  Vector4? run(Float32List v, ShaderBindings b, FragmentContext c) {
    // No surface written, for the reason [SkyShader] gives: the GLSL this
    // mirrors no longer declares a second output.
    final map = b.textures['sky_texture'];
    // A stage bound no cube: black rather than a crash, and black rather than a
    // plausible sky, which is what makes it reportable.
    if (map == null) return Vector4(0.0, 0.0, 0.0, 1.0);

    final texel = map.sampleCube(v[0], v[1], v[2]);
    // Off the varyings, as the preset is — see [SkyVertexShader].
    final tint = Vector4(v[3], v[4], v[5], v[6]);

    return Vector4(
      toLinear(texel.x) * tint.x,
      toLinear(texel.y) * tint.y,
      toLinear(texel.z) * tint.z,
      1.0,
    );
  }
}
