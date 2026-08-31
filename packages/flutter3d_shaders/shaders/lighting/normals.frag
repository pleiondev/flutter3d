#version 460 core

// Debug view: world-space normal mapped into RGB.
//
// The fastest way to tell a geometry bug from a lighting bug. Hard edges show as
// flat colour blocks, smooth ones as gradients, and inverted winding shows as
// the complement of the expected colour.
//
// Includes lib/color.glsl rather than lib/surface.glsl on purpose: this shader
// reads no material inputs, and merely DECLARING the FragInfo block would leave
// it visible to reflection while the compiled shader binds no buffer for it.
// Binding that phantom block segfaults inside Metal's
// setFragmentBuffer:offset:atIndex:. LightingModel.usesFragInfo encodes the same
// fact on the Dart side, because reflection alone cannot be trusted here.
#include <lib/color.glsl>

void main() {
  vec3 n = normalize(v_normal);
  WriteDisplayColor(n * 0.5 + vec3(0.5), 1.0);
}
