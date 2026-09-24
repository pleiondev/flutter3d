#version 460 core

// An octahedral impostor, lit — C4. The card `impostor.vert` turned to the
// eye, showing the three baked views nearest the direction it is seen from.
//
// **Lambert's lighting over a surface read from two atlases.** The albedo
// atlas takes the base colour slot and the normal-depth atlas the normal map
// slot, so the stage asks for no sampler a lit model does not already have —
// the lit stages sit near the sixteen a stage may hold. Diffuse only, because
// the atlases carry no roughness or metal: at the distance a tree becomes a
// card its highlights are below a pixel anyway.
//
// **Three views, blended by where the eye falls between them.** The eye's
// direction lands inside one triangle of the octahedral grid, and its
// barycentric weights say how much of each corner's view to take. Each view is
// read where this fragment's point on the card falls in *that* view's own
// picture — the card turns with the eye, the views do not — so the three agree
// about where a branch is rather than smearing three copies of it.
//
// **Normals were baked in the node's own space** and are turned into the world
// through the card's own frame: its right-hand axis, up and facing are known in
// both spaces (v_tangent and v_normal in the world, and rebuilt here from the
// eye's direction in the node's own), and the rotation that maps one frame
// onto the other is the node's.
//
// The depth in the normal atlas's alpha is baked but not read yet: it is what
// a later stage writes as the fragment's depth so a card intersects the ground
// where the tree does.

#include <lib/impostor.glsl>
#include <lib/shadow.glsl>

// The normal map's slot, declared here rather than through
// `material_maps.glsl`: that header brings four more maps and the irradiance
// field with it, none of which a card reads, and a sampler declared and
// dropped is a reflected slot Metal has no index for.
uniform sampler2D normal_texture;

float LightVisibility(Surface s, LightSample light, int index) {
  return ShadowFactor(s, light, index);
}

vec3 ShadeLight(Surface s, LightSample light) {
  return s.albedo;
}

/// View `cell` of the grid, read at [offset] — this fragment's point on the
/// card, in the node's own space and in radii — as that view saw it.
/// Returns (u, v) in the atlas, or a point outside [0, 1] when the view did
/// not frame this point at all.
vec2 ImpostorViewUv(vec2 cell, vec3 offset) {
  vec3 d = ImpostorDecode(cell / (kImpostorGrid - 1.0));
  vec3 right = ImpostorRight(d);
  vec3 up = cross(d, right);
  vec2 local = vec2(dot(offset, right) * 0.5 + 0.5,
                    0.5 - dot(offset, up) * 0.5);
  return (cell + clamp(local, vec2(0.0), vec2(1.0))) / kImpostorGrid;
}

void main() {
  Surface s = ReadSurface();

  // The eye's direction in the node's own space picks the views; the card's
  // own frame there turns the fragment into a point every view can place.
  vec3 d = normalize(v_color.xyz);
  vec3 right = ImpostorRight(d);
  vec3 up = cross(d, right);
  vec3 offset = right * (v_texcoord.x * 2.0 - 1.0) +
                up * (1.0 - v_texcoord.y * 2.0);

  // Which triangle of the grid, and the weights of its corners. Selects
  // rather than branches, so all three reads below sit in uniform control
  // flow — WGSL refuses an implicit-derivative read anywhere else.
  vec2 g = ImpostorEncode(d) * (kImpostorGrid - 1.0);
  vec2 base = clamp(floor(g), vec2(0.0), vec2(kImpostorGrid - 2.0));
  vec2 f = g - base;
  bool lower = f.x + f.y < 1.0;
  vec2 c0 = lower ? base : base + vec2(1.0, 1.0);
  vec2 c1 = base + vec2(1.0, 0.0);
  vec2 c2 = base + vec2(0.0, 1.0);
  vec3 w = lower ? vec3(1.0 - f.x - f.y, f.x, f.y)
                 : vec3(f.x + f.y - 1.0, 1.0 - f.y, 1.0 - f.x);

  vec2 uv0 = ImpostorViewUv(c0, offset);
  vec2 uv1 = ImpostorViewUv(c1, offset);
  vec2 uv2 = ImpostorViewUv(c2, offset);
  vec4 a0 = textureLod(base_color_texture, uv0, 0.0);
  vec4 a1 = textureLod(base_color_texture, uv1, 0.0);
  vec4 a2 = textureLod(base_color_texture, uv2, 0.0);
  vec4 n0 = textureLod(normal_texture, uv0, 0.0);
  vec4 n1 = textureLod(normal_texture, uv1, 0.0);
  vec4 n2 = textureLod(normal_texture, uv2, 0.0);

  // Weighted by coverage as well, so a view that saw sky here lends neither
  // its colour nor its normal — only its absence, through the alpha.
  vec3 wa = w * vec3(a0.a, a1.a, a2.a);
  float alpha = wa.x + wa.y + wa.z;
  if (alpha < 0.5) discard;
  vec3 srgb = (a0.rgb * wa.x + a1.rgb * wa.y + a2.rgb * wa.z) / alpha;
  vec3 local = (n0.rgb * 2.0 - vec3(1.0)) * wa.x +
               (n1.rgb * 2.0 - vec3(1.0)) * wa.y +
               (n2.rgb * 2.0 - vec3(1.0)) * wa.z;
  local = normalize(dot(local, local) > 1e-12 ? local : d);

  vec3 worldRight = normalize(v_tangent.xyz);
  vec3 worldFacing = normalize(v_normal);
  vec3 worldUp = cross(worldFacing, worldRight);
  s.n = normalize(worldRight * dot(local, right) + worldUp * dot(local, up) +
                  worldFacing * dot(local, d));
  s.n_dot_v = max(dot(s.n, s.v), 1e-4);
  s.albedo = SrgbToLinear(srgb) * SrgbToLinear(frag_info.base_color.rgb);
  s.alpha = 1.0;
  g_albedo = s.albedo;
  s.ambient = mix(frag_info.ambient_ground.rgb, frag_info.ambient_sky.rgb,
                  s.n.y * 0.5 + 0.5) *
              frag_info.material.z;

  vec3 ambient = s.albedo * s.ambient;
  WriteSurface(AccumulateLights(s) + ambient, 1.0, 1.0);
}
