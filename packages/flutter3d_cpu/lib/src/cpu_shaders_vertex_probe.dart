/// The vertex-texture probe, transcribed. See `shaders/probe/vertex_texture.*`
/// and `checkVertexTextureSampling` in `flutter3d_conformance`.
///
/// **This backend's answer to the probe was never in doubt and is written down
/// anyway.** The question is whether a vertex stage can sample a texture, and
/// here a vertex stage is a Dart function handed the same [ShaderBindings] as a
/// fragment one — textures included. So the answer is yes because somebody
/// wrote these twenty lines, which is a different kind of yes from the one a
/// driver gives, and the conformance suite records both rather than reasoning
/// from one to the other.
library;

import 'dart:typed_data';

import 'package:vector_math/vector_math.dart';

import 'cpu_shader.dart';

/// `probe/vertex_texture.vert`: sample, and pass what was sampled through.
final class VertexTextureProbeVertexShader implements CpuVertexShader {
  const VertexTextureProbeVertexShader();

  @override
  int get varyingCount => 4;

  @override
  Vector4 run(Float32List a, ShaderBindings bindings, Float32List out) {
    final at = bindings.vec4('ProbeInfo', 'at', Vector4.zero());
    final texture = bindings.textures['probe_texture'];
    // Zeros when nothing is bound, which is what a compiled shader reading an
    // unbound sampler gets and what the check reads as "the draw landed and
    // the texture did not".
    final sampled = texture == null
        ? Vector4.zero()
        : texture.sample(at.x, at.y);
    out[0] = sampled.x;
    out[1] = sampled.y;
    out[2] = sampled.z;
    out[3] = sampled.w;
    return Vector4(a[0], a[1], a[2], 1.0);
  }
}

/// `probe/vertex_texture.frag`: what the vertex stage sampled, unchanged.
final class VertexTextureProbeShader implements CpuFragmentShader {
  const VertexTextureProbeShader();

  @override
  Vector4? run(Float32List v, ShaderBindings b, FragmentContext c) =>
      Vector4(v[0], v[1], v[2], v[3]);
}
