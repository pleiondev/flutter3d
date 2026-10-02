#version 460 core

// Lens flare, added to the glow — `P2`.
//
// A bright light in the frame reflects between the elements of a lens and
// lands again as a row of ghosts on the line through the middle of the
// frame, on the far side, and as a ring round the middle. Both are drawn
// here from the glow itself: the bloom chain has already picked out what is
// bright and spread it, so reading it at the mirrored positions is what puts
// a ghost where the light's reflection would fall, and nothing that is not
// bright enough to bloom ever flares.
//
// Each ghost is weighted by how near the middle it lands, so ghosts thin out
// towards the edges and one that would land outside the frame is not drawn
// — no wrapping round, which reads as a light on the wrong side. The three
// channels are taken a little apart along the ghost's line, which is the
// colour fringe a coated lens leaves on its reflections.
//
// Drawn into the glow rather than into the picture so the composite adds it
// with the glow, at the glow's own intensity and before the tone map: a
// flare is light, and it saturates the way the rest of the light does.
//
// `flutter3d_cpu`'s `LensFlareShader` is this, line for line.
precision highp float;

in vec2 v_uv;

out vec4 frag_color;

/// The glow, as the bloom chain finished it.
uniform sampler2D bloom_texture;

uniform LensFlareInfo {
  /// x: how much flare, against the glow it is drawn from. y: how many
  /// ghosts, up to eight. z: how far apart they fall, as a fraction of the
  /// way from the light to the middle. w: the halo's radius, as a fraction
  /// of the frame's height.
  vec4 params;

  /// x: how far apart the channels of a ghost are taken, in uv. y: the
  /// halo's strength against the ghosts'. z: the frame's aspect, width over
  /// height. w: unclaimed.
  vec4 more;
}
lens_flare_info;

/// The glow at [at], its channels taken [spread] apart along [along].
vec3 Fringed(vec2 at, vec2 along, float spread) {
  return vec3(textureLod(bloom_texture, at + along * spread, 0.0).r,
              textureLod(bloom_texture, at, 0.0).g,
              textureLod(bloom_texture, at - along * spread, 0.0).b);
}

/// How much a reflection landing at [at] keeps: all of it in the middle,
/// falling off to nothing at the corners and beyond.
float Falloff(vec2 at, float power) {
  float d = length(vec2(0.5) - at) / 0.70710678;
  return pow(max(1.0 - d, 0.0), power);
}

void main() {
  vec3 glow = textureLod(bloom_texture, v_uv, 0.0).rgb;
  float intensity = lens_flare_info.params.x;
  // The reflection of the point at `v_uv` lands on the far side of the
  // middle, so a ghost at `v_uv` comes from the light at `flipped`.
  vec2 flipped = vec2(1.0) - v_uv;
  vec2 towardMiddle = (vec2(0.5) - flipped) * lens_flare_info.params.z;
  float reach = length(towardMiddle);
  vec2 along = reach > 1e-6 ? towardMiddle / reach : vec2(0.0);
  float spread = lens_flare_info.more.x;

  vec3 flare = vec3(0.0);
  int ghosts = int(lens_flare_info.params.y + 0.5);
  for (int i = 0; i < 8; i++) {
    if (i >= ghosts) break;
    vec2 at = flipped + towardMiddle * float(i);
    flare += Fringed(at, along, spread) * Falloff(at, 10.0);
  }

  // The ring: every light at one radius from the middle lands on it.
  float aspect = max(lens_flare_info.more.z, 1e-4);
  vec2 halo = along * vec2(1.0 / aspect, 1.0) * lens_flare_info.params.w;
  vec2 haloAt = flipped + halo;
  flare += Fringed(haloAt, along, spread) * Falloff(haloAt, 5.0) *
           lens_flare_info.more.y;

  frag_color = vec4(glow + flare * intensity, 1.0);
}
