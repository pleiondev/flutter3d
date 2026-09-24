#version 460 core

// Metal-rough with glTF's layers on top — `M1`–`M3`: the index of refraction,
// the specular strength and tint, a clear coat lit on the geometric normal, a
// sheen, anisotropy, transmission through a volume, dispersion and a thin
// film. `lib/pbr.glsl` compiled with `F3D_LAYERED`, so a plain metal-rough
// surface keeps the cost and the samplers it had. See
// `LightingModel.pbrLayered`.
#define F3D_LAYERED
#include <lib/pbr.glsl>
