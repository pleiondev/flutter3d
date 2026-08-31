#version 460 core

// A textured sky: the same view ray, sampled out of a cube map.
//
// A second fragment stage rather than a branch inside `sky.frag`, and rather
// than a new vertex stage. The ray `sky.vert` emits is already a world-space
// direction, which is exactly what a cube sampler takes — so the whole of the
// difference between a procedural sky and a photographed one is this file.
//
// A branch would have been the wrong shape twice over. The uniform block would
// have had to carry both descriptions whichever was in use, and every pixel
// would have paid for a sampler bind that half the callers never fill; and a
// shader that declares a sampler nobody binds is a native crash on Metal rather
// than a black texture. Two entry points, one manifest, one pipeline each.
//
// **The faces are +X, −X, +Y, −Y, +Z, −Z.** That order is documented once, on
// `GraphicsDevice.createCubeTextureFromPixels`, and it is what every backend
// here uploads in — Impeller by slice index, WebGL by consecutive face target,
// the software rasteriser by the table in `BoundTexture.sampleCube`. Nothing in
// a picture says whether two of them are transposed, which is why the
// conformance suite draws six known directions against six known colours.
precision highp float;

in vec3 v_ray;
in vec4 v_tint;

layout(location = 0) out vec4 frag_color;

// No second output — see `sky.frag`.

uniform samplerCube sky_texture;

// **No uniform block, and `sky.vert` says at length why.** The tint arrives as
// a varying, written on all three vertices of the full-screen triangle.

void main() {
  // Decoded from sRGB, because a cube map is an image and an image is authored
  // in display space — the same rule `lib/surface.glsl` applies to a base
  // colour texture, and the same rule a vertex colour is exempt from. Without
  // this a photographed sky arrives with its midtones lifted, which reads as
  // haze rather than as a colour-space mistake.
  vec3 texel = texture(sky_texture, normalize(v_ray)).rgb;
  vec3 linear = mix(texel / 12.92,
                    pow((texel + 0.055) / 1.055, vec3(2.4)),
                    step(vec3(0.04045), texel));

  frag_color = vec4(linear * v_tint.rgb, 1.0);
}
