#version 460 core

// The `Toon` lighting model; `lib/toon.glsl` has it, shared with the opaque
// variant beside this file.
// `A1.1`: a material stage — its colour arithmetic may run at mediump
// where `shaders/PRECISION.md` says it can.
#define F3D_MEDIUMP
#include <lib/toon.glsl>
