#version 460 core

// The shadow pass for a cut-out caster: write depth, or write nothing —
// `gfx-60n`.
//
// **A separate stage rather than a branch in `shadow_depth.frag`.** Every
// caster that is not cut out keeps the stage it has always had, which is a
// pipeline with no sampler in it and no texture bound per draw. That is worth
// a second entry point twice over: the common path pays nothing, and the
// forty-four golden frames recorded against the old stage cannot move, because
// the old stage is still the one they go through — the same split other
// engines draw here, for the same reason.
//
// **Why the shadow pass has to know about alpha at all.** A leaf card is a
// quad with a texture that is transparent almost everywhere. Depth-only, that
// quad is opaque, so a tree casts the shadow of its bounding rectangles — a
// stack of dark slabs where the eye expects dappled light. Nothing about the
// lit pass can repair it, because by then the shadow map already says the
// ground is in shadow.
//
// The threshold is the material's own `alphaCutoff` and the comparison is the
// same one glTF's MASK mode specifies: alpha below the cutoff is not drawn,
// alpha at or above it is fully drawn. There is no partial coverage here on
// purpose; a shadow map holds one depth per texel, so a half-transparent
// fragment either records or does not.

#define F3D_NO_SURFACE_BUFFER
#define F3D_NO_FOG
#include <lib/color.glsl>

/// The base colour map, whose alpha is the mask. The same texture and the same
/// slot name the lit stages bind, so a caller that has one has it already.
uniform sampler2D base_color_texture;

uniform MaskInfo {
  // x: the cutoff, from `Material.alphaCutoff`. y: the base colour's own
  // alpha, which glTF multiplies the texture's by, so a material faded to
  // nothing casts nothing. z, w: unused.
  vec4 mask;
}
mask_info;

void main() {
  float alpha = texture(base_color_texture, v_texcoord).a * mask_info.mask.y;
  if (alpha < mask_info.mask.x) discard;
  frag_color = vec4(gl_FragCoord.z, 0.0, 0.0, 1.0);
}
