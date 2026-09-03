#version 460 core

// Metal-rough physically based shading: Cook-Torrance specular with the GGX
// distribution, height-correlated Smith visibility and a Schlick Fresnel.
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
#include <lib/material_maps.glsl>
#include <lib/shadow.glsl>

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

float LightVisibility(Surface s, LightSample light, int index) {
  return ShadowFactor(s, light, index);
}

vec3 ShadeLight(Surface s, LightSample light) {
  // Perceptual roughness is squared to get the GGX alpha; this is what makes
  // the roughness slider feel linear.
  float alpha = s.roughness * s.roughness;

  // Dielectrics reflect ~4% at normal incidence; metals tint the reflection
  // with their own albedo and have no diffuse response.
  vec3 f0 = mix(vec3(0.04), s.albedo, s.metallic);
  vec3 diffuseColor = s.albedo * (1.0 - s.metallic);

  float d = D_GGX(light.n_dot_h, alpha);
  float vis = V_SmithGGXCorrelated(s.n_dot_v, light.n_dot_l, alpha);
  vec3 f = F_Schlick(f0, light.v_dot_h);

  vec3 specular = d * vis * f * frag_info.material.w;
  // Energy left over after reflection is what scatters diffusely.
  vec3 diffuse = diffuseColor * (vec3(1.0) - f) / kPi;

  // The pi puts the result back on the scale the tone mapper and the exposure
  // default were calibrated against.
  return (diffuse + specular) * kPi;
}

void main() {
  Surface s = ReadSurface();
  ApplyCommonMaps(s);
  ApplyMetallicRoughnessMap(s);

  float metallic = clamp(s.metallic, 0.0, 1.0);
  vec3 diffuseColor = s.albedo * (1.0 - metallic);

  // Ambient occlusion darkens indirect light. It is applied to the direct term
  // too, which is not physical, but with no environment the flat ambient is far
  // too weak for an occlusion map to be visible otherwise.
  vec3 ambient = diffuseColor * s.ambient * s.occlusion;

  float levels = frag_info.frame_params.w;
  if (levels > 0.0) {
    // **This is the term that made metal black.** A metal has no diffuse
    // response at all, so with nothing to reflect it was lit by direct light
    // alone and read as very nearly unlit — which is why the games reached for
    // dark dielectrics wherever they wanted gunmetal.
    vec3 f0 = mix(vec3(0.04), s.albedo, metallic);
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
    ambient = (diffuseColor * irradiance + prefiltered * (f0 * ab.x + ab.y)) *
              frag_info.material.z * s.occlusion;
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

  WriteSurface(
      AccumulateLights(s) * s.occlusion + ambient + s.emissive,
      s.alpha,
      s.roughness);
}
