// Shared material interface for the lighting models.
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

uniform FragInfo {
  /// xyz: unit vector pointing from the surface towards the light.
  vec4 light_direction;

  /// rgb: light colour. w: intensity multiplier.
  vec4 light_color;

  /// rgb: albedo tint applied on top of the texture.
  vec4 base_color;

  /// xyz: camera position in world space, needed for every specular term.
  vec4 camera_position;

  /// x: metallic, y: roughness, z: ambient strength, w: specular strength.
  vec4 material;

  /// x: exposure. The rest is reserved so adding a frame-wide parameter does not
  /// change the offsets of anything already here.
  vec4 frame_params;
}
frag_info;

uniform sampler2D base_color_texture;

/// Everything a lighting model needs, resolved once per fragment.
struct Surface {
  vec3 albedo;      // linear, already tinted
  vec3 n;           // unit normal
  vec3 l;           // unit direction to the light
  vec3 v;           // unit direction to the camera
  vec3 h;           // unit half vector
  float n_dot_l;
  float n_dot_v;
  float n_dot_h;
  float v_dot_h;
  float metallic;
  float roughness;  // perceptual
  vec3 light;       // light colour times intensity
  float ambient;
  float exposure;
};

Surface ReadSurface() {
  Surface s;

  vec3 texel = texture(base_color_texture, v_texcoord).rgb;
  s.albedo = SrgbToLinear(texel) * SrgbToLinear(frag_info.base_color.rgb);

  s.n = normalize(v_normal);
  s.l = normalize(frag_info.light_direction.xyz);
  s.v = normalize(frag_info.camera_position.xyz - v_world_position);
  s.h = normalize(s.l + s.v);

  s.n_dot_l = max(dot(s.n, s.l), 0.0);
  // Clamped away from zero: a grazing view direction otherwise divides by zero
  // in the specular visibility term.
  s.n_dot_v = max(dot(s.n, s.v), 1e-4);
  s.n_dot_h = max(dot(s.n, s.h), 0.0);
  s.v_dot_h = max(dot(s.v, s.h), 0.0);

  s.metallic = clamp(frag_info.material.x, 0.0, 1.0);
  s.roughness = clamp(frag_info.material.y, 0.02, 1.0);
  s.ambient = frag_info.material.z;

  s.light = frag_info.light_color.rgb * frag_info.light_color.w;
  s.exposure = max(frag_info.frame_params.x, 0.0);

  return s;
}

#endif  // SURFACE_GLSL_
