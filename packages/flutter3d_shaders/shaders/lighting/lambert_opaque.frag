#version 460 core

// `Lambert` with no reachable `discard` — `A1.2`. See `pbr_opaque.frag`.
// `A1.1`: a material stage — its colour arithmetic may run at mediump
// where `shaders/PRECISION.md` says it can.
#define F3D_MEDIUMP
#define F3D_OPAQUE
// Lambert reads no ORM map (`LightingModel.lambert` says
// `usesMetallicRoughnessMap: false`), so the sampler is not declared at all:
// declared and dropped, Metal's reflection would list a slot it has not got.
#define F3D_NO_METALLIC_ROUGHNESS_MAP
#include <lib/lambert.glsl>
