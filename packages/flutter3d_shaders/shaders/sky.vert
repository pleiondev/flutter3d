#version 460 core

// Vertex stage for the sky: one full-screen triangle, and everything the
// fragment stage needs, carried on the vertices.
//
// **The sky's data travels as attributes because uniforms do not reach this
// pipeline on Impeller.** That is not a guess and not a workaround chosen for
// taste; it is the one channel that was measured to work. What was measured,
// each against a frame recorded from a real Metal device with the golden runner
// (`tool/golden.sh sky`), and each with the picture read back rather than eyed:
//
//  * a uniform block bound to this stage — an identity matrix was bound and the
//    shader read something else, so the picture never changed;
//  * a uniform block bound to the fragment stage — a pure red zenith was bound
//    and the shader saw something that was not red;
//  * a vertex attribute — arrived exactly, to the value bound;
//  * a varying — interpolated across the triangle exactly.
//
// The same two binds work everywhere else in this renderer, in the same pass,
// in the same frame: every mesh takes its matrices this way and every
// post-processing stage takes its settings this way. Why this pipeline is
// different is not known. What is known is which door is open.
//
// The cost is a vertex buffer of three vertices rebuilt each frame, which is
// 348 bytes through the transient allocator — less than one uniform upload.
//
// ---------------------------------------------------------------------------
//
// **The depth.** A post pass writes `gl_Position.z = 0.0`, which is the *near*
// plane; the sky belongs at the far one. This writes 0.999999 — the far plane,
// less a hair. Strictly less than 1.0 so that the ordinary `less` test passes
// against a buffer cleared to 1.0, which is what lets the sky be drawn with the
// pass's own depth state and no `setDepthCompare` at all. With depth writes off
// it never occludes anything, and because it is drawn after the opaque half,
// every pixel already covered by geometry fails the test before the fragment
// stage runs.
//
// **The ray.** One direction per corner, computed on the CPU from the inverse
// view-projection and interpolated across the triangle — which for a
// perspective camera is exact, because the direction is affine in the screen
// position. The renderer builds them; see `Renderer._skyCornerRay`.
precision highp float;

layout(location = 0) in vec2 position;

// The world-space view ray at this corner.
layout(location = 1) in vec3 corner_ray;

// The preset, replicated on all three vertices. Constant across the triangle,
// so any interpolation of it returns exactly what was written.
layout(location = 2) in vec4 zenith;
layout(location = 3) in vec4 horizon;
layout(location = 4) in vec4 nadir;
/// xyz: unit vector pointing at the sun. w: how tight the scattering lobe is.
layout(location = 5) in vec4 sun;
/// rgb: the sun's own colour. a: how bright the lobe is.
layout(location = 6) in vec4 glow;
/// x: cosine of the disc's angular radius. y: cosine of the radius plus its
/// soft edge. z: how bright the disc is. w: unused.
layout(location = 7) in vec4 disc;

out vec3 v_ray;
out vec4 v_zenith;
out vec4 v_horizon;
out vec4 v_nadir;
out vec4 v_sun;
out vec4 v_glow;
out vec4 v_disc;

void main() {
  v_ray = corner_ray;
  v_zenith = zenith;
  v_horizon = horizon;
  v_nadir = nadir;
  v_sun = sun;
  v_glow = glow;
  v_disc = disc;

  gl_Position = vec4(position, 0.999999, 1.0);
}
