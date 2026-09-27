#version 460 core

// Volumetric fog, marched at half resolution — `S4`.
//
// **The light shafts' march, given a medium.** `light_shafts.frag` asks the
// shadow map at each step whether a point in the air is lit and adds the sun
// it scatters. This asks the same question and three more: how thick the air
// is at that height, which of the view's clustered lights reach that point,
// and how much of what lies behind it is still seen through what the ray has
// crossed. What comes out is not a colour to add but a pair — the light the
// air sends towards the eye, and the share of the scene that survives it —
// which `volumetric_fog_upsample.frag` lays over the full-resolution picture.
//
// **Half resolution, and that is what the upsample is for.** Fog varies
// slowly across the screen except where the depth jumps, so a quarter of the
// rays carry nearly all of the picture; the upsample weighs each of the four
// nearest by how close its depth is to the pixel's own, which keeps a torch's
// halo from bleeding over the edge of the wall in front of it.
//
// **The start is offset by the engine's noise.** The fixed 4 × 4 pattern
// without a temporal resolve, R3's blue noise with one — the history then
// averages the next slice every frame into the integral the steps sample.

#include <lib/frag_coord_info.glsl>
#include <lib/blue_noise.glsl>

in vec2 v_uv;

out vec4 frag_color;

uniform sampler2D surface_texture;
uniform sampler2D shadow_texture;
uniform sampler2D light_list_texture;

// The cube atlas the lit draws read, and the block they read it through —
// `PointShadow` as `surface.glsl` declares it, member for member, because a
// block is one layout whichever stage names it. The march reads the atlas
// rows, the face matrices and the frame's numbers; the slot table is a draw's
// and goes unread here, since a light's row rides in its list row.
uniform sampler2D point_shadow_texture;
uniform sampler2D point_shadow_static_texture;

// `kShadowSlots` and `kMaxLights` from `surface.glsl`.
#define kFogShadowSlots 6
#define kFogSlotLights 8

uniform PointShadow {
  mat4 faces[6 * kFogShadowSlots];
  vec4 lights[kFogShadowSlots];
  vec4 slots[kFogSlotLights];
  vec4 params;
  vec4 params2;
  vec4 params3;
}
point_shadow;

// The most lights one step of the march reads from its cell. A cell lists
// every light whose range reaches into it, and a loop a scene can lengthen
// without limit is a hang rather than a slow frame.
#define kFogCellLights 16

uniform VolumeFogInfo {
  // Screen to world, for turning a stored depth back into a point.
  mat4 inverse_view_projection;

  // The three cascade matrices, world to light clip, as `ShaftInfo` has them.
  mat4 shadow_matrix;
  mat4 shadow_matrix_far;
  mat4 shadow_matrix_farthest;

  // `L6`: the view-projection the light clusters were cut with, so a step
  // finds its cell the way `LightClusters.clusterOf` does.
  mat4 cluster_view_projection;

  // xyz: where the eye is. w: how far to march, in world metres.
  vec4 camera;

  // xyz: the direction the camera looks. w: how many steps.
  vec4 forward;

  // xyz: towards the sun, a unit vector. w: Henyey–Greenstein's g.
  vec4 sun;

  // rgb: the sun's colour times its intensity, times the air's albedo;
  // nought with no directional light. w unused.
  vec4 sun_radiance;

  // x, y: the two cascade split distances. z: how many cascades, nought when
  // there is no shadow map and every point is lit. w unused.
  vec4 cascades;

  // x, y, z: each cascade's depth bias. w unused.
  vec4 bias;

  // x: the air's extinction σ at the base height, per metre. y: how fast it
  // thins with height, per metre. z: the base height. w unused.
  vec4 medium;

  // rgb: the air's albedo, which tints what the clustered lights scatter.
  // w: one when the cells are there to read, nought otherwise.
  vec4 albedo;

  // rgb: light reaching the air from every direction, times the albedo —
  // what keeps fog in shadow from reading as a black wall. w unused.
  vec4 ambient;

  // xyz: tiles across, tiles up, slices deep. w unused.
  vec4 cluster_grid;

  // x: where slices begin, in clip w. y: slices per unit of `ln(w / x)`.
  // z: the row the cells' headers start at. w: the row their entries start at.
  vec4 cluster_depth;

  // x, y: one over the light list texture's width and height. zw unused.
  vec4 list;
}
fog_info;

// How much of the light a point in the air sends along [cosine] from the
// light's direction — Henyey–Greenstein, normalised over the sphere, as in
// `light_shafts.frag`.
float HenyeyGreenstein(float cosine, float g) {
  float g2 = g * g;
  float denominator = max(1.0 + g2 - 2.0 * g * cosine, 1e-4);
  return (1.0 - g2) / (12.566371 * denominator * sqrt(denominator));
}

// The air's extinction at height [y]: σ at the base, thinning exponentially
// above it and thickening below. The exponent is clamped so a camera far
// below the base height reads very thick fog rather than an infinity.
float Density(float y) {
  float exponent = clamp(-fog_info.medium.y * (y - fog_info.medium.z),
                         -30.0, 30.0);
  return max(fog_info.medium.x, 0.0) * exp(exponent);
}

// Whether [world] is lit by the sun: `LitAt` from `light_shafts.frag`, one
// tap per cascade walk. With no map (`cascades.z` nought) everything is lit.
float LitAt(vec3 world, float viewDistance) {
  int cascadeCount = int(fog_info.cascades.z + 0.5);
  int cascade = 0;
  if (cascadeCount > 1 && viewDistance > fog_info.cascades.x) cascade = 1;
  if (cascadeCount > 2 && viewDistance > fog_info.cascades.y) cascade = 2;

  for (int attempt = 0; attempt < 3; attempt++) {
    int which = cascade + attempt;
    if (which >= cascadeCount) break;

    mat4 matrix = which == 0
        ? fog_info.shadow_matrix
        : (which == 1 ? fog_info.shadow_matrix_far
                      : fog_info.shadow_matrix_farthest);
    vec4 lightSpace = matrix * vec4(world, 1.0);
    if (lightSpace.w <= 0.0) continue;
    vec3 candidate = lightSpace.xyz / lightSpace.w;

    vec2 inTile = vec2(candidate.x * 0.5 + 0.5, 0.5 - candidate.y * 0.5);
    if (inTile.x < 0.0 || inTile.x > 1.0 || inTile.y < 0.0 || inTile.y > 1.0) {
      continue;
    }
    if (candidate.z > 1.0) {
      if (which < cascadeCount - 1) continue;
      candidate.z = 1.0;
    }

    vec2 uv = vec2((inTile.x + float(which)) / float(cascadeCount), inTile.y);
    float stored = textureLod(shadow_texture, uv, 0.0).r;
    float bias = which == 0
        ? fog_info.bias.x
        : (which == 1 ? fog_info.bias.y : fog_info.bias.z);
    return candidate.z - bias > stored ? 0.0 : 1.0;
  }
  return 1.0;
}

// How lit [world] is by the light whose list row ends in [cone]: one tap of
// its atlas row, without a normal to offset along — a point in the air has
// none — and so without the filter the surfaces use either. A soft edge in
// the air comes from the march's jitter, and nine taps a step per light would
// be the whole budget of the pass.
//
// `cone.z` is the atlas row plus one, nought for a light that holds none;
// `cone.w` is one for a spot's single tile. The face, the flip and the pair of
// atlases are `PointShadowFactor`'s and `PointShadowDistance`'s.
float LocalLitAt(vec3 world, vec4 cone) {
  float strength = point_shadow.params.z;
  if (cone.z < 0.5 || strength <= 0.0) return 1.0;
  int slot = int(cone.z - 0.5);
  vec3 toFragment = world - point_shadow.lights[slot].xyz;
  float distance = length(toFragment);
  float range = max(point_shadow.lights[slot].w, 1e-4);
  if (distance >= range) return 1.0;

  int face = 0;
  if (cone.w < 0.5) {
    vec3 a = abs(toFragment);
    if (a.x >= a.y && a.x >= a.z) {
      face = toFragment.x > 0.0 ? 0 : 1;
    } else if (a.y >= a.z) {
      face = toFragment.y > 0.0 ? 2 : 3;
    } else {
      face = toFragment.z > 0.0 ? 4 : 5;
    }
  }

  vec4 clip = point_shadow.faces[slot * 6 + face] * vec4(world, 1.0);
  if (clip.w <= 0.0) return 1.0;
  vec2 ndc = clip.xy / clip.w;
  if (abs(ndc.x) > 1.0 || abs(ndc.y) > 1.0) return 1.0;
  vec2 uv = vec2(ndc.x * 0.5 + 0.5, 0.5 - ndc.y * 0.5);
  float inset = point_shadow.params.x;
  vec2 local = clamp(uv, inset, 1.0 - inset);
  vec2 atlas = (local + vec2(float(face), float(slot))) *
               vec2(1.0 / 6.0, 1.0 / float(kFogShadowSlots));
  if (point_shadow.params3.x > 0.5) atlas.y = 1.0 - atlas.y;
  // Level zero by name: this stands behind the slot test and the light loop's
  // own branches, where WGSL takes no implicit derivative.
  float stored = min(textureLod(point_shadow_texture, atlas, 0.0).r,
                     textureLod(point_shadow_static_texture, atlas, 0.0).r) *
                 range;
  // Nothing was drawn in that direction by either, so nothing is in the way.
  if (stored >= range * 0.999) return 1.0;
  float lit = distance - point_shadow.params.y > stored ? 0.0 : 1.0;
  return mix(1.0, lit, clamp(strength, 0.0, 1.0));
}

// One texel of the light list texture, [texel] across and [row] down.
vec4 ListTexel(float texel, float row) {
  return textureLod(light_list_texture,
                    vec2((texel + 0.5) * fog_info.list.x,
                         (row + 0.5) * fog_info.list.y),
                    0.0);
}

// One lane of a four-vector.
float Lane(vec4 four, float lane) {
  return lane < 0.5 ? four.x
                    : (lane < 1.5 ? four.y : (lane < 2.5 ? four.z : four.w));
}

// What the clustered lights whose cell holds [world] send towards the eye
// along [along], before the albedo and the path.
//
// `FindCluster` and `ClusterRow` from `surface.glsl`, with nothing of a draw
// in them: a cell lists every light that reaches it, and the air has no
// slots holding some of them already. A light that owns a row of the cube
// atlas is shadowed through it, so a torch behind a wall lights no air on
// this side of the wall. Points and spots only — a rectangle's
// intensity is spread over its area in a way a point in the air has no
// normal to integrate against, and a directional light is the sun's job.
vec3 ClusterLight(vec3 world, vec3 along, float g) {
  vec4 clip = fog_info.cluster_view_projection * vec4(world, 1.0);
  vec2 ndc = clip.xy / max(clip.w, 1e-6);
  vec3 grid = fog_info.cluster_grid.xyz;
  float near = fog_info.cluster_depth.x;
  float tx = clamp(floor((ndc.x * 0.5 + 0.5) * grid.x), 0.0, grid.x - 1.0);
  float ty = clamp(floor((ndc.y * 0.5 + 0.5) * grid.y), 0.0, grid.y - 1.0);
  float tz = clip.w <= near
                 ? 0.0
                 : clamp(floor(log(clip.w / near) * fog_info.cluster_depth.y),
                         0.0, grid.z - 1.0);
  float cell = tx + ty * grid.x + tz * grid.x * grid.y;
  float headerRow = floor(cell / 4.0);
  vec4 header =
      ListTexel(cell - headerRow * 4.0, fog_info.cluster_depth.z + headerRow);
  int count = int(header.y + 0.5);

  vec3 total = vec3(0.0);
  for (int i = 0; i < kFogCellLights; i++) {
    if (i >= count) break;
    float entry = header.x + float(i);
    float entryRow = floor(entry / 16.0);
    float within = entry - entryRow * 16.0;
    float texel = floor(within / 4.0);
    vec4 four = ListTexel(texel, fog_info.cluster_depth.w + entryRow);
    float row = Lane(four, within - texel * 4.0);

    vec4 position = ListTexel(0.0, row);
    vec4 color = ListTexel(1.0, row);
    vec4 direction = ListTexel(2.0, row);
    vec4 cone = ListTexel(3.0, row);
    float type = position.w;
    vec3 toLight = position.xyz - world;
    float distance = length(toLight);
    // Points and spots, at a distance with a direction.
    float usable = (type > 0.5 && type < 2.5 && distance > 1e-4) ? 1.0 : 0.0;
    vec3 l = toLight / max(distance, 1e-4);

    // `PunctualAttenuation` from `surface.glsl`.
    float attenuation = 1.0 / max(distance * distance, 1e-4);
    if (direction.w > 0.0) {
      float ratio = distance / direction.w;
      float window = clamp(1.0 - ratio * ratio * ratio * ratio, 0.0, 1.0);
      attenuation *= window * window;
    }
    // Spots only: a rectangle's `cone` holds an edge, not two cosines, and
    // the ramp over it could divide by nought into a NaN the `usable`
    // multiply would not clear.
    if (type > 1.5 && type < 2.5) {
      float cosAngle = dot(normalize(direction.xyz), -l);
      attenuation *= clamp((cosAngle - cone.y) / (cone.x - cone.y), 0.0, 1.0);
    }
    // Asked only of a light that reaches here, since it costs two reads.
    float visibility = attenuation * usable > 0.0 ? LocalLitAt(world, cone) : 1.0;
    total += color.rgb * (color.w * attenuation * usable * visibility *
                          HenyeyGreenstein(dot(along, l), g));
  }
  return total;
}

void main() {
  int steps = int(fog_info.forward.w + 0.5);

  // Where the ray starts and which way it goes.
  vec2 xy = vec2(v_uv.x * 2.0 - 1.0, 1.0 - v_uv.y * 2.0);
  vec4 nearH = fog_info.inverse_view_projection * vec4(xy, 0.0, 1.0);
  vec4 farH = fog_info.inverse_view_projection * vec4(xy, 1.0, 1.0);
  vec3 nearPoint = nearH.xyz / nearH.w;
  vec3 along = normalize(farH.xyz / farH.w - nearPoint);
  float cosine = max(dot(along, fog_info.forward.xyz), 1e-4);

  // **From the eye's plane, not the near plane.** The surface buffer's depth
  // is measured from the eye, so a march starting at the near plane and
  // running that depth ends the near distance behind the surface — inside
  // the wall, where a torch on its far side still reaches, and the one step
  // there glowed through the stone. Stepped back along the ray to where the
  // depth is nought: the eye itself for a perspective view.
  vec3 origin = nearPoint -
                along * (dot(nearPoint - fog_info.camera.xyz,
                             fog_info.forward.xyz) /
                         cosine);

  // How far there is air, as `light_shafts.frag` measures it: the surface
  // buffer's depth along the view axis over the cosine to this ray.
  float surfaceDepth = texture(surface_texture, v_uv).a;
  float toSurface = surfaceDepth > 0.0 ? surfaceDepth / cosine : 1e9;
  float distance = min(fog_info.camera.w, toSurface);
  if (steps < 1 || distance <= 0.0) {
    frag_color = vec4(0.0, 0.0, 0.0, 1.0);
    return;
  }

  float stride = distance / float(steps);
  float offset = PixelNoise(TargetFragCoord()) * stride;

  // **Single scattering with transmittance, per step.** A step of length
  // `stride` at extinction σ catches `1 − e^(−σ·stride)` of the light that
  // reaches it and passes on `e^(−σ·stride)` of what is behind it; the light
  // it catches is weighted by what is left of the path to the eye. Each
  // sample stands for one stride of the ray, placed at the offset within it,
  // so the strides add up to the distance exactly and a wall seen through
  // uniform air keeps `e^(−σd)` of itself whatever the noise says.
  float g = fog_info.sun.w;
  float sunPhase = HenyeyGreenstein(dot(along, fog_info.sun.xyz), g);
  bool clustered = fog_info.albedo.w > 0.5;
  vec3 eye = fog_info.camera.xyz;
  float transmittance = 1.0;
  vec3 inscatter = vec3(0.0);
  for (int i = 0; i < 64; i++) {
    if (i >= steps) break;
    float travelled = offset + float(i) * stride;
    vec3 at = origin + along * travelled;
    float stepTransmittance = exp(-Density(at.y) * stride);

    vec3 light = fog_info.sun_radiance.rgb *
                     (sunPhase * LitAt(at, length(at - eye))) +
                 fog_info.ambient.rgb * 0.07957747;
    if (clustered) {
      light += fog_info.albedo.rgb * ClusterLight(at, along, g);
    }
    inscatter += light * (transmittance * (1.0 - stepTransmittance));
    transmittance *= stepTransmittance;
  }

  frag_color = vec4(inscatter, transmittance);
}
