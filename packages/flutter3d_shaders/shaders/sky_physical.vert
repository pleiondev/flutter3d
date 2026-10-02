#version 460 core

// Vertex stage for the physical sky: the gradient sky's triangle, carrying the
// air instead of three colours.
//
// **Its own stage rather than `sky.vert` read under other names.** The data
// travels the same way and for the same reason — `sky.vert` sets out what was
// measured: on Impeller a uniform block never reaches the sky's pipeline and a
// vertex attribute does — and it is the same size, six vec4s after the ray. But
// a varying is matched by name between the stages, and a fragment stage reading
// `v_zenith` as a scattering coefficient is one nobody could maintain.
//
// The depth is `sky.vert`'s 0.999999, for `sky.vert`'s reason: the far plane
// less a hair, so the pass's own `less` passes against a cleared buffer and
// fails against anything already drawn.
//
// Lengths are in kilometres here, not metres. The planet's radius is 6360 of
// them, and in metres its square is 4·10¹³, which single precision holds to
// within a few units — enough to put the horizon a pixel off where the ray
// grazes it. The renderer converts; see `Renderer._skyVertexBytes`.
precision highp float;

layout(location = 0) in vec2 position;

// The world-space view ray at this corner.
layout(location = 1) in vec3 corner_ray;

/// rgb: Rayleigh scattering at the ground, per km. a: its scale height, km.
layout(location = 2) in vec4 rayleigh;
/// x: Mie scattering at the ground, per km. y: Mie extinction, per km.
/// z: its scale height, km. w: Henyey–Greenstein's g.
layout(location = 3) in vec4 mie;
/// xyz: unit vector pointing at the sun. w: the sunlight entering the air.
layout(location = 4) in vec4 sun;
/// x: the planet's radius. y: the top of the air's. z: the eye's, all km.
/// w: the ground's albedo.
layout(location = 5) in vec4 planet;
/// x: how bright the stars are. y: the share of cells holding one.
/// z: cells across a face of the cube they are scattered on. w: unused.
layout(location = 6) in vec4 stars;
/// x: cosine of the disc's angular radius. y: how much softer its edge is,
/// as a difference of cosines. z: how bright the disc is. w: unused.
layout(location = 7) in vec4 disc;

out vec3 v_ray;
out vec4 v_rayleigh;
out vec4 v_mie;
out vec4 v_sun;
out vec4 v_planet;
out vec4 v_stars;
out vec4 v_disc;

void main() {
  v_ray = corner_ray;
  v_rayleigh = rayleigh;
  v_mie = mie;
  v_sun = sun;
  v_planet = planet;
  v_stars = stars;
  v_disc = disc;

  gl_Position = vec4(position, 0.999999, 1.0);
}
