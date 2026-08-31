#version 460 core

// Vertex stage for the cube-map sky: the same full-screen triangle as
// `sky.vert`, with the one value that stage carries instead of a preset.
//
// **Its own stage rather than a shared one**, because the vertex layout is
// derived from these declarations and the two fragment stages want different
// things: the gradient wants six vec4s of preset, this wants a tint. One
// shader serving both would have to declare the union and every draw would
// carry what the other one needed.
//
// Why any of it travels on the vertices at all is written out in `sky.vert`.
precision highp float;

layout(location = 0) in vec2 position;

/// The world-space view ray at this corner.
layout(location = 1) in vec3 corner_ray;

/// rgb: what the sampled cube is multiplied by. a: unused.
layout(location = 2) in vec4 tint;

out vec3 v_ray;
out vec4 v_tint;

void main() {
  v_ray = corner_ray;
  v_tint = tint;
  gl_Position = vec4(position, 0.999999, 1.0);
}
