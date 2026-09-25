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
//
// The algorithm is FXAA 3.11 Quality at preset 12: the early exit on local
// contrast, the direction from the 3x3 second differences, the search along
// the edge for both of its ends, and the sub-pixel term, the larger of the
// two offsets winning. The search is what smooths a long, shallow staircase:
// without it a pixel only knows its neighbours and moves the same whether it
// sits at the start of a step or at its end.
precision highp float;

in vec2 v_uv;

out vec4 frag_color;

/// The composited frame, already tone mapped and sRGB encoded.
uniform sampler2D source_texture;

uniform FxaaInfo {
  /// x, y: one texel. z: the contrast a pixel needs before it is worth
  /// touching, as a fraction of the local maximum. w: the sub-pixel amount,
  /// FXAA's `subpix`: the most a pixel moves on local contrast alone, in
  /// texels.
  vec4 params;

  /// x: contrast-adaptive sharpening, 0 for none. y: one for the robust
  /// kernel a temporal resolve is followed by (`R2`), nought for the one
  /// below. z, w: unclaimed.
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

/// The largest of the three.
float MaxChannel(vec3 v) { return max(v.x, max(v.y, v.z)); }

/// Robust contrast-adaptive sharpening, after a temporal resolve — `R2`.
///
/// The cross-shaped kernel FSR 1 publishes: the negative lobe each neighbour
/// gets is the largest that keeps every channel of the result inside the
/// neighbourhood's own range, so it cannot ring past what was there. Limited
/// to three sixteenths, where the kernel stops being a sharpen and starts
/// being noise — which also keeps the denominator at a quarter or more, the
/// hole the kernel below fell into at a quarter exactly.
vec3 SharpenRobust(vec3 centre, vec3 n, vec3 s, vec3 w, vec3 e, float amount) {
  vec3 lowest = min(min(n, s), min(w, e));
  vec3 highest = max(max(n, s), max(w, e));
  vec3 hitMin = lowest / max(4.0 * highest, vec3(1e-5));
  vec3 hitMax = (vec3(1.0) - highest) / min(4.0 * lowest - 4.0, vec3(-1e-5));
  vec3 lobeRgb = max(-hitMin, hitMax);
  float lobe = max(-0.1875, min(MaxChannel(lobeRgb), 0.0)) * amount;
  return (lobe * (n + s + w + e) + centre) / (4.0 * lobe + 1.0);
}

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
  if (fxaa_info.sharpen.y > 0.5) {
    return SharpenRobust(centre, n, s, w, e, strength);
  }

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

/// The edge search's steps, in texels, after the first one texel —
/// FXAA 3.11's quality preset 12 (`FXAA_QUALITY__P1` to `P4`). Selects
/// rather than a table: the OpenGL ES target has no constant arrays worth
/// indexing, and a chain of ternaries is one select per step.
float SearchStep(int i) {
  return i == 1 ? 1.5 : (i == 2 ? 2.0 : (i == 3 ? 4.0 : 12.0));
}

/// Steps the edge search takes, the first included.
const int kSearchSteps = 5;

void main() {
  vec2 texel = fxaa_info.params.xy;

  // `textureLod` throughout this pass, for `shadow.glsl`'s own reason: every
  // tap after the early return below, the edge search's above all, sits in
  // control flow that differs per fragment, so a WGSL backend refuses the
  // implicit derivative as possibly non-uniform. The composited frame is read
  // at its native size with no mipmap of its own, so naming level zero
  // directly changes no pixel.
  vec3 middle = textureLod(source_texture, v_uv, 0.0).rgb;
  float mid = Weight(middle);

  // The four edge neighbours, colours kept: the sharpening at the end needs
  // the neighbourhood itself, and these are the same four taps either way.
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

  // FXAA 3.11 Quality from here on, step for step. The diagonals only for
  // pixels past the early exit: they sharpen the direction estimate at a
  // corner and weigh into the sub-pixel average.
  float northWest = Weight(textureLod(source_texture, v_uv - texel, 0.0).rgb);
  float southEast = Weight(textureLod(source_texture, v_uv + texel, 0.0).rgb);
  float northEast = Weight(
      textureLod(source_texture, v_uv + vec2(texel.x, -texel.y), 0.0).rgb);
  float southWest = Weight(
      textureLod(source_texture, v_uv + vec2(-texel.x, texel.y), 0.0).rgb);

  // Which way the edge runs: the second differences across it, the middle
  // row counted twice. A horizontal edge changes most from north to south.
  float edgeHorizontal =
      abs(northWest + southWest - 2.0 * west) +
      2.0 * abs(north + south - 2.0 * mid) +
      abs(northEast + southEast - 2.0 * east);
  float edgeVertical =
      abs(northWest + northEast - 2.0 * north) +
      2.0 * abs(west + east - 2.0 * mid) +
      abs(southWest + southEast - 2.0 * south);
  bool horizontalSpan = edgeHorizontal >= edgeVertical;

  // The sub-pixel term: how far the middle sits from the 3x3 low-pass (the
  // cross twice, the corners once, over twelve), against the local range,
  // through a smoothstep and squared.
  float lowPass = (2.0 * (north + south + west + east) +
                   northWest + northEast + southWest + southEast) / 12.0;
  float subpixC = clamp(abs(lowPass - mid) / contrast, 0.0, 1.0);
  float subpixF = (3.0 - 2.0 * subpixC) * subpixC * subpixC;
  float subpixH = subpixF * subpixF * fxaa_info.params.w;

  // The two neighbours across the edge, and the steeper side. On a tie the
  // north (or west) one, as FXAA's `pairN` has it.
  float lumaN = horizontalSpan ? north : west;
  float lumaS = horizontalSpan ? south : east;
  float gradientN = lumaN - mid;
  float gradientS = lumaS - mid;
  bool pairN = abs(gradientN) >= abs(gradientS);
  float gradient = max(abs(gradientN), abs(gradientS));
  float lengthSign = horizontalSpan ? texel.y : texel.x;
  if (pairN) lengthSign = -lengthSign;
  float pairAverage = 0.5 * (pairN ? lumaN + mid : lumaS + mid);

  // **The edge search.** Half a texel onto the steeper side, so a bilinear
  // tap straddles the edge, then outwards both ways along it until the
  // straddled average leaves the pair's average by a quarter of the
  // gradient: that is where the edge ends. Knowing both ends is what lets a
  // pixel on a long shallow staircase know where on its step it sits, which
  // the local neighbourhood alone cannot say.
  vec2 along = horizontalSpan ? vec2(texel.x, 0.0) : vec2(0.0, texel.y);
  vec2 start = v_uv + (horizontalSpan ? vec2(0.0, lengthSign * 0.5)
                                      : vec2(lengthSign * 0.5, 0.0));
  float gradientScaled = gradient * 0.25;
  vec2 posN = start - along;
  vec2 posP = start + along;
  float endN = Weight(textureLod(source_texture, posN, 0.0).rgb) - pairAverage;
  float endP = Weight(textureLod(source_texture, posP, 0.0).rgb) - pairAverage;
  bool doneN = abs(endN) >= gradientScaled;
  bool doneP = abs(endP) >= gradientScaled;
  for (int i = 1; i < kSearchSteps; i++) {
    if (doneN && doneP) break;
    float stride = SearchStep(i);
    if (!doneN) {
      posN -= along * stride;
      endN = Weight(textureLod(source_texture, posN, 0.0).rgb) - pairAverage;
      doneN = abs(endN) >= gradientScaled;
    }
    if (!doneP) {
      posP += along * stride;
      endP = Weight(textureLod(source_texture, posP, 0.0).rgb) - pairAverage;
      doneP = abs(endP) >= gradientScaled;
    }
  }

  // The nearer end decides. Its luma has to have gone the other way from the
  // middle's, or this pixel is on the far side of that end's step and is
  // not moved by the edge at all; otherwise it moves by how near that end
  // it is, half a texel at the end itself and nothing at the span's middle.
  float distanceN = horizontalSpan ? v_uv.x - posN.x : v_uv.y - posN.y;
  float distanceP = horizontalSpan ? posP.x - v_uv.x : posP.y - v_uv.y;
  bool middleBelow = mid - pairAverage < 0.0;
  bool nearerN = distanceN < distanceP;
  bool goodSpan = nearerN ? (endN < 0.0) != middleBelow
                          : (endP < 0.0) != middleBelow;
  float nearest = min(distanceN, distanceP);
  float pixelOffset = 0.5 - nearest / (distanceN + distanceP);
  float offset = max(goodSpan ? pixelOffset : 0.0, subpixH);

  vec2 at = v_uv + (horizontalSpan ? vec2(0.0, offset * lengthSign)
                                   : vec2(offset * lengthSign, 0.0));
  vec3 smoothed = textureLod(source_texture, at, 0.0).rgb;
  frag_color =
      vec4(Sharpen(smoothed, northRgb, southRgb, westRgb, eastRgb), 1.0);
}
