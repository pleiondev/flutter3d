/// The six lighting models — `unlit.frag` through `toon.frag` — each reading
/// a [Surface], applying its own maps, and shading it with
/// `cpu_shaders_lighting.dart`'s `accumulateLights`.
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:vector_math/vector_math.dart';

import 'cpu_shader.dart';
import 'cpu_shaders_color.dart';
import 'cpu_shaders_lighting.dart';
import 'cpu_shaders_surface.dart';

/// `unlit.frag`: the albedo, written into the HDR target as light.
final class UnlitShader implements CpuFragmentShader {
  const UnlitShader();

  @override
  Vector4? run(Float32List v, ShaderBindings bindings, FragmentContext c) {
    final s = readSurface(v, bindings, c);
    if (s == null) return null;
    // Fully rough, which is what WriteSurface's one-argument form means: a
    // surface that cannot say how polished it is should not be reflected off.
    return writeLit(
      c,
      v,
      bindings,
      colour: s.albedo,
      alpha: s.alpha,
      normal: s.normal,
      roughness: 1.0,
    );
  }
}

/// `xray.frag`: the same albedo, and not one word about the surface.
///
/// The whole of what makes it a second shader is what it does NOT do —
/// [FragmentContext.surface] is left null, so `cpu_encoder.dart` writes
/// nothing to attachment one. The GLSL says it with `#define
/// F3D_NO_SURFACE_BUFFER`, which compiles `WriteSurfaceGeometry` away; here
/// the transcription is `writeLit` without the `writeSurface` half, which is
/// `applyFog` and the alpha.
///
/// **Not a call to [UnlitShader] with the surface cleared afterwards.** That
/// would work and would read as a tidy-up rather than as the point: a
/// silhouette is drawn where its node is *behind* what the depth buffer holds,
/// so anything it wrote to the surface buffer would describe geometry that is
/// not visible — and SSAO and reflections read that buffer as the nearest
/// surface. See `renderer_xray_pass.dart`.
final class XrayShader implements CpuFragmentShader {
  const XrayShader();

  @override
  Vector4? run(Float32List v, ShaderBindings bindings, FragmentContext c) {
    final s = readSurface(v, bindings, c);
    // Discarded under a mask cutoff, exactly as every other model here is: a
    // silhouette must have the holes the thing it stands for has.
    if (s == null) return null;
    final fogged = applyFog(s.albedo, v, bindings);
    return Vector4(fogged.x, fogged.y, fogged.z, s.alpha);
  }
}

/// `lambert.frag`: pure diffuse, the cheapest model that still reads as
/// three-dimensional.
final class LambertShader implements CpuFragmentShader {
  const LambertShader();

  @override
  Vector4? run(Float32List v, ShaderBindings b, FragmentContext c) {
    final s = readSurface(v, b, c);
    if (s == null) return null;
    // No ORM map: a purely diffuse model has no response to metallic or
    // roughness, so sampling it would leave a slot the compiler then drops.
    applyCommonMaps(s, v, b, c);
    final lit = accumulateLights(
      s,
      b,
      c,
      shade: (s, light) => s.albedo,
      shadowed: true,
    ).scaled(s.occlusion);
    final ambient =
        (s.albedo.clone()..multiply(s.ambient + sampleLightmap(v, b, c)))
            .scaled(s.occlusion);
    final total = lit + ambient + s.emissive;
    return writeLit(
      c,
      v,
      b,
      colour: total,
      alpha: s.alpha,
      normal: s.normal,
      roughness: s.roughness,
    );
  }
}

/// `blinn_phong.frag`: a Phong highlight on top of the albedo.
final class BlinnPhongShader implements CpuFragmentShader {
  const BlinnPhongShader();

  @override
  Vector4? run(Float32List v, ShaderBindings b, FragmentContext c) {
    final s = readSurface(v, b, c);
    if (s == null) return null;
    applyCommonMaps(s, v, b, c);
    // Roughness drives the exponent, so the ORM map does reach the output.
    applyMetallicRoughnessMap(s, v, b, c);
    final specularStrength = b.vec4('FragInfo', 'material', Vector4.zero()).w;

    final lit = accumulateLights(
      s,
      b,
      c,
      shadowed: true,
      shade: (s, light) {
        // Perceptual roughness onto a Phong exponent. The mapping is arbitrary;
        // it only has to feel monotonic as the slider moves.
        final shininess = 256.0 + (4.0 - 256.0) * s.roughness;
        final specular =
            math.pow(light.nDotH, shininess).toDouble() * specularStrength;
        return Vector3(
          s.albedo.x + specular,
          s.albedo.y + specular,
          s.albedo.z + specular,
        );
      },
    ).scaled(s.occlusion);

    final ambient =
        (s.albedo.clone()..multiply(s.ambient + sampleLightmap(v, b, c)))
            .scaled(s.occlusion);
    final total = lit + ambient + s.emissive;
    return writeLit(
      c,
      v,
      b,
      colour: total,
      alpha: s.alpha,
      normal: s.normal,
      roughness: s.roughness,
    );
  }
}

/// `pbr.frag`: Cook-Torrance with GGX, height-correlated Smith, Schlick.
///
/// Formulations follow Filament, which is what the glTF spec describes, so an
/// imported material lands on the same look. Image-based lighting is here when
/// a scene supplies an environment: `frame_params.w` carries the cube's level
/// count and is zero when there is none, and the flat hemispheric ambient
/// stands in then. Operation for operation with `pbr.frag`, because thirty
/// golden images compare the two.
/// `EnvBrdfApprox` from `pbr.frag`: the split-sum BRDF as arithmetic.
///
/// Karis' analytic fit, in place of the 2D lookup table this would otherwise
/// need. What it buys is a third texture that would have to be built, bound on
/// every backend, and mirrored here — for a difference visible only on a
/// grazing mirror. Returns the scale and bias to apply to F0.
Vector2 _envBrdfApprox(double roughness, double nDotV) {
  final rx = roughness * -1.0 + 1.0;
  final ry = roughness * -0.0275 + 0.0425;
  final rz = roughness * -0.572 + 1.04;
  final rw = roughness * 0.022 - 0.04;
  final a004 =
      math.min(rx * rx, math.pow(2.0, -9.28 * nDotV).toDouble()) * rx + ry;
  return Vector2(-1.04 * a004 + rz, 1.04 * a004 + rw);
}

final class PbrShader implements CpuFragmentShader {
  const PbrShader();

  static const double _pi = 3.141592653589793;

  static double _dGgx(double nDotH, double alpha) {
    final a = nDotH * alpha;
    final k = alpha / math.max(1.0 - nDotH * nDotH + a * a, 1e-6);
    return k * k * (1.0 / _pi);
  }

  static double _vSmith(double nDotV, double nDotL, double alpha) {
    final a2 = alpha * alpha;
    final lambdaV = nDotL * math.sqrt(nDotV * nDotV * (1.0 - a2) + a2);
    final lambdaL = nDotV * math.sqrt(nDotL * nDotL * (1.0 - a2) + a2);
    return 0.5 / math.max(lambdaV + lambdaL, 1e-5);
  }

  static Vector3 _fSchlick(Vector3 f0, double vDotH) {
    final f = math.pow(1.0 - vDotH, 5.0).toDouble();
    return Vector3(
      f0.x + (1.0 - f0.x) * f,
      f0.y + (1.0 - f0.y) * f,
      f0.z + (1.0 - f0.z) * f,
    );
  }

  @override
  Vector4? run(Float32List v, ShaderBindings b, FragmentContext c) {
    final s = readSurface(v, b, c);
    if (s == null) return null;
    applyCommonMaps(s, v, b, c);
    applyMetallicRoughnessMap(s, v, b, c);
    final specularStrength = b.vec4('FragInfo', 'material', Vector4.zero()).w;

    final lit = accumulateLights(
      s,
      b,
      c,
      shadowed: true,
      shade: (s, light) {
        // Perceptual roughness squared is the GGX alpha; this is what makes the
        // roughness slider feel linear.
        final alpha = s.roughness * s.roughness;

        // Dielectrics reflect about four percent head-on; metals tint the
        // reflection with their albedo and have no diffuse response.
        final f0 = Vector3(
          0.04 + (s.albedo.x - 0.04) * s.metallic,
          0.04 + (s.albedo.y - 0.04) * s.metallic,
          0.04 + (s.albedo.z - 0.04) * s.metallic,
        );
        final diffuseColour = s.albedo * (1.0 - s.metallic);

        final d = _dGgx(light.nDotH, alpha);
        final vis = _vSmith(s.nDotV, light.nDotL, alpha);
        final f = _fSchlick(f0, light.vDotH);

        final specular = f * (d * vis * specularStrength);
        // Energy left over after reflection is what scatters diffusely.
        final diffuse = Vector3(
          diffuseColour.x * (1.0 - f.x) / _pi,
          diffuseColour.y * (1.0 - f.y) / _pi,
          diffuseColour.z * (1.0 - f.z) / _pi,
        );
        // The pi puts the result back on the scale the tone mapper and the
        // exposure default were calibrated against.
        return (diffuse + specular)..scale(_pi);
      },
    ).scaled(s.occlusion);

    // Occlusion darkens indirect light, and is applied to the direct term too.
    // Not physical; with no IBL the flat ambient is far too weak for an
    // occlusion map to be visible otherwise.
    final metallic = s.metallic.clamp(0.0, 1.0);
    final diffuseColour = s.albedo * (1.0 - metallic);
    var ambient = (diffuseColour.clone()..multiply(s.ambient)).scaled(
      s.occlusion,
    );

    final levels = b.vec4('FragInfo', 'frame_params', Vector4.zero()).w;
    final environment = b.textures['environment_texture'];
    if (levels > 0.0 && environment != null) {
      // The term that made metal black: a metal has no diffuse response, so
      // with nothing to reflect it was lit by direct light alone.
      final f0 =
          Vector3(0.04, 0.04, 0.04) +
          (s.albedo - Vector3(0.04, 0.04, 0.04)) * metallic;
      // reflect(-v, n) = 2(n·v)n - v, with v already the direction to the eye.
      final nDotV = s.normal.dot(s.view);
      final reflected = s.normal * (2.0 * nDotV) - s.view;

      final irradiance = environment.sampleCube(
        s.normal.x,
        s.normal.y,
        s.normal.z,
        levels,
      );
      final prefiltered = environment.sampleCube(
        reflected.x,
        reflected.y,
        reflected.z,
        s.roughness * levels,
      );
      final ab = _envBrdfApprox(s.roughness, math.max(nDotV, 0.0));

      final strength = b.vec4('FragInfo', 'material', Vector4.zero()).z;
      final diffusePart = diffuseColour.clone()
        ..multiply(Vector3(irradiance.x, irradiance.y, irradiance.z));
      final specularPart = Vector3(prefiltered.x, prefiltered.y, prefiltered.z)
        ..multiply(f0 * ab.x + Vector3(ab.y, ab.y, ab.y));
      ambient = ((diffusePart + specularPart) * strength).scaled(s.occlusion);
    }
    // The baked bounce light, diffuse only, as `pbr.frag` adds it.
    ambient += (diffuseColour.clone()..multiply(sampleLightmap(v, b, c)))
        .scaled(s.occlusion);

    final total = lit + ambient + s.emissive;
    return writeLit(
      c,
      v,
      b,
      colour: total,
      alpha: s.alpha,
      normal: s.normal,
      roughness: s.roughness,
    );
  }
}

/// `toon.frag`: the diffuse response quantised into bands, plus a rim term.
final class ToonShader implements CpuFragmentShader {
  const ToonShader();

  @override
  Vector4? run(Float32List v, ShaderBindings b, FragmentContext c) {
    final s = readSurface(v, b, c);
    if (s == null) return null;
    applyCommonMaps(s, v, b, c);
    // Roughness sets the band count, so the ORM map matters here too.
    applyMetallicRoughnessMap(s, v, b, c);

    final lit = accumulateLights(
      s,
      b,
      c,
      shadowed: true,
      shade: (s, light) {
        // Fewer bands as roughness rises, so the slider still does something.
        final bands = 5.0 + (2.0 - 5.0) * s.roughness;
        var quantised = (light.nDotL * bands).floorToDouble() / bands;
        final fraction = fract(light.nDotL * bands);
        quantised += smoothstep(0.85, 1.0, fraction) / bands;
        // AccumulateLights multiplies by N.L, which is what the banding is meant
        // to replace, so divide it back out and keep the ramp.
        final ramp = quantised / math.max(light.nDotL, 1e-3);
        return s.albedo * ramp;
      },
    ).scaled(s.occlusion);

    // The rim belongs to the view, not to any one light: inside the loop it
    // would brighten with the number of lamps in the scene.
    final specularStrength = b.vec4('FragInfo', 'material', Vector4.zero()).w;
    final rim =
        math.pow(1.0 - s.nDotV, 3.0).toDouble() * specularStrength * 0.35;
    final ambient =
        (s.albedo.clone()..multiply(s.ambient + sampleLightmap(v, b, c)))
            .scaled(s.occlusion);
    final total = lit + ambient + Vector3.all(rim) + s.emissive;
    return writeLit(
      c,
      v,
      b,
      colour: total,
      alpha: s.alpha,
      normal: s.normal,
      roughness: s.roughness,
    );
  }
}
