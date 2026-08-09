// Shared material and lighting interface for the lighting models.
//
// flutter_gpu compiles shaders ahead of time into a bundle: there is no runtime
// compilation, so a node-graph material system in the style of Babylon's
// NodeMaterial or three.js TSL is impossible. Each lighting model is therefore
// its own pre-built fragment shader, and this header is what keeps them
// interchangeable — one identical uniform block, so the Dart binding code never
// needs to know which model is active.
//
// Keep every declaration below byte-identical across models. A member a model
// does not read may be optimized out of the reflected block, which is why the
// Dart side skips absent members instead of failing.
//
// Only include this from a shader that actually reads FragInfo. Declaring the
// block without using it leaves it visible to reflection while the compiled
// shader binds no buffer for it, and binding that phantom block segfaults
// inside Metal. Shaders needing only colour helpers include lib/color.glsl.

#ifndef SURFACE_GLSL_
#define SURFACE_GLSL_

#include <lib/color.glsl>

/// Lights per draw. Must match LightBuffer.maxLights on the Dart side.
///
/// A fixed array with a runtime count, not a shader permutation per light
/// count: turning a light on has to be free, because there is no runtime
/// compilation to fall back on. Verified against the SDK — Impeller keeps
/// `vec4 x[8]` in the compiled Metal struct and reflects the array's base
/// offset, with the std140 stride of 16 bytes.
#define kMaxLights 8

uniform FragInfo {
  /// xyz: world position (point and spot). w: type, 0 directional 1 point 2 spot.
  vec4 light_position[kMaxLights];

  /// rgb: linear colour. w: intensity.
  vec4 light_color[kMaxLights];

  /// xyz: the direction the light points, its local -Z. w: range, 0 unbounded.
  vec4 light_direction[kMaxLights];

  /// x: cos(inner cone angle). y: cos(outer cone angle).
  vec4 light_cone[kMaxLights];

  /// rgb: albedo tint applied on top of the texture. w: opacity.
  vec4 base_color;

  /// rgb: emissive factor, already linear. w unused.
  vec4 emissive;

  /// xyz: camera position in world space, needed for every specular term.
  vec4 camera_position;

  /// x: metallic, y: roughness, z: ambient strength, w: specular strength.
  vec4 material;

  /// x: alpha cutoff (negative when the material is not masked), y: normal
  /// scale, z: occlusion strength, w: emissive strength.
  vec4 material2;

  /// x: exposure, y: active light count, z: index of the shadow-casting light.
  /// w is reserved so adding a frame-wide parameter does not change the offsets
  /// of anything already here.
  vec4 frame_params;

  /// x: one texel of the shadow map, y: depth bias, z: normal offset,
  /// w: strength, zero when shadows are off.
  vec4 shadow_params;

  /// World space to the shadow camera's clip space.
  mat4 shadow_matrix;
}
frag_info;

uniform sampler2D base_color_texture;

/// Everything about the surface that does not depend on which light is being
/// evaluated, resolved once per fragment.
struct Surface {
  vec3 albedo;      // linear, already tinted
  float alpha;      // opacity after texture, tint and vertex colour
  vec3 n;           // unit normal, perturbed by the normal map when there is one
  vec3 v;           // unit direction to the camera
  float n_dot_v;
  float metallic;
  float roughness;  // perceptual
  float occlusion;  // 1 means unoccluded
  vec3 emissive;    // linear, added after shading
  float ambient;
  float exposure;
};

/// One light's contribution geometry, recomputed per light per fragment.
struct LightSample {
  vec3 l;           // unit direction to the light
  vec3 h;           // unit half vector
  vec3 radiance;    // colour * intensity * attenuation
  float n_dot_l;
  float n_dot_h;
  float v_dot_h;
};

Surface ReadSurface() {
  Surface s;

  vec4 texel = texture(base_color_texture, v_texcoord);
  // Vertex colour is authored linear per the glTF spec, unlike the base colour
  // texture and the tint, which are sRGB.
  s.albedo = SrgbToLinear(texel.rgb) *
             SrgbToLinear(frag_info.base_color.rgb) *
             v_color.rgb;
  s.alpha = texel.a * frag_info.base_color.a * v_color.a;

  // Alpha masking, glTF's third alpha mode. A negative cutoff means the
  // material is opaque or blended, and discard would then be wrong rather than
  // merely unnecessary. Doing it before anything else is deliberate: a
  // discarded fragment should not pay for the lighting loop.
  float cutoff = frag_info.material2.x;
  if (cutoff >= 0.0 && s.alpha < cutoff) discard;

  s.n = normalize(v_normal);
  s.v = normalize(frag_info.camera_position.xyz - v_world_position);
  // Clamped away from zero: a grazing view direction otherwise divides by zero
  // in the specular visibility term.
  s.n_dot_v = max(dot(s.n, s.v), 1e-4);

  s.metallic = clamp(frag_info.material.x, 0.0, 1.0);
  s.roughness = clamp(frag_info.material.y, 0.02, 1.0);
  s.ambient = frag_info.material.z;
  s.exposure = max(frag_info.frame_params.x, 0.0);

  // Neutral until ApplyMaterialMaps says otherwise, so a model that samples no
  // maps still has a complete surface.
  s.occlusion = 1.0;
  s.emissive = vec3(0.0);

  return s;
}

int LightCount() {
  return clamp(int(frag_info.frame_params.y + 0.5), 0, kMaxLights);
}

/// Distance attenuation for a punctual light, following the glTF spec.
///
/// Inverse square with an optional range window. The window is what stops a
/// lamp with a declared range from contributing a faint haze across the whole
/// scene, which matters far more once there are eight of them.
float PunctualAttenuation(float distance, float range) {
  float attenuation = 1.0 / max(distance * distance, 1e-4);
  if (range > 0.0) {
    float ratio = distance / range;
    float window = clamp(1.0 - ratio * ratio * ratio * ratio, 0.0, 1.0);
    attenuation *= window * window;
  }
  return attenuation;
}

/// Resolves light [index] against the surface.
///
/// Returns `n_dot_l == 0` for anything that contributes nothing — behind the
/// surface, out of range, outside the spot cone — so a model can skip it with
/// one test instead of repeating the classification.
LightSample SampleLight(int index, Surface s) {
  LightSample light;

  vec4 position = frag_info.light_position[index];
  vec4 color = frag_info.light_color[index];
  vec4 direction = frag_info.light_direction[index];
  vec4 cone = frag_info.light_cone[index];

  float type = position.w;
  vec3 aim = normalize(direction.xyz);
  float attenuation = 1.0;

  if (type < 0.5) {
    // Directional: no position, no falloff. The direction to the light is the
    // reverse of the direction it points.
    light.l = -aim;
  } else {
    vec3 toLight = position.xyz - v_world_position;
    float distance = length(toLight);
    // A light exactly on the surface has no direction; treat it as contributing
    // nothing rather than producing a NaN that spreads through the frame.
    if (distance < 1e-6) {
      light.l = s.n;
      light.h = s.n;
      light.radiance = vec3(0.0);
      light.n_dot_l = 0.0;
      light.n_dot_h = 0.0;
      light.v_dot_h = 0.0;
      return light;
    }
    light.l = toLight / distance;
    attenuation = PunctualAttenuation(distance, direction.w);

    if (type > 1.5) {
      // Spot: a smooth ramp between the two cone cosines. The Dart side already
      // guarantees the denominator is non-zero.
      float cosAngle = dot(aim, -light.l);
      attenuation *= clamp(
          (cosAngle - cone.y) / (cone.x - cone.y), 0.0, 1.0);
    }
  }

  light.h = normalize(light.l + s.v);
  light.n_dot_l = max(dot(s.n, light.l), 0.0);
  light.n_dot_h = max(dot(s.n, light.h), 0.0);
  light.v_dot_h = max(dot(s.v, light.h), 0.0);
  light.radiance = color.rgb * color.w * attenuation;

  return light;
}

/// How much of light [index] reaches this fragment, defined by each fragment
/// shader.
///
/// A prototype rather than a call into shadow.glsl, because the models that
/// sample no shadow map must not declare its sampler — the compiler would drop
/// the slot and leave the engine binding one that is not there. A lit model
/// returns `ShadowFactor(...)`; an unlit one returns 1.
float LightVisibility(Surface s, LightSample light, int index);

/// A model's per-light term, defined by each fragment shader.
///
/// A prototype here and the definition in the model is what lets the loop below
/// be written once. The alternative — repeating the loop in every model — is
/// six copies of the same three lines, and the place a light would go missing.
vec3 ShadeLight(Surface s, LightSample light);

/// Sums every active light's contribution.
///
/// The loop bound is the compile-time maximum with a runtime break, because GLSL
/// wants a constant trip count and the hardware wants the early exit.
/// The cube atlas: three tiles across, two down, each a ninety-degree view
/// from a point light, each storing radial distance normalised by range.
uniform sampler2D point_shadow_texture;

uniform PointShadow {
  /// The same six view-projections the atlas was rendered with.
  ///
  /// Passed rather than reconstructed. Deriving cube face coordinates here
  /// would be a second implementation of a decision the renderer already made,
  /// and the two would disagree about handedness or up vectors on some face
  /// and nowhere else — which shows as one face of every shadow being wrong.
  mat4 faces[6];

  /// xyz: the light's world position. w: its range.
  vec4 light;

  /// x: index of the light this belongs to, negative when there is none.
  /// y: distance bias in metres. z: strength. w unused.
  vec4 params;
}
point_shadow;

/// How lit [world] is by the point light that owns the cube atlas.
///
/// One, fully lit, when this is not that light or the atlas has nothing to say.
float PointShadowFactor(vec3 world, vec3 normal, int lightIndex) {
  if (point_shadow.params.x < 0.0) return 1.0;
  if (lightIndex != int(point_shadow.params.x + 0.5)) return 1.0;
  float strength = point_shadow.params.z;
  if (strength <= 0.0) return 1.0;

  // Offset along the normal before measuring, for the same reason the
  // directional map does it: the error is proportional to slope, not depth.
  vec3 origin = world + normal * point_shadow.params.y;
  vec3 toFragment = origin - point_shadow.light.xyz;
  float distance = length(toFragment);
  float range = max(point_shadow.light.w, 1e-4);
  if (distance >= range) return 1.0;

  // The dominant axis picks the face, in the order the renderer wrote them:
  // +X, -X, +Y, -Y, +Z, -Z, left to right then top to bottom.
  vec3 a = abs(toFragment);
  int face;
  if (a.x >= a.y && a.x >= a.z) {
    face = toFragment.x > 0.0 ? 0 : 1;
  } else if (a.y >= a.z) {
    face = toFragment.y > 0.0 ? 2 : 3;
  } else {
    face = toFragment.z > 0.0 ? 4 : 5;
  }

  vec4 clip = point_shadow.faces[face] * vec4(origin, 1.0);
  if (clip.w <= 0.0) return 1.0;
  vec2 ndc = clip.xy / clip.w;
  if (abs(ndc.x) > 1.0 || abs(ndc.y) > 1.0) return 1.0;

  vec2 uv = ndc * 0.5 + 0.5;
  vec2 tile = vec2(float(face - (face / 3) * 3), float(face / 3));
  uv = (uv + tile) * vec2(1.0 / 3.0, 0.5);

  float stored = texture(point_shadow_texture, uv).r * range;
  // Nothing was drawn in that direction, so nothing is in the way.
  if (stored >= range * 0.999) return 1.0;

  return distance - point_shadow.params.y > stored ? 1.0 - strength : 1.0;
}

vec3 AccumulateLights(Surface s) {
  vec3 total = vec3(0.0);
  int count = LightCount();

  for (int i = 0; i < kMaxLights; i++) {
    if (i >= count) break;
    LightSample light = SampleLight(i, s);
    if (light.n_dot_l <= 0.0) continue;
    float visibility = LightVisibility(s, light, i) *
        PointShadowFactor(v_world_position, s.n, i);
    if (visibility <= 0.0) continue;
    total += ShadeLight(s, light) * light.radiance * light.n_dot_l * visibility;
  }

  return total;
}

#endif  // SURFACE_GLSL_
