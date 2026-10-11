// Which vertex this is: `gl_VertexIndex` where the target has it, an
// attribute where it does not.
//
// Impeller's OpenGL ES backend compiles the bundle as GLSL ES 1.00, which has
// no vertex or instance index. `impellerc` writes the built-in into the
// `#version 100` source anyway, the driver refuses the stage at run time, and
// a Linux machine or an Android phone without Vulkan draws nothing. GLSL ES
// 3.00 is no way out: `--gles-language-version=300` also sets the desktop GL
// target's version, which then reads `#version 300` (`doc/upstream.md`).
//
// So on that one target the index is `f3d_vertex_index`, a float per vertex
// in a buffer of its own that the backend binds after the pipeline's own
// slots (`flutter3d_impeller`'s `gpu_vertex_index.dart`). A float because
// GLSL ES 1.00 has no integer attributes; it is exact up to 2^24. Every other
// target keeps the built-in and its layout. `lib/instance_index.glsl` is the
// same for the instance.

#ifndef VERTEX_INDEX_GLSL_
#define VERTEX_INDEX_GLSL_

#ifdef IMPELLER_TARGET_OPENGLES
in float f3d_vertex_index;
int F3dVertexIndex() { return int(f3d_vertex_index + 0.5); }
#else
int F3dVertexIndex() { return gl_VertexIndex; }
#endif

#endif  // VERTEX_INDEX_GLSL_
