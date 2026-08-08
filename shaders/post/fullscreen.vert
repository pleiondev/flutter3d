#version 460 core

// Vertex stage for every full-screen pass.
//
// A single oversized triangle, not a quad. A quad has a diagonal seam where the
// two triangles meet, and the GPU rasterizes 2x2 quads of fragments along it
// twice; one triangle that covers the screen has no seam and no duplicated
// work. The extra area outside the viewport is clipped for free.
//
// The three vertices come from a tiny vertex buffer rather than from
// gl_VertexIndex, because flutter_gpu's draw() renders nothing without an index
// buffer bound, so there is a buffer to bind either way.
in vec2 position;
in vec2 texcoord;

out vec2 v_uv;

void main() {
  v_uv = texcoord;
  gl_Position = vec4(position, 0.0, 1.0);
}
