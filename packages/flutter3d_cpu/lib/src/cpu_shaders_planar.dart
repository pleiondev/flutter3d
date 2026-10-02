/// `P4`'s two stages: `planar_reflection.frag`, which lays a mirrored picture
/// over a reflector's surface, and `render_texture_encode.frag`, which turns
/// what a camera into a texture saw into sRGB bytes.
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:vector_math/vector_math.dart';

import 'cpu_shader.dart';
import 'cpu_shaders_color.dart';
import 'cpu_shaders_layout.dart';

/// `planar_reflection.frag`: the texel of the reflection under this pixel,
/// by its place in the view, weighted by Schlick's Fresnel and fogged.
///
/// Writes no surface: the GLSL declares `F3D_NO_SURFACE_BUFFER`, and the
/// surface underneath keeps describing itself, as under `XrayShader`.
final class PlanarReflectionShader implements CpuFragmentShader {
  const PlanarReflectionShader();

  @override
  Vector4? run(Float32List v, ShaderBindings b, FragmentContext c) {
    final picture = b.textures['reflection_texture'];
    if (picture == null) return Vector4.zero();
    final view = b.vec4('PlanarReflectionInfo', 'view', Vector4(0, 0, 1, 1));
    final params = b.vec4('PlanarReflectionInfo', 'params', Vector4.zero());
    final tint = b.vec4('PlanarReflectionInfo', 'tint', Vector4.zero());

    // `FragCoordFromTop`, and the texture's rows turned back where its first
    // row is the bottom of the picture.
    final rows = params.z;
    final pixelY = rows > 0.0 ? rows - c.coord.y : c.coord.y;
    final u = (c.coord.x - view.x) / view.z;
    final top = (pixelY - view.y) / view.w;
    final texel = picture.sample(u, rows > 0.0 ? 1.0 - top : top);
    final reflected = Vector3(
      texel.x * tint.x,
      texel.y * tint.y,
      texel.z * tint.z,
    );

    final normal = Vector3(v[kVNormal], v[kVNormal + 1], v[kVNormal + 2])
      ..normalize();
    if (!c.frontFacing) normal.negate();
    final eye = b.vec4('FogInfo', 'eye', Vector4.zero());
    final toEye = Vector3(
      eye.x - v[kVWorld],
      eye.y - v[kVWorld + 1],
      eye.z - v[kVWorld + 2],
    )..normalize();
    final cosine = normal.dot(toEye).clamp(0.0, 1.0);
    final f0 = params.x;
    final grazing = 1.0 - cosine;
    final grazing2 = grazing * grazing;
    final fresnel = f0 + (1.0 - f0) * grazing2 * grazing2 * grazing;
    final alpha = (fresnel * params.y).clamp(0.0, 1.0);

    final fogged = applyFog(reflected, v, b);
    return Vector4(fogged.x * alpha, fogged.y * alpha, fogged.z * alpha, alpha);
  }
}

/// `render_texture_encode.frag`: the light times the exposure, clipped to
/// one and encoded as sRGB.
final class RenderTextureEncodeShader implements CpuFragmentShader {
  const RenderTextureEncodeShader();

  @override
  Vector4? run(Float32List v, ShaderBindings b, FragmentContext c) {
    final source = b.textures['source_texture'];
    if (source == null) return Vector4(0.0, 0.0, 0.0, 1.0);
    final params = b.vec4('RenderTextureInfo', 'params', Vector4.zero());
    final exposure = params.x;
    // Turned over where the backend draws its first row at the bottom; this
    // one draws it at the top and never is.
    final light = source.sample(v[0], params.y > 0.5 ? 1.0 - v[1] : v[1]);
    double encode(double channel) =>
        toSrgb(math.min(math.max(channel * exposure, 0.0), 1.0));
    return Vector4(encode(light.x), encode(light.y), encode(light.z), 1.0);
  }
}
