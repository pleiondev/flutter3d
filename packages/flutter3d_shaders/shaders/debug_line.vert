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
  // `impellerc` defines IMPELLER_GRAPHICS_BACKEND and a WebGL2 compile
  // GL_ES, and never both. The road to WGSL has neither, and naga refuses
  // PointSize, which WGSL does not have.
#ifdef IMPELLER_GRAPHICS_BACKEND
  gl_PointSize = 1.0;
#endif
#ifdef GL_ES
  gl_PointSize = 1.0;
#endif
}
