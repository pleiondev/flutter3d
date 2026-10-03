#version 460 core

// One photon of sunlight through a refracting caster — `ShadowSettings.
// caustics`.
//
// **Where the light goes, worked out per photon, and splatted where it
// lands.** The caster has been drawn into two small maps as the sun sees it:
// its near faces and its far faces, each a normal and a depth
// (`caustic_surface.frag`). One photon per texel of that map comes in along
// the light, is bent into the caster by Snell's law at the near face, crosses
// it to the far face — as far as the two depths say, along the bent ray — and
// is bent out again there; it loses what Fresnel reflects at each face and
// what the volume absorbs over the length it travelled, and is lost entirely
// where it meets the far face too steeply to leave. Then it is followed to
// whatever receives it, by stepping along its new direction against the
// atlas's own depth (copied, since the atlas is what this draws into).
//
// **How big its splat is comes from where its neighbours land** — ray
// differentials. The photon one texel over and the one one row down are
// followed too, and the two offsets to where they land span the parallelogram
// this photon's share of the light was spread over: wide and faint where the
// caster spread the beam, small and bright where it gathered it. Its energy
// is divided by that area, so light is neither made nor lost by the splat,
// and a quad is never smaller than a couple of texels, or it could fall
// between texel centres and add nothing.
//
// One instance per photon: the instance index is the texel. A photon that
// starts on no surface, is totally reflected, leaves almost sideways or finds
// no receiver is drawn off the tile.
//
// `textureLod` at texel centres throughout, never `texelFetch`, which the
// Impeller shader compiler does not accept in a vertex stage — see
// `lib/morph.glsl`.

precision highp float;

/// One corner of the photon's quad, from −1 to 1 on each axis.
in vec2 corner;

/// What the photon carries, already divided by the area it covers, in rgb.
/// The particles' names for the particles' pair, which is what a photon is:
/// the varyings are numbered once across every stage, and two new names
/// would be two more for every family to keep apart.
out vec4 v_color;

/// Where in its quad this vertex is, for the falloff.
out vec2 v_uv;

uniform CausticInfo {
  /// The caster's map back to the world, and the world into it: the
  /// cascade's matrix cropped to the caster's footprint, in the convention
  /// the atlas is sampled in (window depth, rows from the top).
  mat4 map_to_world;
  mat4 world_to_map;

  /// The world into the cascade's tile, sampled the same way, and the world
  /// into the tile's clip space, drawn the backend's way.
  mat4 world_to_tile;
  mat4 world_to_clip;

  /// x: photons along each side of the map. y: the least a quad reaches
  /// either way, in clip units. z, w: the spacing of photons across and
  /// down, in clip units.
  vec4 grid;

  /// xyz: the way the light travels, in the world. w unused.
  vec4 light;

  /// x: the caster's index of refraction. y: its reflectance head-on.
  /// z: its attenuation distance, nought for none. w unused.
  vec4 optics;

  /// rgb: its transmission times its base colour. w unused.
  vec4 tint;

  /// rgb: its attenuation colour. w unused.
  vec4 attenuation;
}
caustic_info;

uniform sampler2D caustic_front;
uniform sampler2D caustic_back;
uniform sampler2D caustic_depth;

/// A point's place in a map whose matrix produced [p], rows from the top —
/// the same reading `shadow.glsl` makes of the atlas.
vec2 MapUv(vec4 p) { return vec2(p.x * 0.5 + 0.5, 0.5 - p.y * 0.5); }

float Schlick(float f0, float cosine) {
  float c = clamp(1.0 - cosine, 0.0, 1.0);
  return f0 + (1.0 - f0) * c * c * c * c * c;
}

/// The photon starting at [uv] of the maps, followed to where it lands:
/// xy where, in clip space, and w one if it lands at all. [energy] is what
/// it carries.
vec4 Follow(vec2 uv, out vec3 energy) {
  energy = vec3(0.0);
  vec4 front = textureLod(caustic_front, uv, 0.0);
  if (front.a >= 1.0 || dot(front.xyz, front.xyz) < 0.25) return vec4(0.0);

  vec2 ndc = vec2(uv.x * 2.0 - 1.0, (0.5 - uv.y) * 2.0);
  vec3 entry = (caustic_info.map_to_world * vec4(ndc, front.a, 1.0)).xyz;
  // Metres along the light for one unit of stored depth.
  float range = length((caustic_info.map_to_world * vec4(0.0, 0.0, 1.0, 0.0)).xyz);

  vec3 l = normalize(caustic_info.light.xyz);
  vec3 n1 = normalize(front.xyz);
  if (dot(n1, l) > 0.0) n1 = -n1;
  float index = max(caustic_info.optics.x, 1.0);
  vec3 inside = refract(l, n1, 1.0 / index);

  // A far face behind this texel, or the photon started on the caster's
  // rim, where the two maps disagree about whether there is anything.
  vec4 back = textureLod(caustic_back, uv, 0.0);
  if (back.a <= front.a) return vec4(0.0);
  float across = (back.a - front.a) * range;
  vec3 exit = entry + inside * (across / max(dot(inside, l), 0.2));
  vec4 there = textureLod(
      caustic_back, clamp(MapUv(caustic_info.world_to_map * vec4(exit, 1.0)), 0.0, 1.0), 0.0);
  vec3 n2 = dot(there.xyz, there.xyz) > 0.25 ? normalize(there.xyz) : normalize(back.xyz);
  if (dot(n2, inside) < 0.0) n2 = -n2;
  vec3 out_ray = refract(inside, -n2, index);
  if (dot(out_ray, out_ray) < 1e-6) return vec4(0.0);
  out_ray = normalize(out_ray);
  // Leaving almost sideways it lands far off and faint, and following it
  // there against a depth map is where the search goes wrong.
  if (dot(out_ray, l) < 0.3) return vec4(0.0);

  float f0 = caustic_info.optics.y;
  energy = caustic_info.tint.rgb *
           (1.0 - Schlick(f0, abs(dot(l, n1)))) *
           (1.0 - Schlick(f0, abs(dot(out_ray, n2))));
  float fading = caustic_info.optics.z;
  if (fading > 0.0) {
    energy *= pow(max(caustic_info.attenuation.rgb, vec3(1e-4)),
                  vec3(length(exit - entry) / fading));
  }

  // Out to whatever receives it: step along the ray by what the atlas says
  // is left between here and the first opaque surface below.
  vec3 p = exit;
  float down = max(dot(out_ray, l), 0.05);
  for (int k = 0; k < 4; k++) {
    vec4 q = caustic_info.world_to_tile * vec4(p, 1.0);
    float receiver = textureLod(caustic_depth, clamp(MapUv(q), 0.0, 1.0), 0.0).r;
    float advance = (receiver - q.z) * range / down;
    if (k == 0) advance = max(advance, 0.0);
    p += out_ray * advance;
  }
  // Only where the search settled on a surface.
  vec4 landed = caustic_info.world_to_tile * vec4(p, 1.0);
  float under = textureLod(caustic_depth, clamp(MapUv(landed), 0.0, 1.0), 0.0).r;
  if (abs(under - landed.z) * range > 0.02) return vec4(0.0);

  vec4 clip = caustic_info.world_to_clip * vec4(p, 1.0);
  return vec4(clip.xy / clip.w, 0.0, 1.0);
}

/// [a], made at least [least] long, in its own direction or [fallback]'s.
vec2 AtLeast(vec2 a, vec2 fallback, float least) {
  float size = length(a);
  if (size < 1e-9) return normalize(fallback) * least;
  return size < least ? a * (least / size) : a;
}

void main() {
  v_uv = corner;
  v_color = vec4(0.0);
  // Off the tile until it is known to land somewhere.
  gl_Position = vec4(4.0, 4.0, 0.5, 1.0);

  float n = caustic_info.grid.x;
  float id = float(gl_InstanceIndex);
  float column = mod(id, n);
  float row = floor(id / n);
  vec2 uv = vec2((column + 0.5) / n, (row + 0.5) / n);
  float texel = 1.0 / n;

  vec3 energy;
  vec4 here = Follow(uv, energy);
  if (here.w < 0.5) return;

  // Where the neighbours land, one texel across and one down — or the
  // other way, where this photon is on the edge — or, failing both, where
  // they would have landed with nothing in the way.
  vec2 spacing_x = vec2(caustic_info.grid.z, 0.0);
  vec2 spacing_y = vec2(0.0, caustic_info.grid.w);
  vec3 unused;
  vec4 next_x = Follow(uv + vec2(texel, 0.0), unused);
  vec2 a = next_x.w > 0.5 ? next_x.xy - here.xy : spacing_x;
  if (next_x.w < 0.5) {
    vec4 prev_x = Follow(uv - vec2(texel, 0.0), unused);
    if (prev_x.w > 0.5) a = here.xy - prev_x.xy;
  }
  vec4 next_y = Follow(uv + vec2(0.0, texel), unused);
  vec2 b = next_y.w > 0.5 ? next_y.xy - here.xy : spacing_y;
  if (next_y.w < 0.5) {
    vec4 prev_y = Follow(uv - vec2(0.0, texel), unused);
    if (prev_y.w > 0.5) b = here.xy - prev_y.xy;
  }
  // **Stretched past sixteen times its own spacing either way, left out.**
  // Its light is spread a two-hundred-and-fiftieth as thin as where it set
  // out, so it shows nothing; drawn, a photon whose neighbour landed across
  // the tile was a quad over most of it, and the hundreds of them at a
  // liquid's rim, where the light leaves edge-on, cost more than the rest
  // of the frame together once the bench was in the map for them to land.
  if (length(a) > 16.0 * caustic_info.grid.z ||
      length(b) > 16.0 * caustic_info.grid.w) {
    return;
  }
  // Half again, so neighbouring quads overlap, and never under the least.
  float least = caustic_info.grid.y;
  a = AtLeast(1.5 * a, spacing_x, least);
  b = AtLeast(1.5 * b, spacing_y, least);
  float area = max(abs(a.x * b.y - a.y * b.x), least * least);

  gl_Position = vec4(here.xy + corner.x * a + corner.y * b, 0.5, 1.0);
  // The photon's own share of the light, over what the falloff covers:
  // (1 − r²)² integrates to π/3 of the area the quad's disc maps to.
  float share = caustic_info.grid.z * caustic_info.grid.w;
  v_color = vec4(energy * share / (1.0471976 * area), 0.0);
}
