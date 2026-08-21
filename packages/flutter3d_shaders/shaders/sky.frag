#version 460 core

// The sky, evaluated per pixel from the view ray.
//
// What this buys over a painted dome, which is the thing it replaces: a sun
// disc. A disc is about half a degree across — two, if you are being generous
// about glare — and a dome fine enough to resolve one would need rings a
// fraction of a degree apart. Here the shape is analytic and its size is a
// number, so it costs the same at any angular radius.
//
// It also escapes the fog. `ApplyFog` lives inside `WriteSurface` in
// `lib/color.glsl` and every lit model goes through it, so a dome ten metres
// across is fogged by ten metres of air whether that makes sense or not. This
// stage includes none of that.
//
// **Deliberately not including `lib/color.glsl`.** That header declares the
// five varyings `mesh.vert` emits, and a fragment shader whose inputs disagree
// with its vertex stage's outputs does not link — there is no partial-match
// rule. `shadow_depth.frag` includes it *because* it runs off `mesh.vert`; this
// runs off `sky.vert`, whose varyings are its own.
//
// **The preset arrives on the varyings rather than in a uniform block**, and
// `sky.vert` sets out at length what was measured to make that the design: on
// Impeller a uniform block bound to this pipeline never arrives, in either
// stage, while an attribute does.
precision highp float;

in vec3 v_ray;
in vec4 v_zenith;
in vec4 v_horizon;
in vec4 v_nadir;
in vec4 v_sun;
in vec4 v_glow;
in vec4 v_disc;

layout(location = 0) out vec4 frag_color;

// **The surface buffer is deliberately not written here, and the sentence this
// replaces cost a working sky.**
//
// It used to say: "Writing it costs nothing and does not depend on that. When
// the scene draws into one attachment rather than two, the extra output is
// discarded; the renderer decides whether anyone is listening." Every clause of
// that is wrong on Impeller. Measured, both ways round, in the `sky` golden
// scene:
//
//  * one attachment (the usual path — no screen-space effect asked for the
//    surface buffer, so the pass multisamples instead) and this shader
//    declaring `frag_surface`: **the process dies**, inside Metal, at
//    `-[AGXG15XFamilyRenderContext setFragmentBuffer:offset:atIndex:]` with a
//    bad address. When it survives long enough to draw, `SkyInfo` and `SkyRay`
//    arrive as rubbish, which is a flat maroon sky over a racing circuit.
//  * two attachments (`surfaceBuffer: true`), same shader: draws correctly.
//
// `lib/color.glsl` already knew — "a pipeline declaring an output its target has
// no slot for is a mismatch worth avoiding rather than discovering" — and
// guards its own second output behind `F3D_NO_SURFACE_BUFFER` for the shadow
// pass. This file was the one place that declared it anyway.
//
// Nothing is lost by leaving it out. The attachment is cleared to zero and zero
// alpha is exactly what `reflections.frag` reads as "nothing was drawn here" —
// the same answer this shader was writing by hand.

// **No uniform block, and `sky.vert` says at length why.** Its members reach
// this stage as varyings, written on all three vertices of the full-screen
// triangle: the only channel measured to arrive on this pipeline.

void main() {
  vec3 direction = normalize(v_ray);

  // The gradient, smoothstepped in height rather than linear: the first fifteen
  // degrees above the horizon are most of what anybody looks at, and a straight
  // ramp spends its range on the part they do not.
  float height = clamp(direction.y, -1.0, 1.0);
  vec3 far = height >= 0.0 ? v_zenith.rgb : v_nadir.rgb;
  float t = abs(height);
  t = t * t * (3.0 - 2.0 * t);
  vec3 colour = mix(v_horizon.rgb, far, t);

  float towards = dot(direction, v_sun.xyz);

  // The wide scattering lobe. Guarded, because `pow` of a negative base is
  // undefined and a NaN here is a pixel that is black on one backend and white
  // on another.
  if (towards > 0.0) {
    colour += v_glow.rgb * (v_glow.a * pow(towards, v_sun.w));
  }

  // And the disc itself, added on top of the lobe rather than replacing it: the
  // sun is a bright thing seen through the glow around it, not instead of it.
  // Its brightness is free to sit above one — this target is HDR, and a sun
  // that cannot blow out is a sun bloom has nothing to find.
  //
  // Guarded, and the guard is not defensive programming. `smoothstep` is
  // undefined when its two edges are equal — GLSL says so, and Metal computes
  // `(x - e0) / (e1 - e0)`, which is 0/0 and therefore NaN. The two edges here
  // are cosines of angles a third of a degree apart, so they are equal for any
  // caller who leaves the disc at its default size, and a single NaN channel
  // poisons the whole pixel through the tone map. A sky is exactly where that
  // is least visible as a NaN and most visible as "the gradient went away".
  //
  // **The other branch was `0.0`, and that turned the sun off.** A soft edge of
  // nothing is a sun with a hard edge — which is a thing to ask for — and the
  // answer to it is a step, not an absence. `SkySettings.sample`, which is the
  // same model written in Dart, has always drawn one; this drew nothing, so a
  // hard-edged sun existed in the fog colour and not in the sky.
  float disc = v_disc.y > 0.0
      ? smoothstep(v_disc.x - v_disc.y, v_disc.x, towards)
      : step(v_disc.x, towards);
  colour += v_glow.rgb * (disc * v_disc.z);

  frag_color = vec4(colour, 1.0);

}
