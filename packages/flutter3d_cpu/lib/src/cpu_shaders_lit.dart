/// The six lighting models — `unlit.frag` through `toon.frag` — each reading
/// a [Surface], applying its own maps, and shading it with
/// `cpu_shaders_lighting.dart`'s `accumulateLights`.
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:vector_math/vector_math.dart';

import 'cpu_shader.dart';
import 'cpu_shaders_color.dart';
import 'cpu_shaders_layout.dart';
import 'cpu_shaders_lighting.dart';
import 'cpu_shaders_ltc.dart';
import 'cpu_shaders_surface.dart';

/// `unlit.frag`: the albedo, written into the HDR target as light.
final class UnlitShader implements CpuFragmentShader {
  const UnlitShader();

  @override
  Vector4? run(Float32List v, ShaderBindings bindings, FragmentContext c) {
    final s = readSurface(v, bindings, c);
    // `L5`: reflects no light, as `unlit.frag` says.
    c.albedo = null;
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
/// `MultiscatterScale` from `pbr.frag` — `L1`.
Vector3 _multiscatterScale(Vector3 f0, Surface s) {
  final ab = _envBrdfApprox(s.roughness, s.nDotV);
  final ess = math.max(ab.x + ab.y, 1e-4);
  return Vector3.all(1.0) + f0 * (1.0 / ess - 1.0);
}

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

/// The layers `lib/pbr.glsl` reads under `F3D_LAYERED` — `M1`: resolved once
/// per fragment, as `ReadLayers` fills its globals.
final class _Layers {
  _Layers({
    required this.f0Dielectric,
    required this.f90,
    required this.coat,
    required this.coatRoughness,
    required this.coatNormal,
    required this.coatNDotV,
    required this.sheen,
    required this.sheenRoughness,
    required this.transmission,
    required this.thickness,
    required this.transmittance,
    required this.iridescence,
    required this.dispersion,
    required this.filmIor,
    required this.filmThickness,
  }) : coatThrough =
           1.0 -
           coat * (0.04 + 0.96 * math.pow(1.0 - coatNDotV, 5.0).toDouble());

  /// `ReadLayers`, from the `LayerInfo` block and the coat map, on [s] as it
  /// is before the normal map bends it.
  factory _Layers.read(
    Surface s,
    Float32List v,
    ShaderBindings b,
    FragmentContext c,
  ) {
    final specular = b.vec4('LayerInfo', 'specular', Vector4(1, 1, 1, 1));
    final coat = b.vec4('LayerInfo', 'coat', Vector4(0, 0, 1.5, 0));
    final uv = uvFootprint(c, bias: materialLodBias(b));
    Vector4 texel(String slot) => switch (b.textures[slot]) {
      final map? => map.sample(v[kVUv], v[kVUv + 1], du: uv.du, dv: uv.dv),
      null => Vector4(1, 1, 1, 1),
    };
    final coatTexel = texel('coat_texture');
    final sheenTexel = texel('sheen_texture');
    final sheen = b.vec4('LayerInfo', 'sheen', Vector4.zero());
    final transmission = b.vec4('LayerInfo', 'transmission', Vector4.zero());
    final attenuation = b.vec4('LayerInfo', 'attenuation', Vector4(1, 1, 1, 0));
    final film = b.vec4('LayerInfo', 'iridescence', Vector4.zero());
    final thickness = math.max(transmission.y * coatTexel.w, 0.0);
    // Beer's law over the thickness, as `ReadLayers` takes it.
    final distance = transmission.z;
    double through(double colour) => distance > 0.0
        ? math.pow(math.max(colour, 1e-4), thickness / distance).toDouble()
        : 1.0;
    final ior = math.max(coat.z, 1.0);
    final r = (ior - 1.0) / (ior + 1.0);
    final layers = _Layers(
      f0Dielectric: Vector3(
        math.min(r * r * specular.x, 1.0) * specular.w,
        math.min(r * r * specular.y, 1.0) * specular.w,
        math.min(r * r * specular.z, 1.0) * specular.w,
      ),
      f90: specular.w,
      coat: (coat.x * coatTexel.x).clamp(0.0, 1.0),
      coatRoughness: (coat.y * coatTexel.y).clamp(0.02, 1.0),
      coatNormal: s.normal.clone(),
      coatNDotV: math.max(s.normal.dot(s.view), 1e-4),
      sheen: Vector3(
        sheen.x * toLinear(sheenTexel.x),
        sheen.y * toLinear(sheenTexel.y),
        sheen.z * toLinear(sheenTexel.z),
      ),
      sheenRoughness: (sheen.w * sheenTexel.w).clamp(0.07, 1.0),
      transmission: (transmission.x * coatTexel.z).clamp(0.0, 1.0),
      thickness: thickness,
      transmittance: (
        through(attenuation.x),
        through(attenuation.y),
        through(attenuation.z),
      ),
      iridescence: film.x.clamp(0.0, 1.0),
      dispersion: transmission.w,
      filmIor: film.y,
      filmThickness: film.z,
    );
    return layers.._ior = ior;
  }

  /// `ReadLayersOnMaps`: the sheen's albedo at this view and the anisotropy's
  /// frame, on the normal the maps left — `M2`.
  void readOnMaps(Surface s, ShaderBindings b, FragmentContext c) {
    final table = b.textures['ltc_texture'];
    sheenAlbedoAtView = table == null
        ? 0.0
        : sheenAlbedo(table, sheenRoughness, s.nDotV);
    sheenScale =
        1.0 - math.max(math.max(sheen.x, sheen.y), sheen.z) * sheenAlbedoAtView;

    final t = Vector3(s.tangent.x, s.tangent.y, s.tangent.z)
      ..sub(
        s.normal * s.normal.dot(Vector3(s.tangent.x, s.tangent.y, s.tangent.z)),
      );
    final usable = t.length2 > 1e-12;
    if (usable) {
      t.normalize();
    } else {
      t.setValues(1.0, 0.0, 0.0);
    }
    final bitangent = s.normal.cross(t)..scale(s.tangent.w);
    if (!c.frontFacing) t.negate();
    final turn = b.vec4('LayerInfo', 'anisotropy', Vector4.zero());
    final along = t * turn.y + bitangent * turn.z;
    anisotropy = usable && along.length2 > 1e-12 ? turn.x.clamp(0.0, 1.0) : 0.0;
    anisotropyT = anisotropy > 0.0 ? (along..normalize()) : t;
    anisotropyB = s.normal.cross(anisotropyT);

    // `ReadIridescence`.
    final metallic = s.metallic.clamp(0.0, 1.0);
    iridFresnel = _fresnelIridescence(
      filmIor,
      s.nDotV,
      filmThickness,
      Vector3(
        f0Dielectric.x + (s.albedo.x - f0Dielectric.x) * metallic,
        f0Dielectric.y + (s.albedo.y - f0Dielectric.y) * metallic,
        f0Dielectric.z + (s.albedo.z - f0Dielectric.z) * metallic,
      ),
    );
  }

  /// [f] with the thin film's colours mixed in, as the stage mixes them.
  Vector3 withFilm(Vector3 f) => Vector3(
    f.x + (iridFresnel.x - f.x) * iridescence,
    f.y + (iridFresnel.y - f.y) * iridescence,
    f.z + (iridFresnel.z - f.z) * iridescence,
  );

  /// `TransmittedRadiance`: the environment through the surface, bent by
  /// the index when there is a volume and spread by the dispersion.
  Vector3 transmitted(Surface s, BoundTexture environment, double levels) {
    final ior = f0Ior;
    final spread = (ior - 1.0) * 0.025 * dispersion;
    final lod = s.roughness * (ior * 2.0 - 2.0).clamp(0.0, 1.0) * levels;
    final incident = -s.view;
    Vector3 ray(double eta) =>
        thickness <= 0.0 ? incident : _refract(incident, s.normal, eta);
    final red = ray(1.0 / math.max(ior - spread, 1.0));
    final green = ray(1.0 / ior);
    final blue = ray(1.0 / (ior + spread));
    return Vector3(
      environment.sampleCube(red.x, red.y, red.z, lod).x,
      environment.sampleCube(green.x, green.y, green.z, lod).y,
      environment.sampleCube(blue.x, blue.y, blue.z, lod).z,
    );
  }

  /// GLSL's `refract`.
  static Vector3 _refract(Vector3 i, Vector3 n, double eta) {
    final d = n.dot(i);
    final k = 1.0 - eta * eta * (1.0 - d * d);
    return k < 0.0 ? Vector3.zero() : (i * eta - n * (eta * d + math.sqrt(k)));
  }

  final Vector3 f0Dielectric;
  final double f90;
  final double coat;
  final double coatRoughness;
  final Vector3 coatNormal;
  final double coatNDotV;

  /// What the coat's Fresnel lets through to the layer beneath.
  final double coatThrough;

  /// The sheen's colour, linear, and its roughness — `M2`.
  final Vector3 sheen;
  final double sheenRoughness;

  /// The transmission — `M3`: how much passes, through how much medium,
  /// and what of each colour survives it.
  final double transmission;
  final double thickness;
  final (double, double, double) transmittance;

  /// The thin film: how much, spread and index — see `ReadIridescence`.
  final double iridescence;
  final double dispersion;
  final double filmIor;
  final double filmThickness;

  /// The index `ReadLayers` took the dielectric's reflectance from, read back
  /// out of it for the refraction.
  double get f0Ior => _ior;
  double _ior = 1.5;

  /// Filled by [readOnMaps].
  Vector3 iridFresnel = Vector3.all(0.04);
  double sheenAlbedoAtView = 0.0;
  double sheenScale = 1.0;
  double anisotropy = 0.0;
  Vector3 anisotropyT = Vector3(1.0, 0.0, 0.0);
  Vector3 anisotropyB = Vector3(0.0, 1.0, 0.0);
}

final class PbrShader implements CpuFragmentShader {
  const PbrShader() : layered = false;

  /// `pbr_layered.frag`: the same stage with `F3D_LAYERED` — `M1`.
  const PbrShader.layered() : layered = true;

  /// Whether this is the layered stage, which reads `LayerInfo` and the coat
  /// map. Plain metal-rough takes none of the branches it guards, so the
  /// thirty golden images of that stage see what they always saw.
  final bool layered;

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

  static Vector3 _fSchlick(Vector3 f0, double vDotH, [double f90 = 1.0]) {
    final f = math.pow(1.0 - vDotH, 5.0).toDouble();
    return Vector3(
      f0.x + (f90 - f0.x) * f,
      f0.y + (f90 - f0.y) * f,
      f0.z + (f90 - f0.z) * f,
    );
  }

  /// `CoatLobe`: the clear coat's GGX lobe on its own normal, scaled so the
  /// loop's `nDotL` — the base's — becomes the coat's. A rectangle's is a form
  /// factor and is left alone.
  static double _coatLobe(
    _Layers layers,
    Surface s,
    LightSample light,
    double specularStrength,
  ) {
    final alpha = layers.coatRoughness * layers.coatRoughness;
    final h = (light.direction + s.view)..normalize();
    final nDotL = math.max(layers.coatNormal.dot(light.direction), 0.0);
    final nDotH = math.max(layers.coatNormal.dot(h), 0.0);
    final d = _dGgx(nDotH, alpha);
    final vis = _vSmith(layers.coatNDotV, nDotL, alpha);
    final f = 0.04 + 0.96 * math.pow(1.0 - light.vDotH, 5.0).toDouble();
    final scale = light.ltc != null ? 1.0 : nDotL / math.max(light.nDotL, 1e-6);
    return d * vis * f * specularStrength * scale;
  }

  /// `D_Charlie`.
  static double _dCharlie(double roughness, double nDotH) {
    final invAlpha = 1.0 / (roughness * roughness);
    final sin2h = math.max(1.0 - nDotH * nDotH, 0.0078125);
    return (2.0 + invAlpha) *
        math.pow(sin2h, invAlpha * 0.5).toDouble() /
        (2.0 * _pi);
  }

  /// `V_Neubelt`.
  static double _vNeubelt(double nDotV, double nDotL) =>
      1.0 / (4.0 * (nDotL + nDotV - nDotL * nDotV));

  /// `D_GGXAnisotropic`.
  static double _dGgxAnisotropic(
    double nDotH,
    double tDotH,
    double bDotH,
    double at,
    double ab,
  ) {
    final a2 = at * ab;
    final fx = ab * tDotH;
    final fy = at * bDotH;
    final fz = a2 * nDotH;
    final w2 = a2 / math.max(fx * fx + fy * fy + fz * fz, 1e-12);
    return a2 * w2 * w2 / _pi;
  }

  /// `V_GGXAnisotropic`.
  static double _vGgxAnisotropic(
    double nDotL,
    double nDotV,
    double bDotV,
    double tDotV,
    double tDotL,
    double bDotL,
    double at,
    double ab,
  ) {
    double length(double x, double y, double z) =>
        math.sqrt(x * x + y * y + z * z);
    final ggxV = nDotL * length(at * tDotV, ab * bDotV, nDotV);
    final ggxL = nDotV * length(at * tDotL, ab * bDotL, nDotL);
    return (0.5 / math.max(ggxV + ggxL, 1e-5)).clamp(0.0, 1.0);
  }

  @override
  Vector4? run(Float32List v, ShaderBindings b, FragmentContext c) {
    final s = readSurface(v, b, c);
    if (s == null) return null;
    final layers = layered ? _Layers.read(s, v, b, c) : null;
    applyCommonMaps(s, v, b, c);
    applyMetallicRoughnessMap(s, v, b, c);
    layers?.readOnMaps(s, b, c);
    final specularStrength = b.vec4('FragInfo', 'material', Vector4.zero()).w;
    // `EnergyCompensation()` — `L1`.
    final compensate =
        b.vec4('FragInfo', 'target_origin', Vector4.zero()).z > 0.5;
    // Plain metal-rough reflects four per cent head-on and all of it at
    // grazing; the layered stage takes both from its layers. Doubles, not a
    // `Vector3`: its float32 lanes would round the plain stage's 0.04.
    final (d0x, d0y, d0z) = switch (layers?.f0Dielectric) {
      final Vector3 f0 => (f0.x, f0.y, f0.z),
      null => (0.04, 0.04, 0.04),
    };

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
          d0x + (s.albedo.x - d0x) * s.metallic,
          d0y + (s.albedo.y - d0y) * s.metallic,
          d0z + (s.albedo.z - d0z) * s.metallic,
        );
        final f90 = layers == null
            ? 1.0
            : layers.f90 + (1.0 - layers.f90) * s.metallic;
        final diffuseColour = s.albedo * (1.0 - s.metallic);

        final (d, vis) = switch (layers) {
          // `M2`: the lobe stretched along the tangent.
          final layers? when layers.anisotropy > 0.0 => () {
            final h = (light.direction + s.view)..normalize();
            final at =
                alpha + (1.0 - alpha) * layers.anisotropy * layers.anisotropy;
            final ab = math.max(alpha, 1e-3);
            final t = layers.anisotropyT;
            final bt = layers.anisotropyB;
            return (
              _dGgxAnisotropic(light.nDotH, t.dot(h), bt.dot(h), at, ab),
              _vGgxAnisotropic(
                light.nDotL,
                s.nDotV,
                bt.dot(s.view),
                t.dot(s.view),
                t.dot(light.direction),
                bt.dot(light.direction),
                at,
                ab,
              ),
            );
          }(),
          _ => (
            _dGgx(light.nDotH, alpha),
            _vSmith(s.nDotV, light.nDotL, alpha),
          ),
        };
        final plainF = _fSchlick(f0, light.vDotH, f90);
        // `M3`: the thin film's colours in place of the plain Fresnel.
        final f = layers == null ? plainF : layers.withFilm(plainF);

        final ltc = light.ltc;
        final specular = ltc == null
            ? f * (d * vis * specularStrength)
            // `L7`: integrated over the rectangle already, with the fit's own
            // Fresnel, and over `nDotL` for `pbr.frag`'s reason.
            : Vector3(
                    f0.x * ltc.y + (f90 - f0.x) * ltc.z,
                    f0.y * ltc.y + (f90 - f0.y) * ltc.z,
                    f0.z * ltc.y + (f90 - f0.z) * ltc.z,
                  ) *
                  (ltc.x * specularStrength / math.max(light.nDotL, 1e-6));
        if (compensate) specular.multiply(_multiscatterScale(f0, s));
        // Energy left over after reflection is what scatters diffusely.
        final diffuse = Vector3(
          diffuseColour.x * (1.0 - f.x) / _pi,
          diffuseColour.y * (1.0 - f.y) / _pi,
          diffuseColour.z * (1.0 - f.z) / _pi,
        );
        // `M3`: what passes through is not scattered back.
        if (layers != null) diffuse.scale(1.0 - layers.transmission);
        // The pi puts the result back on the scale the tone mapper and the
        // exposure default were calibrated against.
        final base = diffuse + specular;
        if (layers == null) return base..scale(_pi);
        // Under the sheen, what its albedo leaves; under the coat, what its
        // Fresnel lets through; on top, the coat's lobe.
        final sheen =
            layers.sheen *
            (_dCharlie(layers.sheenRoughness, light.nDotH) *
                _vNeubelt(s.nDotV, light.nDotL));
        final coat =
            layers.coat * _coatLobe(layers, s, light, specularStrength);
        return (base
            ..scale(layers.sheenScale)
            ..add(sheen)
            ..scale(layers.coatThrough))
          ..add(Vector3.all(coat))
          ..scale(_pi);
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
    if (layers != null) {
      // `M3`: without an environment, the flat ambient passes through too.
      final (tr, tg, tb) = layers.transmittance;
      final t = layers.transmission;
      ambient.multiply(
        Vector3(
          1.0 + (tr - 1.0) * t,
          1.0 + (tg - 1.0) * t,
          1.0 + (tb - 1.0) * t,
        ),
      );
    }
    var coatAmbient = Vector3.zero();
    var sheenIncoming = s.ambient.clone();

    final levels = b.vec4('FragInfo', 'frame_params', Vector4.zero()).w;
    final environment = b.textures['environment_texture'];
    if (levels > 0.0 && environment != null) {
      // The term that made metal black: a metal has no diffuse response, so
      // with nothing to reflect it was lit by direct light alone.
      final dielectric = Vector3(d0x, d0y, d0z);
      final f0 = dielectric + (s.albedo - dielectric) * metallic;
      final f90 = layers == null
          ? 1.0
          : layers.f90 + (1.0 - layers.f90) * metallic;
      // `M2`: an anisotropic surface reflects along a normal bent towards the
      // stretch.
      final bent = switch (layers) {
        final layers? when layers.anisotropy > 0.0 => () {
          final across = layers.anisotropyT.cross(s.view);
          final anisoN = across.cross(layers.anisotropyT);
          final bend = 1.0 - layers.anisotropy * (1.0 - s.roughness);
          final bend4 = bend * bend * bend * bend;
          return (anisoN + (s.normal - anisoN) * bend4)..normalize();
        }(),
        _ => s.normal,
      };
      // reflect(-v, n) = 2(n·v)n - v, with v already the direction to the eye.
      final nDotV = bent.dot(s.view);
      final reflected = bent * (2.0 * nDotV) - s.view;

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
      // The surface's own `n·v`, clamped to 1e-4 as `pbr.frag` passes it —
      // not this raw one clamped to zero. They part only at grazing angles,
      // where the split-sum term is steepest, and a multiscatter term built
      // on top of it would widen the gap it was handed.
      final ab = _envBrdfApprox(s.roughness, s.nDotV);

      final strength = b.vec4('FragInfo', 'material', Vector4.zero()).z;
      final diffusePart = diffuseColour.clone()
        ..multiply(Vector3(irradiance.x, irradiance.y, irradiance.z));
      final single =
          (layers == null ? f0 : layers.withFilm(f0)) * ab.x +
          Vector3.all(f90 * ab.y);
      final specularPart = Vector3(prefiltered.x, prefiltered.y, prefiltered.z)
        ..multiply(single);
      if (compensate) {
        // Fdez-Agüera, as `pbr.frag` adds it — `L1`.
        final missed = 1.0 - (ab.x + ab.y);
        final average = f0 + (Vector3.all(1.0) - f0) / 21.0;
        final multiple = Vector3(
          single.x * average.x / (1.0 - missed * average.x),
          single.y * average.y / (1.0 - missed * average.y),
          single.z * average.z / (1.0 - missed * average.z),
        );
        specularPart.add(
          multiple
            ..multiply(Vector3(irradiance.x, irradiance.y, irradiance.z))
            ..scale(missed),
        );
      }
      ambient = ((diffusePart + specularPart) * strength).scaled(s.occlusion);
      if (layers != null) {
        // `M3`: the transmitted share of the diffuse light is the
        // environment behind, less what the dielectric reflects and the
        // medium takes.
        final reflects =
            layers.withFilm(layers.f0Dielectric) * ab.x +
            Vector3.all(layers.f90 * ab.y);
        final (tr, tg, tb) = layers.transmittance;
        final passed = layers.transmitted(s, environment, levels)
          ..multiply(
            Vector3(
              tr * (1.0 - math.min(reflects.x, 1.0)),
              tg * (1.0 - math.min(reflects.y, 1.0)),
              tb * (1.0 - math.min(reflects.z, 1.0)),
            ),
          );
        ambient.add(
          (diffuseColour.clone()..multiply(
                passed - Vector3(irradiance.x, irradiance.y, irradiance.z),
              ))
              .scaled(layers.transmission * strength * s.occlusion),
        );
        // The coat's own reflection of the environment, on its normal.
        final n = layers.coatNormal;
        final coatReflected = n * (2.0 * n.dot(s.view)) - s.view;
        final coatPrefiltered = environment.sampleCube(
          coatReflected.x,
          coatReflected.y,
          coatReflected.z,
          layers.coatRoughness * levels,
        );
        final coatAb = _envBrdfApprox(layers.coatRoughness, layers.coatNDotV);
        coatAmbient =
            Vector3(coatPrefiltered.x, coatPrefiltered.y, coatPrefiltered.z)
              ..scale(
                (0.04 * coatAb.x + coatAb.y) *
                    layers.coat *
                    strength *
                    s.occlusion,
              );
        final incoming = environment.sampleCube(
          s.normal.x,
          s.normal.y,
          s.normal.z,
          layers.sheenRoughness * levels,
        );
        sheenIncoming = Vector3(incoming.x, incoming.y, incoming.z)
          ..scale(strength);
      }
    }
    // The baked bounce light, diffuse only, as `pbr.frag` adds it.
    ambient += (diffuseColour.clone()..multiply(sampleLightmap(v, b, c)))
        .scaled(s.occlusion);

    // Under a coat, the ambient and the emission come out through it.
    final through = layers?.coatThrough ?? 1.0;
    final total = switch (layers) {
      null => lit + ambient + s.emissive,
      final layers =>
        lit +
            (ambient.scaled(layers.sheenScale) +
                    (layers.sheen.clone()
                      ..multiply(sheenIncoming)
                      ..scale(layers.sheenAlbedoAtView * s.occlusion)) +
                    s.emissive)
                .scaled(through) +
            coatAmbient,
    };
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

/// `IridescenceSensitivity` — Belcour and Barla's spectral sensitivity,
/// taken to linear Rec. 709.
Vector3 _iridescenceSensitivity(double opd, Vector3 shift) {
  const pi = 3.141592653589793;
  final phase = 2.0 * pi * opd * 1.0e-9;
  const val = <double>[5.4856e-13, 4.4201e-13, 5.2481e-13];
  const pos = <double>[1.6810e+06, 1.7953e+06, 2.2084e+06];
  const variance = <double>[4.3278e+09, 9.3046e+09, 6.6121e+09];
  final xyz = <double>[
    for (var i = 0; i < 3; i++)
      val[i] *
          math.sqrt(2.0 * pi * variance[i]) *
          math.cos(pos[i] * phase + shift[i]) *
          math.exp(-(phase * phase) * variance[i]),
  ];
  xyz[0] +=
      9.7470e-14 *
      math.sqrt(2.0 * pi * 4.5282e+09) *
      math.cos(2.2399e+06 * phase + shift.x) *
      math.exp(-4.5282e+09 * phase * phase);
  final x = xyz[0] / 1.0685e-7;
  final y = xyz[1] / 1.0685e-7;
  final z = xyz[2] / 1.0685e-7;
  return Vector3(
    3.2404542 * x - 1.5371385 * y - 0.4985314 * z,
    -0.9692660 * x + 1.8760108 * y + 0.0415560 * z,
    0.0556434 * x - 0.2040259 * y + 1.0572252 * z,
  );
}

/// `FresnelIridescence`: the two-bounce Airy sum of a thin film of index
/// [film] and [thickness] nanometres over a base of reflectance [base].
Vector3 _fresnelIridescence(
  double film,
  double cos1,
  double thickness,
  Vector3 base,
) {
  const pi = 3.141592653589793;
  final t = (thickness / 0.03).clamp(0.0, 1.0);
  final eta2 = 1.0 + (film - 1.0) * (t * t * (3.0 - 2.0 * t));
  final sin2Sq = (1.0 - cos1 * cos1) / (eta2 * eta2);
  final cos2Sq = 1.0 - sin2Sq;
  if (cos2Sq < 0.0) return Vector3.all(1.0);
  final cos2 = math.sqrt(cos2Sq);

  final r0 = (eta2 - 1.0) / (eta2 + 1.0);
  final r12 = r0 * r0 + (1.0 - r0 * r0) * math.pow(1.0 - cos1, 5.0).toDouble();
  final t121 = 1.0 - r12;
  final phi12 = eta2 < 1.0 ? pi : 0.0;
  final phi21 = pi - phi12;

  double channel(int i, List<double> phis) {
    final root = math.sqrt(base[i].clamp(0.0, 0.9999));
    final baseIor = (1.0 + root) / (1.0 - root);
    final r1 = math.pow((baseIor - eta2) / (baseIor + eta2), 2.0).toDouble();
    final r23 = r1 + (1.0 - r1) * math.pow(1.0 - cos2, 5.0).toDouble();
    phis.add(phi21 + (baseIor < eta2 ? pi : 0.0));
    return r23;
  }

  final phis = <double>[];
  final r23 = Vector3(channel(0, phis), channel(1, phis), channel(2, phis));
  final phi = Vector3(phis[0], phis[1], phis[2]);
  final opd = 2.0 * eta2 * thickness * cos2;
  final total = Vector3.zero();
  for (var i = 0; i < 3; i++) {
    final r123 = (r12 * r23[i]).clamp(1e-5, 0.9999);
    final rs = t121 * t121 * r23[i] / (1.0 - r123);
    total[i] = r12 + rs;
  }
  final cm = Vector3(
    (t121 * t121 * r23.x / (1.0 - (r12 * r23.x).clamp(1e-5, 0.9999))) - t121,
    (t121 * t121 * r23.y / (1.0 - (r12 * r23.y).clamp(1e-5, 0.9999))) - t121,
    (t121 * t121 * r23.z / (1.0 - (r12 * r23.z).clamp(1e-5, 0.9999))) - t121,
  );
  final root123 = Vector3(
    math.sqrt((r12 * r23.x).clamp(1e-5, 0.9999)),
    math.sqrt((r12 * r23.y).clamp(1e-5, 0.9999)),
    math.sqrt((r12 * r23.z).clamp(1e-5, 0.9999)),
  );
  for (var m = 1; m <= 2; m++) {
    cm.multiply(root123);
    final sensitivity = _iridescenceSensitivity(m * opd, phi * m.toDouble());
    total.add(
      Vector3(cm.x * sensitivity.x, cm.y * sensitivity.y, cm.z * sensitivity.z)
        ..scale(2.0),
    );
  }
  return Vector3(
    math.max(total.x, 0.0),
    math.max(total.y, 0.0),
    math.max(total.z, 0.0),
  );
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
