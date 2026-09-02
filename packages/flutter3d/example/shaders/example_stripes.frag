#version 460 core

// A look the engine never shipped: bands of two colours by the height of the
// surface normal, faintly lit from above so the shape still reads.
//
// This is the example's own shader, compiled into the example's own bundle —
// `tool/build_shaders.sh` here, not the engine's — and loaded from bytes at run
// time through `GraphicsDevice.loadShaders`. The `loaded-shader` golden is a
// teapot wearing it on all three backends, and the software backend draws it
// from `example_stripes_cpu.dart`, the same arithmetic in Dart.
//
// The file name carries the package's name on purpose: Impeller derives an
// entry point from the file stem and registers it process-wide, so a
// `stripes.frag` in two bundles would be one shader with two callers.
//
// Only color.glsl. This reads no material inputs, and declaring FragInfo
// without reading it would leave a phantom block for the renderer to bind;
// `LightingModel.usesFragInfo` says the same on the Dart side.
#include <lib/color.glsl>

void main() {
  vec3 n = normalize(v_normal);
  float band = step(0.5, fract(n.y * 3.0 + 0.25));
  vec3 warm = vec3(0.90, 0.45, 0.08);
  vec3 cool = vec3(0.10, 0.30, 0.85);
  float lit = 0.55 + 0.45 * clamp(n.y, 0.0, 1.0);
  WriteSurface(mix(warm, cool, band) * lit, 1.0);
}
