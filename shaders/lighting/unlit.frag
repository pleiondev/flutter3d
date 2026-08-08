#version 460 core

// Albedo only. Useful as a baseline: whatever this shows is purely texture and
// tint, with no lighting term involved.
#include <lib/surface.glsl>

void main() {
  Surface s = ReadSurface();
  WriteDisplayColor(s.albedo);
}
