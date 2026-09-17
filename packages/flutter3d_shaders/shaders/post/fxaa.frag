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
}
fxaa_info;

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

  vec3 middle = texture(source_texture, v_uv).rgb;
  float mid = Weight(middle);

  // The four edge neighbours. Diagonals are deliberately left out: they cost
  // four more samples and only sharpen the direction estimate on a corner,
  // which is the one place this pass should be doing the least.
  float north = Weight(texture(source_texture, v_uv + vec2(0.0, -texel.y)).rgb);
  float south = Weight(texture(source_texture, v_uv + vec2(0.0, texel.y)).rgb);
  float west = Weight(texture(source_texture, v_uv + vec2(-texel.x, 0.0)).rgb);
  float east = Weight(texture(source_texture, v_uv + vec2(texel.x, 0.0)).rgb);

  float lowest = min(mid, min(min(north, south), min(west, east)));
  float highest = max(mid, max(max(north, south), max(west, east)));
  float contrast = highest - lowest;

  // **Relative to the local brightness, not absolute.** A step of 0.02 across
  // a dark surface is an edge somebody can see; the same step across a white
  // wall is dithering. A fixed threshold either scrubs the dark parts of the
  // frame or leaves the bright parts crawling, and this frame has both.
  if (contrast < max(0.0312, highest * fxaa_info.params.z)) {
    frag_color = vec4(middle, 1.0);
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
  frag_color = vec4(texture(source_texture, v_uv + offset).rgb, 1.0);
}
