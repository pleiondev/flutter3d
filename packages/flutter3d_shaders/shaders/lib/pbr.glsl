// Metal-rough physically based shading: Cook-Torrance specular with the GGX
// distribution, height-correlated Smith visibility and a Schlick Fresnel.
//
// **The body of two stages.** `lighting/pbr.frag` is this and nothing else;
// `lighting/pbr_layered.frag` defines `F3D_LAYERED` first and gets the glTF
// layers on top — `M1`. Everything under `#ifdef F3D_LAYERED` is the layered
// stage's alone, and everything under its `#else` is what plain metal-rough
// always was, kept as it was so that stage compiles to what it compiled to.
// Formulations follow Filament, which is also what the glTF spec describes, so
// imported glTF materials will land on the same look.
//
// Image-based lighting is here when a scene supplies an environment, and the
// flat hemispheric ambient stands in when it does not. `frame_params.w` carries
// the number of levels in the environment cube and is zero when there is none —
// the slot that block reserved for exactly this kind of frame-wide parameter.
//
// **The environment sampler is always bound**, to a one-texel cube when a scene
// has no environment. A sampler a shader declares and nobody binds is a native
// crash on Metal rather than a black texture; the same rule keeps the sky's
// cube out of `sky.frag` and a white texel under the composite's occlusion.
// `L7`: rectangle lights integrate the GGX lobe; see `lib/ltc.glsl`.
#define F3D_LTC
#ifndef PBR_GLSL_
#define PBR_GLSL_

#include <lib/material_maps.glsl>
#include <lib/shadow.glsl>

#ifdef F3D_LAYERED
/// What a layered material adds to metal-rough — `M1`. A block of its own
/// rather than members appended to `FragInfo`: six stages share that block and
/// none of the other five reads a layer.
uniform LayerInfo {
  /// rgb: `KHR_materials_specular`'s colour, linear. w: its strength.
  vec4 specular;

  /// x: the clear coat, y: its perceptual roughness, z: the index of
  /// refraction, w: unused.
  vec4 coat;
}
layer_info;

/// The coat map: r the clear coat, g its roughness, each multiplying its
/// factor; b and a are reserved for transmission and thickness. White when a
/// material has none. One texture where glTF gives up to four, because the
/// lit stages have two samplers left under WebGL2's sixteen.
uniform sampler2D coat_texture;

/// The layers at this fragment, resolved once by [ReadLayers] and read by
/// every light: the dielectric's reflectance head-on and at grazing, and the
/// coat — how much, how rough, which way it faces, and what it leaves of what
/// is under it.
vec3 g_f0_dielectric = vec3(0.04);
float g_f90 = 1.0;
float g_coat = 0.0;
float g_coat_roughness = 0.02;
vec3 g_coat_n = vec3(0.0, 0.0, 1.0);
float g_coat_n_dot_v = 1.0;
float g_coat_through = 1.0;

/// Fills the globals above from the block and the coat map.
///
/// Called before the normal map bends `s.n`, because the coat is lit on the
/// geometric normal: a lacquer over a bumpy base is smooth, and that is what
/// makes car paint read as car paint.
void ReadLayers(Surface s) {
  vec4 coatTexel = texture(coat_texture, v_texcoord, MaterialLodBias());
  // `KHR_materials_ior` and `KHR_materials_specular`: the reflectance a
  // dielectric of this index has head-on, tinted and scaled, and the
  // strength alone at grazing. 1.5, white and one give 0.04 and 1 — plain
  // metal-rough.
  float ior = max(layer_info.coat.z, 1.0);
  float r = (ior - 1.0) / (ior + 1.0);
  g_f0_dielectric =
      min(vec3(r * r) * layer_info.specular.rgb, vec3(1.0)) *
      layer_info.specular.w;
  g_f90 = layer_info.specular.w;
  g_coat = clamp(layer_info.coat.x * coatTexel.r, 0.0, 1.0);
  g_coat_roughness = clamp(layer_info.coat.y * coatTexel.g, 0.02, 1.0);
  g_coat_n = s.n;
  g_coat_n_dot_v = max(dot(s.n, s.v), 1e-4);
  // The coat is a dielectric of index 1.5, and what it reflects towards the
  // eye does not reach the layer under it: everything beneath is scaled by
  // what its Fresnel lets through.
  float fc = 0.04 + 0.96 * pow(1.0 - g_coat_n_dot_v, 5.0);
  g_coat_through = 1.0 - g_coat * fc;
}
#endif  // F3D_LAYERED

/// The environment, convolved by roughness: level zero is a mirror and the last
/// is rough enough to stand in for irradiance. Built by `EnvironmentMap`.
uniform samplerCube environment_texture;

/// The split-sum BRDF, as arithmetic rather than as a lookup table.
///
/// The usual form of this is a 2D texture indexed by roughness and view angle.
/// Karis' analytic fit replaces it at a cost too small to see on anything but a
/// grazing mirror, and what it buys is a third texture binding this renderer
/// does not have to find, bind on every backend, and mirror in the software
/// rasteriser. Returns the scale and bias to apply to F0.
vec2 EnvBrdfApprox(float roughness, float n_dot_v) {
  const vec4 c0 = vec4(-1.0, -0.0275, -0.572, 0.022);
  const vec4 c1 = vec4(1.0, 0.0425, 1.04, -0.04);
  vec4 r = roughness * c0 + c1;
  float a004 = min(r.x * r.x, exp2(-9.28 * n_dot_v)) * r.x + r.y;
  return vec2(-1.04, 1.04) * a004 + r.zw;
}

float D_GGX(float n_dot_h, float alpha) {
  float a = n_dot_h * alpha;
  float k = alpha / max(1.0 - n_dot_h * n_dot_h + a * a, 1e-6);
  return k * k * (1.0 / kPi);
}

float V_SmithGGXCorrelated(float n_dot_v, float n_dot_l, float alpha) {
  float a2 = alpha * alpha;
  float lambda_v = n_dot_l * sqrt(n_dot_v * n_dot_v * (1.0 - a2) + a2);
  float lambda_l = n_dot_v * sqrt(n_dot_l * n_dot_l * (1.0 - a2) + a2);
  return 0.5 / max(lambda_v + lambda_l, 1e-5);
}

vec3 F_Schlick(vec3 f0, float v_dot_h) {
  float f = pow(1.0 - v_dot_h, 5.0);
  return f0 + (vec3(1.0) - f0) * f;
}

#ifdef F3D_LAYERED
/// [F_Schlick] towards [f90] rather than towards one at grazing — what
/// `KHR_materials_specular`'s strength scales.
vec3 F_SchlickF90(vec3 f0, vec3 f90, float v_dot_h) {
  float f = pow(1.0 - v_dot_h, 5.0);
  return f0 + (f90 - f0) * f;
}

/// The clear coat's own GGX lobe for [light], on the coat's normal, with the
/// Fresnel of a dielectric of index 1.5. Scaled so that the loop's `n_dot_l`,
/// which is the base's, becomes the coat's: the coat faces the geometric
/// normal and the base may face the normal map's. A rectangle's `n_dot_l` is
/// a form factor rather than a cosine and is left as it is.
float CoatLobe(LightSample light) {
  float alpha = g_coat_roughness * g_coat_roughness;
  float n_dot_l = max(dot(g_coat_n, light.l), 0.0);
  float n_dot_h = max(dot(g_coat_n, light.h), 0.0);
  float d = D_GGX(n_dot_h, alpha);
  float vis = V_SmithGGXCorrelated(g_coat_n_dot_v, n_dot_l, alpha);
  float f = 0.04 + 0.96 * pow(1.0 - light.v_dot_h, 5.0);
  float scale = light.integrated > 0.5
                    ? 1.0
                    : n_dot_l / max(light.n_dot_l, 1e-6);
  return d * vis * f * frag_info.material.w * scale;
}
#endif  // F3D_LAYERED

float LightVisibility(Surface s, LightSample light, int index) {
  return ShadowFactor(s, light, index);
}

/// Whether the energy lost to single scattering is put back — `L1`,
/// `RenderSettings.energyCompensation`, in `FragInfo.target_origin.z`.
bool EnergyCompensation() { return frag_info.target_origin.z > 0.5; }

/// The light GGX loses on a rough metal, returned as the factor its single
/// scattering has to be multiplied by: one plus f0 times the share of the
/// hemisphere the single-scattering albedo misses. Fdez-Agüera's term, with
/// the albedo the split sum already computes.
vec3 MultiscatterScale(vec3 f0, Surface s) {
  vec2 ab = EnvBrdfApprox(s.roughness, s.n_dot_v);
  float ess = max(ab.x + ab.y, 1e-4);
  return vec3(1.0) + f0 * (1.0 / ess - 1.0);
}

vec3 ShadeLight(Surface s, LightSample light) {
  // Perceptual roughness is squared to get the GGX alpha; this is what makes
  // the roughness slider feel linear.
  float alpha = s.roughness * s.roughness;

  // Dielectrics reflect ~4% at normal incidence; metals tint the reflection
  // with their own albedo and have no diffuse response.
#ifdef F3D_LAYERED
  // The dielectric's own reflectance, from its index and specular layer.
  vec3 f0 = mix(g_f0_dielectric, s.albedo, s.metallic);
  vec3 f90 = vec3(mix(g_f90, 1.0, s.metallic));
#else
  vec3 f0 = mix(vec3(0.04), s.albedo, s.metallic);
#endif
  vec3 diffuseColor = s.albedo * (1.0 - s.metallic);

  float d = D_GGX(light.n_dot_h, alpha);
  float vis = V_SmithGGXCorrelated(s.n_dot_v, light.n_dot_l, alpha);
#ifdef F3D_LAYERED
  vec3 f = F_SchlickF90(f0, f90, light.v_dot_h);
#else
  vec3 f = F_Schlick(f0, light.v_dot_h);
#endif

  vec3 specular = d * vis * f * frag_info.material.w;
  if (light.integrated > 0.5) {
    // `L7`: the lobe already integrated over the rectangle, with the fit's
    // own Fresnel. Divided by `n_dot_l` because the loop multiplies by it,
    // and that is the diffuse form factor, not a term of this; the `kPi` the
    // return applies is the same calibration the diffuse gets.
#ifdef F3D_LAYERED
    specular = light.ltc.x * (f0 * light.ltc.y + (f90 - f0) * light.ltc.z) *
               frag_info.material.w / max(light.n_dot_l, 1e-6);
#else
    specular = light.ltc.x * (f0 * light.ltc.y + (1.0 - f0) * light.ltc.z) *
               frag_info.material.w / max(light.n_dot_l, 1e-6);
#endif
  }
  if (EnergyCompensation()) specular *= MultiscatterScale(f0, s);
  // Energy left over after reflection is what scatters diffusely.
  vec3 diffuse = diffuseColor * (vec3(1.0) - f) / kPi;

  // The pi puts the result back on the scale the tone mapper and the exposure
  // default were calibrated against.
#ifdef F3D_LAYERED
  // Under the coat, what its Fresnel lets through; on top, its own lobe.
  return ((diffuse + specular) * g_coat_through +
          vec3(g_coat * CoatLobe(light))) *
         kPi;
#else
  return (diffuse + specular) * kPi;
#endif
}

void main() {
  Surface s = ReadSurface();
#ifdef F3D_LAYERED
  ReadLayers(s);
#endif
  ApplyCommonMaps(s);
  ApplyMetallicRoughnessMap(s);

  float metallic = clamp(s.metallic, 0.0, 1.0);
  vec3 diffuseColor = s.albedo * (1.0 - metallic);

  // Ambient occlusion darkens indirect light. It is applied to the direct term
  // too, which is not physical, but with no environment the flat ambient is far
  // too weak for an occlusion map to be visible otherwise.
  vec3 ambient = diffuseColor * s.ambient * s.occlusion;

  float levels = frag_info.frame_params.w;
#ifdef F3D_LAYERED
  // What the coat reflects of the environment; nothing without one, since
  // the flat ambient has no specular part for it to have.
  vec3 coatAmbient = vec3(0.0);
#endif
  if (levels > 0.0) {
    // **This is the term that made metal black.** A metal has no diffuse
    // response at all, so with nothing to reflect it was lit by direct light
    // alone and read as very nearly unlit — which is why the games reached for
    // dark dielectrics wherever they wanted gunmetal.
#ifdef F3D_LAYERED
    vec3 f0 = mix(g_f0_dielectric, s.albedo, metallic);
    float f90 = mix(g_f90, 1.0, metallic);
#else
    vec3 f0 = mix(vec3(0.04), s.albedo, metallic);
#endif
    vec3 reflected = reflect(-s.v, s.n);

    // The roughest level stands in for irradiance. Not a true Lambert
    // convolution — see `EnvironmentMap.diffuseLevel`, which says the same
    // thing from the other side and states what it costs.
    vec3 irradiance = textureLod(environment_texture, s.n, levels).rgb;
    vec3 prefiltered =
        textureLod(environment_texture, reflected, s.roughness * levels).rgb;
    vec2 ab = EnvBrdfApprox(s.roughness, s.n_dot_v);

    // Scaled by the strength in the slot the flat term above reads, which is
    // why the two are interchangeable rather than additive: whichever term
    // runs, it runs at `material.z`. **What that number is depends on what is
    // bound.** A scene's own environment is scaled by `Scene.ambientIntensity`,
    // the same knob the flat term uses, so a scene that dials its indirect
    // light down dials both; a reflection probe brings its own
    // `ReflectionProbeNode.intensity` instead, because a probe is the room's
    // light already measured. The renderer decides which — see `_encodeNode`
    // in renderer_mesh_encode.dart — and this stage cannot tell them apart.
#ifdef F3D_LAYERED
    vec3 specular = prefiltered * (f0 * ab.x + f90 * ab.y);
#else
    vec3 specular = prefiltered * (f0 * ab.x + ab.y);
#endif
    if (EnergyCompensation()) {
      // Fdez-Agüera: the single-scattered part as it was, and the multiple
      // scattering it misses added from the irradiance, tinted by the average
      // Fresnel — `L1`.
#ifdef F3D_LAYERED
      vec3 single = f0 * ab.x + f90 * ab.y;
#else
      vec3 single = f0 * ab.x + ab.y;
#endif
      float missed = 1.0 - (ab.x + ab.y);
      vec3 average = f0 + (vec3(1.0) - f0) / 21.0;
      vec3 multiple = single * average / (vec3(1.0) - missed * average);
      specular += multiple * missed * irradiance;
    }
    ambient = (diffuseColor * irradiance + specular) * frag_info.material.z *
              s.occlusion;
#ifdef F3D_LAYERED
    // The coat reflects the environment too, on its own normal and at its
    // own roughness, over what it lets through of the layer beneath.
    vec3 coatPrefiltered = textureLod(environment_texture,
                                      reflect(-s.v, g_coat_n),
                                      g_coat_roughness * levels)
                               .rgb;
    vec2 coatAb = EnvBrdfApprox(g_coat_roughness, g_coat_n_dot_v);
    coatAmbient = coatPrefiltered * (0.04 * coatAb.x + coatAb.y) * g_coat *
                  frag_info.material.z * s.occlusion;
#endif
  }
  // The light the level's walls throw on each other, baked: diffuse only,
  // since a lightmap holds irradiance and a metal has no diffuse response.
  // Zero from the one-texel black a material without a map is bound to.
  //
  // **Added rather than chosen between, and the choosing happens above this
  // shader.** A lightmap and an environment's roughest level are two answers
  // to the same question — how much indirect light reaches this point — so a
  // draw that had both would count it twice. There is no flag here to branch
  // on: a material without a map is bound the neutral black by design (see
  // material_maps.glsl), which is what makes this a plain add. The renderer
  // keeps the two apart instead, by handing no reflection probe to a
  // lightmapped draw; see `_encodeNode` in renderer_mesh_encode.dart. A sky
  // environment over a lightmapped level still adds, and should: sky light
  // is not what the bake measured.
  ambient += diffuseColor * SampleLightmap() * s.occlusion;

#ifdef F3D_LAYERED
  // What shines from under the coat is dimmed by it on the way out, the
  // emission included — glTF's own layering. The direct light was scaled in
  // `ShadeLight`.
  WriteSurface(
      AccumulateLights(s) * s.occlusion +
          (ambient + s.emissive) * g_coat_through + coatAmbient,
      s.alpha,
      s.roughness);
#else
  WriteSurface(
      AccumulateLights(s) * s.occlusion + ambient + s.emissive,
      s.alpha,
      s.roughness);
#endif
}

#endif  // PBR_GLSL_
