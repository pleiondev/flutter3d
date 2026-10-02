#version 460 core

// One side of a refracting caster, as the sun sees it — `ShadowSettings.
// caustics`. The surface's normal in the world, and its depth along the light
// in the same units the shadow atlas stores.
//
// Drawn twice into a small map of the caster alone: once nearest-first with
// the faces turned towards the light, once farthest-first with the faces
// turned away. `caustic_photon.vert` reads both, which is all a ray needs to
// be followed in at one side and out at the other.

#define F3D_NO_SURFACE_BUFFER
#define F3D_NO_FOG

#include <lib/color.glsl>

void main() {
  frag_color = vec4(normalize(v_normal), gl_FragCoord.z);
}
