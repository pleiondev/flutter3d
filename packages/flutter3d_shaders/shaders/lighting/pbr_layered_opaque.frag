#version 460 core

// The layered metal-rough model with no reachable `discard` — `A1.2`. See
// `pbr_opaque.frag`.
// `A1.1`: a material stage — its colour arithmetic may run at mediump
// where `shaders/PRECISION.md` says it can.
#define F3D_MEDIUMP
#define F3D_LAYERED
#define F3D_OPAQUE
#include <lib/pbr.glsl>
