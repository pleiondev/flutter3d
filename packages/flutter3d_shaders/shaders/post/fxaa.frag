#version 460 core

// Edges smoothed after the fact, on the finished picture.
//
// **This exists to end a choice nobody should have to make.** The scene pass
// turns MSAA off whenever anything consumes the surface buffer, because a
// multisampled attachment and a buffer something else reads back are the same
// decision made two ways — so switching ambient occlusion on cost every edge
// in the frame its smoothing. A game got shadows in its corners or clean
// silhouettes, and not both.
//
// Working on the composited image rather than on the scene is what makes that
// possible, and it is also what makes this cheap: one pass, one texture, no
// depth, no second attachment, no knowledge of geometry at all. What it
// cannot do is help an edge the rasteriser never saw — a thin wire that fell
// between two pixel centres is gone before this reads it, which MSAA would
// have caught. Named here because it is the honest limit of the technique
// rather than a defect in this implementation.
precision highp float;

in vec2 v_uv;

out vec4 frag_color;

/// The composited frame, already tone mapped and sRGB encoded.
uniform sampler2D source_texture;

uniform FxaaInfo {
  /// x, y: one texel. z: the contrast a pixel needs before it is worth
  /// touching, as a fraction of the local maximum. w: how far along the edge
  /// to sample, in texels.
  vec4 params;

  /// x: contrast-adaptive sharpening, 0 for none. y, z, w: unclaimed.
  ///
  /// **A second block member rather than a fifth component**, because
  /// `params` is full — and because sharpening is not an anti-aliasing
  /// parameter. It rides in this pass for one reason: the four taps it needs
  /// are the four this pass already fetches.
  vec4 sharpen;
}
fxaa_info;

/// The smallest of the three, which GLSL has no builtin for.
float MinChannel(vec3 v) { return min(v.x, min(v.y, v.z)); }

/// Contrast-adaptive sharpening over the cross this pass already sampled —
/// `gfx-29n`.
///
/// **Why it is here and not in a pass of its own.** Output sharpening is what
/// normally follows an FXAA-softened image, and the neighbourhood it needs is
/// the four taps the smoothing already fetched. A pass of its own would be a
/// second full-screen draw and four more texture reads for the same answer.
///
/// **Adaptive, which is the whole of the name.** A plain unsharp mask
/// overshoots wherever the neighbourhood is already near an extreme — the
/// bright halo along a hard edge that reads as a cheap filter. The amplitude
/// here is taken from how much headroom the darkest and lightest neighbours
/// leave, so a pixel with room is sharpened and a pixel already against the
/// ceiling is not.
///
/// **Pushed away from the neighbourhood average, with no denominator.** The
/// first version here used the normalised kernel a sharpener usually has —
/// `(c + w*(n+s+w+e)) / (1 + 4w)` — and that form has a hole in it with four
/// neighbours: the denominator is zero at `w = -0.25`, which is exactly where
/// full strength on a pixel with full headroom lands. A flat grey frame came
/// back white. Measured, not reasoned about: 96 went to 255 on every pixel.
///
/// This form has no denominator to vanish. A flat neighbourhood has the
/// centre equal to its own average, so the difference is zero and the pixel
/// is returned untouched — an identity by construction rather than by
/// algebra that happens to cancel.
vec3 Sharpen(vec3 centre, vec3 n, vec3 s, vec3 w, vec3 e) {
  float strength = fxaa_info.sharpen.x;
  if (strength <= 0.0) return centre;

  vec3 lowest = min(centre, min(min(n, s), min(w, e)));
  vec3 highest = max(centre, max(max(n, s), max(w, e)));
  // How much room is left at the nearer end. Per channel, because a red edge
  // against white has headroom in two channels and none in the third.
  vec3 room = min(lowest, vec3(1.0) - highest) / max(highest, vec3(1e-5));
  float amount = clamp(sqrt(clamp(MinChannel(room), 0.0, 1.0)), 0.0, 1.0);

  vec3 average = (n + s + w + e) * 0.25;
  return centre + (centre - average) * amount * strength;
}

/// Perceptual weight, on the encoded image.
///
/// Green-weighted rather than Rec. 709 luma: this runs *after* the sRGB
/// encode, so the values are not linear light and a photometric weighting
/// would be measuring the wrong space. What the algorithm needs is a number
/// that moves when a person would see an edge, and green carries most of
/// that.
float Weight(vec3 color) { return dot(color, vec3(0.299, 0.587, 0.114)); }

void main() {
  vec2 texel = fxaa_info.params.xy;

  // `textureLod` throughout this pass, for `shadow.glsl`'s own reason: the
  // last of these six taps sits after the early return below, so a WGSL
  // backend sees a sample that need not be reached by every invocation of a
  // quad and refuses the implicit derivative as possibly non-uniform. The
  // composited frame is read at its native size with no mipmap of its own, so
  // naming level zero directly changes no pixel.
  vec3 middle = textureLod(source_texture, v_uv, 0.0).rgb;
  float mid = Weight(middle);

  // The four edge neighbours. Diagonals are deliberately left out: they cost
  // four more samples and only sharpen the direction estimate on a corner,
  // which is the one place this pass should be doing the least.
  // The colours are kept, not just their weights: the sharpening at the end
  // needs the neighbourhood itself, and these are the same four taps either
  // way. Discarding the colour and re-fetching it would be four more.
  vec3 northRgb = textureLod(source_texture, v_uv + vec2(0.0, -texel.y), 0.0).rgb;
  vec3 southRgb = textureLod(source_texture, v_uv + vec2(0.0, texel.y), 0.0).rgb;
  vec3 westRgb = textureLod(source_texture, v_uv + vec2(-texel.x, 0.0), 0.0).rgb;
  vec3 eastRgb = textureLod(source_texture, v_uv + vec2(texel.x, 0.0), 0.0).rgb;
  float north = Weight(northRgb);
  float south = Weight(southRgb);
  float west = Weight(westRgb);
  float east = Weight(eastRgb);

  float lowest = min(mid, min(min(north, south), min(west, east)));
  float highest = max(mid, max(max(north, south), max(west, east)));
  float contrast = highest - lowest;

  // **Relative to the local brightness, not absolute.** A step of 0.02 across
  // a dark surface is an edge somebody can see; the same step across a white
  // wall is dithering. A fixed threshold either scrubs the dark parts of the
  // frame or leaves the bright parts crawling, and this frame has both.
  if (contrast < max(0.0312, highest * fxaa_info.params.z)) {
    frag_color = vec4(
        Sharpen(middle, northRgb, southRgb, westRgb, eastRgb), 1.0);
    return;
  }

  // Which way the edge runs. The vertical difference is larger on a
  // horizontal edge, which is the one to blend across.
  float vertical = abs(north + south - 2.0 * mid);
  float horizontal = abs(west + east - 2.0 * mid);
  bool horizontalEdge = vertical >= horizontal;

  // And which side of it is the darker one, so the blend moves towards the
  // neighbour rather than away from it.
  float towards = horizontalEdge ? south - mid : east - mid;
  float away = horizontalEdge ? north - mid : west - mid;
  float step_length = horizontalEdge ? texel.y : texel.x;
  if (abs(away) > abs(towards)) step_length = -step_length;

  // **How far to go: how wrong this pixel is against its neighbourhood.** A
  // white pixel with a black neighbour sits far from the average of the four
  // and has to move most; a pixel already near that average is already the
  // blend and moves least.
  //
  // Measuring the distance from the *end* of the range instead — which the
  // first version of this did — gives exactly zero on a hard black-to-white
  // edge, because every pixel there is at one end or the other. The pass ran,
  // cost a draw, and changed nothing, which is the failure this arithmetic
  // exists to avoid.
  float average = (north + south + west + east) * 0.25;
  float blend = clamp(abs(average - mid) / max(contrast, 1e-5), 0.0, 1.0);
  // Squared, so a faint gradient is left alone and a real edge gets the whole
  // step: the difference between smoothing an edge and smearing a texture.
  blend = blend * blend * fxaa_info.params.w;

  vec2 offset = horizontalEdge ? vec2(0.0, step_length * blend)
                               : vec2(step_length * blend, 0.0);
  vec3 smoothed = textureLod(source_texture, v_uv + offset, 0.0).rgb;
  frag_color =
      vec4(Sharpen(smoothed, northRgb, southRgb, westRgb, eastRgb), 1.0);
}
