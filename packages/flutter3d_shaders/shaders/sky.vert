#version 460 core

// Vertex stage for the sky: one full-screen triangle, and a world-space ray per
// corner.
//
// Its own stage rather than `post/fullscreen.vert` for two reasons, and both
// are load-bearing.
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
// **The ray.** The direction is computed here, per corner, and interpolated —
// which for a perspective camera is exact, because the direction is affine in
// the screen position. Doing it in the fragment shader would mean
// reconstructing NDC from a UV, and that is where `reflections.frag` and this
// renderer's own full-screen triangle disagree about which way Y runs. Nothing
// here has to know.
//
// The two sample depths are 0.5 and 1.0, and that is deliberate: both are valid
// in **either** depth convention. This engine runs zero-to-one on Impeller and
// on the software rasteriser and minus-one-to-one on WebGL, so a ray built from
// the near plane would need to know which. The difference of two points on the
// same eye ray is the same direction wherever the two points sit.
//
// One attribute, not two. The vertex layout is taken from these declarations,
// so an `in vec2 texcoord` that this stage never reads is one the compiler is
// free to drop — and dropping it changes the stride the buffer is read with.
// Hence a vertex buffer of its own, holding positions and nothing else.
//
// ---------------------------------------------------------------------------
// **This stage does not work on Impeller, and the cause is not known.** The
// software rasteriser and this file agree completely; the picture Impeller
// draws is a flat wash of one colour, because `v_ray` barely varies. What
// follows is what was measured rather than what was guessed, so that the next
// person starts from the end of this rather than the beginning.
//
// Measured *correct* on Impeller, each against the software rasteriser reading
// the identical bytes, pixel for pixel:
//
//  * the `position` attribute, emitted straight through this varying;
//  * the varying itself, as `vec3` and as `vec2`;
//  * `SkyInfo`'s colour members, read by `sky.frag`.
//
// Measured *wrong* on Impeller, in every arrangement tried:
//
//  * `SkyRay` bound here — the shader read a constant that did not change when
//    three different matrices were bound: the real one, a probe, and a probe of
//    hundreds. The software rasteriser tracked all three. Reflection reported
//    `size=64 offset=0`, which is exactly right, and `bindUniform` was reached.
//  * the same matrix moved into `sky.frag`'s own block as a `mat4` — the
//    colours beside it arrived, the matrix read as zero, and `normalize` of the
//    zero ray is a NaN that paints the sky black.
//  * the same matrix as four `vec4` members of that block — black again.
//  * the same four members moved to the end of the block — **one build drew a
//    correct gradient and the next drew black, from identical source.** That
//    is the finding that rules out layout: the behaviour is not stable, so no
//    ordering of members is a fix.
//  * the ray computed on the CPU and passed as a second vertex attribute
//    alongside `position` — flat wash again, which is why this file still has
//    one attribute.
//
// So: colours in a uniform block arrive, a single vertex attribute arrives, and
// this pipeline's camera data does not, in any form tried. `RenderSettings.sky`
// is off by default and no golden is recorded for it, so nothing ships broken —
// except a racing game that turns it on, which is where this matters.
// ---------------------------------------------------------------------------
in vec2 position;

uniform SkyRay {
  mat4 inverse_view_projection;
}
sky_ray;

out vec3 v_ray;

void main() {
  vec4 near = sky_ray.inverse_view_projection * vec4(position, 0.5, 1.0);
  vec4 far = sky_ray.inverse_view_projection * vec4(position, 1.0, 1.0);
  v_ray = far.xyz / far.w - near.xyz / near.w;

  gl_Position = vec4(position, 0.999999, 1.0);
}
