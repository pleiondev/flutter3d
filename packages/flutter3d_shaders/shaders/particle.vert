#version 460 core

// Vertex stage for particles.
//
// The quads arrive already facing the camera. Billboarding on the CPU rather
// than here is the cheaper arrangement for this engine: the alternative expands
// a point into a quad in the vertex stage, which needs either a geometry stage
// — flutter_gpu has none — or four vertices carrying the same centre plus a
// corner index, which is the same bandwidth this uses with an extra
// reconstruction on top.
//
// A third layout, and therefore a third vertex shader: flutter_gpu reads the
// layout from the order of these declarations, so position + colour + texcoord
// cannot share a stage with anything else. See VertexLayout.positionColorTexcoord.
in vec3 position;
in vec4 color;
in vec2 texcoord;

uniform ParticleInfo {
  mat4 view_projection;
}
particle_info;

out vec4 v_color;
out vec2 v_uv;

/// Carried so the fragment stage can be fogged. A particle knows where it is
/// only here; the quad's own coordinates say nothing about the world.
out vec3 v_world_position;

void main() {
  v_color = color;
  v_uv = texcoord;
  v_world_position = position;
  gl_Position = particle_info.view_projection * vec4(position, 1.0);
}
