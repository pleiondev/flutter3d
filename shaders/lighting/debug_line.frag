#version 460 core

// Fragment stage for the debug line overlay: the vertex colour, unchanged.
//
// No tone mapping and no sRGB encode. Overlay colours are chosen to be read on
// screen, not to be light values, so pushing them through the display transform
// would only make them differ from what the Dart side asked for.
//
// It includes nothing from shaders/lib on purpose: those headers declare the
// mesh varyings and the FragInfo block, and a shader that declares a uniform
// block it never reads is exactly the phantom-binding trap documented in
// RESEARCH.md §4.
precision highp float;

in vec4 v_line_color;

out vec4 frag_color;

void main() {
  frag_color = v_line_color;
}
