#version 460 core

// The picking pass: the id the renderer gave this node, and nothing else.
//
// A `Normals`-shaped stage — every mesh drawn again through the same vertex
// stages, with a fragment stage that writes a constant instead of a colour —
// into an RGBA8 target one pixel of which is then read back. The id arrives
// as three bytes in [0, 1] so an eight-bit store hands it back exactly; the
// renderer decodes `r + g·256 + b·65536`, and zero is the clear colour, which
// is what "nothing here" reads as.
//
// One attachment, not two: the target is the id texture and there is no
// surface buffer beside it, so the second output is left undeclared the way the
// shadow passes leave it — see `shadow_depth.frag`.
//
// Includes lib/color.glsl rather than lib/surface.glsl for the reason
// `normals.frag` gives: merely declaring FragInfo would leave it visible to
// reflection while the compiled shader binds no buffer for it, and binding
// that phantom block is a native crash on Metal. This stage declares a block of
// its own and reads that.
#define F3D_NO_SURFACE_BUFFER
#include <lib/color.glsl>

uniform IdInfo {
  /// xyz: the id, low byte first, each as a fraction of 255. w: unused.
  vec4 id;

  /// x: the material's alpha cutoff, negative when it is not masked — the
  /// encoding `FragInfo.material2.x` uses. y: the tint's alpha, the
  /// `base_color.a` the scene pass multiplies the texel by. zw: unused.
  vec4 mask;
}
id_info;

/// The same texture the scene pass reads, for the one thing it reads it for
/// here: where a masked material's alpha falls under its cutoff is a hole, and
/// a hole is where the thing behind it is on the screen.
uniform sampler2D base_color_texture;

void main() {
  // What the scene pass threw away, thrown away here too, before the write: a
  // click through a fence's hole has to answer with what is seen through it.
  // The alpha is the one `ReadSurface` computes — texel, tint, vertex colour —
  // or the two stages would disagree about where the hole is.
  float cutoff = id_info.mask.x;
  if (cutoff >= 0.0) {
    float alpha = texture(base_color_texture, v_texcoord).a *
                  id_info.mask.y * v_color.a;
    if (alpha < cutoff) discard;
  }
  frag_color = vec4(id_info.id.xyz, 1.0);
}
