#version 460 core

// `unlit.frag` with its second output taken away: a flat colour that says
// nothing about the surface it covers.
//
// **A shader of its own rather than a blend state, because a blend state does
// not reach here.** The x-ray stage draws every marked node twice inside the
// scene pass, and that pass has two attachments whenever a screen-space effect
// asked for the surface buffer. `BlendState.keepDestination` is what the
// marking draw uses to leave the picture alone, and it protects attachment
// zero only: `setBlend` takes an attachment index that Impeller honours and
// WebGL2 cannot, since per-attachment blending there needs
// `EXT_draw_buffers_indexed`. So the three backends disagreed about what was
// left in attachment one — and the silhouette draw, which blends not at all,
// wrote into it on every one of them.
//
// What that wrote was wrong rather than merely extra. The silhouette's depth
// test is `greater`: it passes exactly where the marked node is BEHIND what
// the depth buffer holds, so `frag_surface` was taking the normal, roughness
// and depth of a monster and stamping them over the wall in front of it. The
// surface buffer's one invariant is that it describes the nearest surface, and
// SSAO and reflections read it as such — a silhouette would have occluded and
// reflected off geometry that is not visible.
//
// Declaring one output into a two-attachment target is the arrangement
// `sky.frag` already ships and `lib/color.glsl` already guards for the shadow
// passes; the reverse — declaring an output the target has no slot for — is
// the one that crashes Metal.
#define F3D_NO_POINT_SHADOW
#define F3D_NO_SURFACE_BUFFER
#include <lib/surface.glsl>

// Never called, for the reason `unlit.frag` gives: nothing here accumulates
// lights, and the prototypes in surface.glsl still have to be satisfied.
vec3 ShadeLight(Surface s, LightSample light) {
  return s.albedo;
}

float LightVisibility(Surface s, LightSample light, int index) {
  return 1.0;
}

void main() {
  Surface s = ReadSurface();
  // The same call unlit makes, and it behaves the same way but for the guarded
  // half: colour into the HDR target, and `WriteSurfaceGeometry` compiled away
  // to nothing. The stage binds no fog, so `ApplyFog` is the identity here.
  WriteSurface(s.albedo, s.alpha);
}
