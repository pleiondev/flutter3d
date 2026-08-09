#version 460 core

// The shadow pass: write depth, nothing else.
//
// Depth goes into a **colour** target rather than being read back out of the
// depth buffer. flutter_gpu gives no way to sample a depth texture — the format
// enum has depth formats, but a `DepthStencilAttachment` texture is not
// something `bindTexture` will take — so the workaround is chosen up front
// rather than discovered: render linear depth into `r16g16b16a16Float`, which
// is a format sampling is known to work for.
//
// `gl_FragCoord.z` is exactly what is wanted here *because* the shadow camera is
// orthographic. Under a perspective projection that value is hyperbolic and
// would concentrate all its precision near the near plane; an orthographic one
// is linear in view space, so the stored value is a distance and comparing two
// of them is meaningful.
//
// It includes lib/color.glsl for the varying declarations and the output, not
// for the colour helpers: a fragment shader whose inputs disagree with the
// vertex shader's outputs does not link, and mesh.vert emits all five.
// One attachment, not two: this pass writes a shadow map, and the surface
// buffer belongs to the scene pass.
#define F3D_NO_SURFACE_BUFFER
#include <lib/color.glsl>

void main() {
  frag_color = vec4(gl_FragCoord.z, 0.0, 0.0, 1.0);
}
