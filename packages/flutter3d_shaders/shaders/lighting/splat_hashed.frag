#version 460 core

// A Gaussian splat kept or dropped whole per pixel, instead of blended — `N5`.
//
// **Why a second stage rather than a switch in `splat.frag`.** Blending needs
// the cloud sorted back to front, and the sort is most of what a cloud costs a
// camera move. With a temporal resolve running there is another way: treat the
// splat's opacity at a pixel as a *probability* of covering it, keep or discard
// the fragment against noise, and write it opaque with its depth. One frame of
// that is speckle; the resolve averages sixteen, and the expected colour of a
// pixel is exactly what the sorted blend would have put there — the nearest
// kept splat wins the depth test, and it is kept with its own opacity times the
// chance that everything nearer was dropped. No order is needed because the
// depth buffer does the ordering. `splat.frag` stays as it was, byte for byte,
// so a frame without the resolve draws what it always drew.
//
// **The noise is the pixel's, the splat's and the frame's.** The engine's
// `hashed` material mode anchors its noise to world position so a moving leaf
// keeps its verdict; that is the wrong choice here, because the resolve has to
// *see* the verdict change from frame to frame to average it. So:
//
//   * the engine's blue noise (`R3`), a new slice each frame: across one
//     splat, the pixels it keeps are spread evenly rather than clumped, so
//     every three-by-three neighbourhood the resolve clips its history
//     against holds close to its share of them. White noise clumps, and a
//     neighbourhood that happens to hold none clips the history to the
//     background — the picture comes out darker than the sorted one, and
//     stays so however many frames are averaged;
//   * read at an offset that is the splat's own, so two splats over one pixel
//     read unrelated texels and draw independent verdicts. With the same
//     number for both, a splat behind a half-opaque one would only ever
//     survive where the front one also did, and the far layer would vanish
//     instead of showing through. The fragment does not know its splat's
//     index — the quads share `particle.vert`'s layout, which has no room for
//     one — so the offset is hashed from what does tell two splats apart at
//     one pixel and is the same at every pixel of one: its colour, and its
//     distance along the view axis, which is constant across a quad because
//     every quad lies in the camera's own plane.

in vec4 v_color;
in vec2 v_uv;
in vec3 v_world_position;

out vec4 frag_color;

/// The block `splat.frag` declares, for the fog mix it makes.
uniform FogInfo {
  /// rgb: linear fog colour. w: density per metre, zero for no fog.
  vec4 fog;

  /// xyz: camera position in world space.
  vec4 eye;
}
fog_info;

/// `EngineTables.blueNoise`: 32 slices of 64 × 64 in an 8 × 4 atlas.
uniform sampler2D blue_noise_texture;

uniform SplatHashInfo {
  /// x: the frame's slice of the blue noise, `frameIndex % 32`.
  vec4 frame;

  /// xyz: the camera's position in world space.
  vec4 eye;

  /// xyz: the camera's forward axis, unit length.
  vec4 forward;
}
splat_hash_info;

void main() {
  // The same falloff and the same cut-offs as `splat.frag`: what is kept here
  // is exactly what would have been blended there.
  float power = -0.5 * dot(v_uv, v_uv);
  if (power < -4.5) discard;

  float alpha = v_color.a * exp(power);
  if (alpha < 1.0 / 255.0) discard;

  // The splat's identity, as a whole number: millimetres along the view axis
  // and the colour in 8-bit steps. Whole numbers so that the rounding which
  // makes one fragment's interpolated colour differ from its neighbour's in
  // the last bit changes nothing, except on the rare pixel that straddles a
  // step.
  float along = dot(v_world_position - splat_hash_info.eye.xyz,
                    splat_hash_info.forward.xyz);
  float identity =
      floor(along * 1000.0) +
      floor(dot(v_color, vec4(255.0, 255.0 * 7.0, 255.0 * 31.0, 255.0 * 127.0)));
  identity = mod(identity, 4096.0);
  vec2 offset = floor(
      fract(sin(identity * vec2(12.9898, 78.233)) * 43758.5453) * 64.0);

  // This frame's slice of the blue noise at the pixel, moved by the splat's
  // offset. The same arithmetic as `BlueNoise` in `lib/blue_noise.glsl`,
  // which this does not include because it brings the `NoiseInfo` block the
  // post passes share and a slice this stage already has.
  float slice = splat_hash_info.frame.x;
  vec2 cell = mod(floor(gl_FragCoord.xy) + offset, 64.0);
  vec2 corner = vec2(mod(slice, 8.0), floor(slice / 8.0)) * 64.0;
  float threshold =
      textureLod(blue_noise_texture,
                 (corner + cell + 0.5) / vec2(512.0, 256.0),
                 0.0).r *
      (255.0 / 256.0);

  // Kept with probability `alpha`, which is what the sorted blend would have
  // given this splat's colour at this pixel had nothing been in front of it.
  if (alpha <= threshold) discard;

  vec3 colour = v_color.rgb;
  if (fog_info.fog.w > 0.0) {
    float visibility = clamp(
        exp(-fog_info.fog.w * distance(v_world_position, fog_info.eye.xyz)),
        0.0,
        1.0);
    colour = mix(fog_info.fog.rgb, colour, visibility);
  }

  // Opaque: whether the splat is here was decided above, and how much of it
  // shows is what the resolve's average says.
  frag_color = vec4(colour, 1.0);
}
