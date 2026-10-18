#version 460 core

// Metal-rough, as `lib/pbr.glsl` describes it. The body lives there so the
// layered stage beside this one is the same code with its layers switched on.
// `A1.1`: a material stage — its colour arithmetic may run at mediump
// where `shaders/PRECISION.md` says it can.
#define F3D_MEDIUMP
#include <lib/pbr.glsl>
