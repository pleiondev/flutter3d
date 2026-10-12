#version 460 core

// Vertex stage for the debug line overlay.
//
// A separate vertex shader rather than a reuse of mesh.vert: the debug buffer is
// position + colour with no normal or texcoord, and flutter_gpu takes the vertex
// layout from the order of `in` declarations, so a different layout means a
// different shader. See VertexLayout.positionColor.
in vec3 position;
in vec4 color;

uniform LineInfo {
  mat4 view_projection;
}
line_info;

out vec4 v_line_color;

void main() {
  v_line_color = color;
  gl_Position = line_info.view_projection * vec4(position, 1.0);
  // One pixel, the size WebGPU draws every point at. GLSL leaves the size of
  // a point whose stage writes none undefined, and Metal took whatever it
  // found: three points of a triangle covered more pixels than its fill,
  // some runs and not others. Written where the target has the built-in:
  // `impellerc` defines IMPELLER_TARGET_METAL, _OPENGLES or _VULKAN for the
  // target it is compiling (and never IMPELLER_GRAPHICS_BACKEND, which this
  // once asked for, so Metal went on drawing points at whatever size it
  // found), and a WebGL2 compile defines GL_ES. The road to WGSL has none of
  // them, and naga refuses PointSize, which WGSL does not have.
#if defined(IMPELLER_TARGET_METAL) || defined(IMPELLER_TARGET_OPENGLES) || defined(IMPELLER_TARGET_VULKAN)
  gl_PointSize = 1.0;
#elif defined(GL_ES)
  gl_PointSize = 1.0;
#endif
}
