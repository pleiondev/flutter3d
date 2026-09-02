/// `probe_prefilter.frag`: one face of one level of a reflection probe,
/// convolved from the captured cube.
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:vector_math/vector_math.dart';

import 'cpu_shader.dart';

/// The direction the texel at ([s], [t]) of [face] looks along, with `t`
/// measured down the face from row zero.
///
/// The cube-map table inverted — the same six cases `probe_prefilter.frag`
/// spells out and `EnvironmentMap` uses on the host — and it has to stay the
/// inverse of `BoundTexture.sampleCube`'s addressing: a face written from
/// directions its own sampler does not produce is a cube with six seams.
Vector3 probeFaceDirection(int face, double s, double t) {
  final u = s * 2.0 - 1.0;
  final v = t * 2.0 - 1.0;
  return switch (face) {
    0 => Vector3(1.0, -v, -u),
    1 => Vector3(-1.0, -v, u),
    2 => Vector3(u, 1.0, v),
    3 => Vector3(u, -1.0, -v),
    4 => Vector3(u, -v, 1.0),
    _ => Vector3(-u, -v, -1.0),
  }..normalize();
}

/// `probe_prefilter.frag`.
///
/// Read against the GLSL rather than against `EnvironmentMap._convolve`,
/// which is the same arithmetic on the host: this is the transcription the
/// cross-backend comparison of `probe-car` rests on, and a transcription of a
/// transcription is one drift further from the thing it stands for.
final class ProbePrefilterShader implements CpuFragmentShader {
  const ProbePrefilterShader();

  @override
  Vector4? run(Float32List v, ShaderBindings b, FragmentContext c) {
    final capture = b.textures['capture_texture'];
    // No cube bound: black rather than a crash, and black rather than a
    // plausible reflection, which is what makes it reportable.
    if (capture == null) return Vector4(0.0, 0.0, 0.0, 1.0);

    final params = b.vec4('ProbeInfo', 'params', Vector4.zero());
    final face = (params.x + 0.5).floor();
    final roughness = params.y;
    final lod = params.z;
    final samples = (params.w + 0.5).floor().clamp(1, 128);

    final axis = probeFaceDirection(face, v[0], v[1]);

    if (samples == 1) {
      final texel = capture.sampleCube(axis.x, axis.y, axis.z, lod);
      return Vector4(texel.x, texel.y, texel.z, 1.0);
    }

    final alpha = math.max(roughness * roughness, 1e-3);
    final power = 2.0 / (alpha * alpha) - 2.0;

    final up = axis.z.abs() < 0.999
        ? Vector3(0.0, 0.0, 1.0)
        : Vector3(1.0, 0.0, 0.0);
    final right = up.cross(axis)..normalize();
    final ahead = axis.cross(right);

    final golden = math.pi * (3.0 - math.sqrt(5.0));
    var r = 0.0;
    var g = 0.0;
    var bl = 0.0;
    var weight = 0.0;
    for (var i = 0; i < samples; i++) {
      final z = 1.0 - (i + 0.5) / samples;
      final radius = math.sqrt(math.max(1.0 - z * z, 0.0));
      final theta = golden * i;
      final spread = math.pow(z, 1.0 / (power + 1.0)).toDouble();
      final tap = Vector3(
        radius * math.cos(theta) * (1.0 - spread),
        radius * math.sin(theta) * (1.0 - spread),
        spread,
      )..normalize();
      final dir = right * tap.x + ahead * tap.y + axis * tap.z;
      final cosine = dir.dot(axis);
      if (cosine <= 0.0) continue;
      final texel = capture.sampleCube(dir.x, dir.y, dir.z, lod);
      r += texel.x * cosine;
      g += texel.y * cosine;
      bl += texel.z * cosine;
      weight += cosine;
    }

    final scale = weight > 0.0 ? 1.0 / weight : 0.0;
    return Vector4(r * scale, g * scale, bl * scale, 1.0);
  }
}
