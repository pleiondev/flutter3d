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
}
