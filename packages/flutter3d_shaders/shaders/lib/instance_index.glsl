// Which instance this is: `gl_InstanceIndex` where the target has it, the
// attribute `f3d_instance_index` — a float per instance — on Impeller's
// OpenGL ES target, which has no such built-in. `lib/vertex_index.glsl` says
// why.

#ifndef INSTANCE_INDEX_GLSL_
#define INSTANCE_INDEX_GLSL_

#ifdef IMPELLER_TARGET_OPENGLES
in float f3d_instance_index;
int F3dInstanceIndex() { return int(f3d_instance_index + 0.5); }
#else
int F3dInstanceIndex() { return gl_InstanceIndex; }
#endif

#endif  // INSTANCE_INDEX_GLSL_
