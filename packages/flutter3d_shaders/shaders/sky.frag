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
// runs off `sky.vert`, which emits one varying. So the two outputs are declared
// here instead, in the same slots and with the same meanings.
precision highp float;

in vec3 v_ray;

layout(location = 0) out vec4 frag_color;

// The surface buffer, written as zero rather than left alone.
//
// Zero alpha is how `reflections.frag` recognises "nothing was drawn here", and
// the attachment is cleared to zero, so not writing would give the same answer
// — on a backend that guarantees an untouched attachment keeps its cleared
// value. Writing it costs nothing and does not depend on that. When the scene
// draws into one attachment rather than two, the extra output is discarded; the
// renderer decides whether anyone is listening.
layout(location = 1) out vec4 frag_surface;

uniform SkyInfo {
  /// rgb: the sky straight up. a: unused.
  vec4 zenith;
  /// rgb: the sky level with the horizon. a: unused.
  vec4 horizon;
  /// rgb: the sky straight down — haze rather than ground. a: unused.
  vec4 nadir;
  /// xyz: unit vector pointing at the sun. w: how tight the scattering lobe is.
  vec4 sun;
  /// rgb: the sun's own colour. a: how bright the lobe is.
  vec4 glow;
  /// x: cosine of the disc's angular radius. y: cosine of the radius plus its
  /// soft edge — smaller than x, since cosine falls as the angle grows.
  /// z: how bright the disc is, which may be far above white. w: unused.
  vec4 disc;
}
sky_info;

void main() {
  vec3 direction = normalize(v_ray);

  // The gradient, smoothstepped in height rather than linear: the first fifteen
  // degrees above the horizon are most of what anybody looks at, and a straight
  // ramp spends its range on the part they do not.
  float height = clamp(direction.y, -1.0, 1.0);
  vec3 far = height >= 0.0 ? sky_info.zenith.rgb : sky_info.nadir.rgb;
  float t = abs(height);
  t = t * t * (3.0 - 2.0 * t);
  vec3 colour = mix(sky_info.horizon.rgb, far, t);

  float towards = dot(direction, sky_info.sun.xyz);

  // The wide scattering lobe. Guarded, because `pow` of a negative base is
  // undefined and a NaN here is a pixel that is black on one backend and white
  // on another.
  if (towards > 0.0) {
    colour += sky_info.glow.rgb * (sky_info.glow.a * pow(towards, sky_info.sun.w));
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
  float disc = sky_info.disc.x > sky_info.disc.y
      ? smoothstep(sky_info.disc.y, sky_info.disc.x, towards)
      : 0.0;
  colour += sky_info.glow.rgb * (disc * sky_info.disc.z);

  frag_color = vec4(colour, 1.0);
  frag_surface = vec4(0.0);
}
