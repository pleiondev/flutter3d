#version 460 core

// The depth pre-draw: a surface's depth, where it covers the pixel, and no
// colour — `A1.2`, `A1.3`.
//
// **Where the cut is made so the lit stage need not make it.** A masked
// material's alpha cut and a hashed one's noise are a `discard`, and a stage
// that may discard turns off early depth and hidden-surface removal for its
// whole draw. So a masked, hashed or cross-fading draw is drawn twice: once
// through this, which makes the cut and writes depth, and once through the
// lit model's opaque variant (`pbr_opaque.frag`), tested `equal`, which
// shades exactly what this left and nothing it threw away. The expensive
// stage keeps its early depth; the cheap one pays for the `discard`.
//
// **The cut is the lit stage's own, to the texel.** The base colour map read
// with the same coordinate, the same sampler and the same level bias, its
// alpha times the material's and the vertex colour's, against the same
// cutoff; the hashed noise is `surface.glsl`'s, anchored to the same world
// position. A pixel this keeps and the lit stage would have thrown away, or
// the other way round, would be a hole or a speck at the edge of every leaf.
//
// **And a level of detail's share of the pixels — `A1.3`.** Two levels of one
// object cross-fade by splitting the pixels between them through one pattern:
// the finer takes the low end of it and the coarser the high end, so each
// pixel is covered by exactly one, and the share each takes follows the fade.
// Opaque surfaces have no other way to fade without sorting.
//
// One output and a blend that keeps what is there, as the x-ray marks are
// drawn: colour is the lit draw's to write. `F3D_NO_SURFACE_BUFFER` for that
// reason — a declared second output would be written whatever the blend.
precision highp float;

#define F3D_NO_SURFACE_BUFFER
#define F3D_NO_FOG
#include <lib/color.glsl>

/// The base colour map, whose alpha is the mask: the lit stage's own slot.
uniform sampler2D base_color_texture;

uniform PredrawInfo {
  /// x: the cutoff the lit stage reads from `FragInfo.material2.x` — at
  /// nought or above a mask, below -1.5 hashed, anything else no cut.
  /// y: the base colour's alpha, the node's tint folded in. z: the share of
  /// the pixels a cross-fading level keeps — positive from the low end of the
  /// pattern, negative from the high end, one for all of them. w: the level
  /// bias the lit stage reads its maps with, `MaterialLodBias`.
  vec4 mask;
}
predraw_info;

/// `surface.glsl`'s noise for a hashed cut, to the operation — that stage's
/// block is not declared here, and a pixel kept by one and thrown away by
/// the other would be a speck or a hole. See `HashedAlphaNoise` there.
float HashedAlphaNoise(vec3 scenePosition, float cutoff) {
  float key = -2.0 - cutoff;
  vec3 origin = vec3(floor(key / 16384.0), mod(floor(key / 128.0), 128.0),
                     mod(key, 128.0));
  vec3 cell = mod(floor(scenePosition * 16.0) + origin, 128.0);
  vec3 p3 = fract(cell * 0.1031);
  p3 += dot(p3, p3.zyx + 31.32);
  return fract((p3.x + p3.y) * p3.z);
}

/// Interleaved gradient noise at the pixel, in [0, 1): a pattern that spreads
/// any share of the pixels evenly at every scale, which is what keeps a fade
/// from reading as a screen door.
float FadePattern() {
  return fract(52.9829189 *
               fract(dot(gl_FragCoord.xy, vec2(0.06711056, 0.00583715))));
}

void main() {
  float cutoff = predraw_info.mask.x;
  if (cutoff >= 0.0 && cutoff <= 1.0) {
    float alpha = texture(base_color_texture, v_texcoord, predraw_info.mask.w).a *
                  predraw_info.mask.y * v_color.a;
    if (alpha < cutoff) discard;
  } else if (cutoff < -1.5) {
    float alpha = texture(base_color_texture, v_texcoord, predraw_info.mask.w).a *
                  predraw_info.mask.y * v_color.a;
    if (alpha < HashedAlphaNoise(v_world_position, cutoff)) discard;
  }

  float share = predraw_info.mask.z;
  if (share < 1.0) {
    float pattern = FadePattern();
    bool kept = share >= 0.0 ? pattern < share : pattern >= 1.0 + share;
    if (!kept) discard;
  }
  frag_color = vec4(0.0);
}
