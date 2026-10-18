#version 460 core

// A high-contrast look with outlines — `N9`, an accommodation for players who
// see little contrast or little detail.
//
// **Three things, in the order a player with low vision needs them.** The
// texture detail inside each surface is flattened away, so a wall is one tone
// rather than a field of mortar lines competing with what stands in front of
// it; the result is pushed apart in tone and drained of most of its colour, so
// the world reads as shapes in greys; and every edge the geometry has is drawn
// as a line, with whatever a game marked — its monsters, its pickups — ringed
// in the colour that role has. That last part is the information: a grey world
// with orange around what can hurt you is the arrangement the games that do
// this well have converged on, because colour then means one thing.
//
// **The flattening is a cross bilateral filter, guided by the surface buffer
// rather than by the picture.** An edge-preserving blur has to decide what an
// edge is. Decide it from the colour, as a bilateral or a Kuwahara filter on
// the picture does, and the mortar between two stones *is* an edge, so the
// texture survives the filter that was meant to remove it. Decide it from the
// geometry and the question becomes the right one: a tap is averaged in when
// it lies on the same surface — near the same depth, facing the same way — and
// left out when it does not. Texture lives within a surface and shape lives
// between surfaces, so this removes exactly the first and keeps the second,
// with no threshold on colour at all. Twenty-five taps of two textures on a
// fixed five-by-five grid: a box rather than a Gaussian, because the weights
// are already all-or-nothing and the cost is the fetches, not the arithmetic.
//
// **The outline reads depth and normal, as `viewport_shade.frag`'s does, but
// asks a different question of the depth.** The modeller's outline thresholds
// the step between neighbours in metres, which is right for an object in front
// of a camera and wrong for a corridor: a floor receding from the eye steps
// further between neighbours the further away it is, and a threshold in metres
// draws its far half as one solid line. A plane's depth changes *linearly*
// across the screen, so its second difference is near nought however steep it
// is, and a silhouette or a step is where that stops being true. Measured as a
// share of the depth, so it means the same at one metre and at thirty.
//
// After the composite and the antialias, as the viewport shading is: the lines
// are about the finished picture and must not be blurred, and the colours are
// display-referred, so a role colour comes out as the colour the player chose.
//
// `textureLod` throughout, for `viewport_shade.frag`'s reason: most reads here
// sit behind a branch on a per-fragment depth, which a WGSL backend refuses an
// implicit derivative under, and every texture is read at its own size.

in vec2 v_uv;

out vec4 frag_color;

uniform sampler2D scene_texture;
uniform sampler2D surface_texture;
uniform sampler2D mask_texture;

uniform HighContrastInfo {
  // x: how much of the surface's mean replaces each pixel, nought to one.
  // y: the gain on tone about mid grey. z: how much colour is kept, nought
  // to one. w: how much of a marked node's own colour is laid over it.
  vec4 look;

  // x: how far depth may bend, as a share of itself per tap, before it is
  // another surface — the outline's threshold and the flattening's both.
  // y: how far apart two normals must be to count as an edge, as one minus
  // their cosine. z: the outline's reach in pixels, nought for none.
  // w: how far apart the flattening's taps are, in pixels.
  vec4 edges;

  // rgb: the outline's colour, display-referred. w: how wide the ring round
  // a marked node is, in pixels, nought for none.
  vec4 line;

  // xy: one texel. z: one when the surface buffer is bound, nought when the
  // device could not make one. w: one when the mask is bound.
  vec4 screen;
}
contrast_info;

// The octahedral decode every reader of the surface buffer keeps — see
// `ssao.frag`, which carries the argument for the encoding.
vec3 DecodeOctahedral(vec2 e) {
  e = e * 2.0 - 1.0;
  vec3 n = vec3(e.xy, 1.0 - abs(e.x) - abs(e.y));
  float t = max(-n.z, 0.0);
  n.x += n.x >= 0.0 ? -t : t;
  n.y += n.y >= 0.0 ? -t : t;
  return normalize(n);
}

/// How far [centre] bends away from the line through [a] and [b], the taps
/// either side of it, as a share of its own depth. A background tap on
/// either side is a silhouette, which is as bent as depth gets.
float DepthBend(float a, float centre, float b) {
  if (a <= 0.0 || b <= 0.0) return 1e6;
  return abs(a + b - 2.0 * centre) / centre;
}

void main() {
  vec4 scene = textureLod(scene_texture, v_uv, 0.0);
  vec3 colour = scene.rgb;
  vec2 texel = contrast_info.screen.xy;
  bool hasSurface = contrast_info.screen.z > 0.5;
  bool hasMask = contrast_info.screen.w > 0.5;

  vec4 surface = vec4(0.0);
  if (hasSurface) surface = textureLod(surface_texture, v_uv, 0.0);
  float depth = surface.a;
  vec3 normal =
      depth > 0.0 ? DecodeOctahedral(surface.rg) : vec3(0.0, 0.0, 1.0);
  float bend = max(contrast_info.edges.x, 1e-4);
  float turn = max(contrast_info.edges.y, 1e-4);

  // **Flatten**: the mean of the taps that lie on this pixel's surface. The
  // centre always does, so the mean is never of nothing.
  float flatten = clamp(contrast_info.look.x, 0.0, 1.0);
  if (depth > 0.0 && flatten > 0.0) {
    vec2 spacing = texel * max(contrast_info.edges.w, 1.0);
    vec3 sum = vec3(0.0);
    float count = 0.0;
    for (int y = -2; y <= 2; y++) {
      for (int x = -2; x <= 2; x++) {
        vec2 uv = v_uv + vec2(float(x), float(y)) * spacing;
        vec4 tap = textureLod(surface_texture, uv, 0.0);
        // A tap two steps out may sit twice as far from this depth along a
        // plane and still be the same surface, so the allowance grows with
        // the ring the tap is on.
        float ring = float(max(abs(x), abs(y)));
        bool same = tap.a > 0.0 &&
                    abs(tap.a - depth) <= bend * depth * max(ring, 1.0) &&
                    1.0 - dot(DecodeOctahedral(tap.rg), normal) < turn;
        if (same) {
          sum += textureLod(scene_texture, uv, 0.0).rgb;
          count += 1.0;
        }
      }
    }
    if (count > 0.0) colour = mix(colour, sum / count, flatten);
  }

  // **Tone**: drained toward its luma, then pushed apart about mid grey. The
  // luma of the display-referred value, Rec. 709's weights, which is what a
  // grey that looks as light as the colour it replaced is.
  float luma = dot(colour, vec3(0.2126, 0.7152, 0.0722));
  colour = mix(vec3(luma), colour, clamp(contrast_info.look.z, 0.0, 1.0));
  colour = clamp((colour - 0.5) * max(contrast_info.look.y, 0.0) + 0.5,
                 vec3(0.0), vec3(1.0));

  // **Outline**, wherever the geometry steps or turns.
  float reach = contrast_info.edges.z;
  if (depth > 0.0 && reach > 0.0) {
    vec2 dx = vec2(texel.x * reach, 0.0);
    vec2 dy = vec2(0.0, texel.y * reach);
    vec4 left = textureLod(surface_texture, v_uv - dx, 0.0);
    vec4 right = textureLod(surface_texture, v_uv + dx, 0.0);
    vec4 up = textureLod(surface_texture, v_uv - dy, 0.0);
    vec4 down = textureLod(surface_texture, v_uv + dy, 0.0);
    // At the frame's border one tap of a pair is clamped back onto this
    // pixel, and the bend of a pair holding the centre twice is just the
    // other step — the very test this outline exists not to make, which drew
    // a line along the bottom row of every floor. An axis whose tap falls off
    // the frame is left out.
    bool across = v_uv.x - dx.x >= 0.0 && v_uv.x + dx.x <= 1.0;
    bool along = v_uv.y - dy.y >= 0.0 && v_uv.y + dy.y <= 1.0;
    float bent = max(across ? DepthBend(left.a, depth, right.a) : 0.0,
                     along ? DepthBend(up.a, depth, down.a) : 0.0);
    // A background neighbour has no normal to compare, and the depth above
    // has already called it an edge.
    float turned = 0.0;
    if (left.a > 0.0) {
      turned = max(turned, 1.0 - dot(DecodeOctahedral(left.rg), normal));
    }
    if (right.a > 0.0) {
      turned = max(turned, 1.0 - dot(DecodeOctahedral(right.rg), normal));
    }
    if (up.a > 0.0) {
      turned = max(turned, 1.0 - dot(DecodeOctahedral(up.rg), normal));
    }
    if (down.a > 0.0) {
      turned = max(turned, 1.0 - dot(DecodeOctahedral(down.rg), normal));
    }
    if (bent >= bend || turned >= turn) colour = contrast_info.line.rgb;
  }

  // **Roles**: a marked node keeps a share of its own colour inside, and is
  // ringed in it outside. Outside only — a pixel the mask holds is the node,
  // and drawing the ring over it would eat the shape it is meant to show.
  float ringWidth = contrast_info.line.w;
  if (hasMask) {
    vec4 own = textureLod(mask_texture, v_uv, 0.0);
    if (own.a > 0.5) {
      colour = mix(colour, own.rgb, clamp(contrast_info.look.w, 0.0, 1.0));
    } else if (ringWidth > 0.0) {
      // The nearest marked pixel within the ring's width, in eight
      // directions, nearer rings first, so two marks close together each
      // keep their own colour up to the middle of the gap.
      vec2 directions[8] = vec2[8](
          vec2(1.0, 0.0), vec2(-1.0, 0.0), vec2(0.0, 1.0), vec2(0.0, -1.0),
          vec2(1.0, 1.0), vec2(-1.0, 1.0), vec2(1.0, -1.0), vec2(-1.0, -1.0));
      vec4 found = vec4(0.0);
      for (int i = 1; i <= 4; i++) {
        if (float(i) <= ringWidth && found.a < 0.5) {
          for (int d = 0; d < 8; d++) {
            vec4 tap = textureLod(mask_texture,
                                  v_uv + directions[d] * texel * float(i), 0.0);
            if (found.a < 0.5 && tap.a > 0.5) found = tap;
          }
        }
      }
      if (found.a > 0.5) colour = found.rgb;
    }
  }

  frag_color = vec4(colour, scene.a);
}
