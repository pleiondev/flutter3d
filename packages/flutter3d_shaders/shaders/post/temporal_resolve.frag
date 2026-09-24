#version 460 core

// The temporal resolve: this frame's jittered scene blended into the history
// of the frames before it, at the output's size — `R2`.
//
// Per output pixel:
//
//   * **This frame's colour** is read where the jitter put the pixel's centre,
//     so a still picture's samples land on sixteen different sub-pixel
//     positions over sixteen frames and the history averages them.
//   * **The motion** is the velocity of the nearest surface in the 3 × 3
//     scene texels around it. The nearest rather than the centre's, so an
//     edge follows the object in front and does not smear the background
//     over it.
//   * **Last frame's colour** is read from the history where the motion says
//     the pixel was, through a Catmull-Rom filter, which keeps a moving
//     picture from going soft the way a bilinear read of a bilinear read
//     does.
//   * **The history is clipped** to the colours this frame's neighbourhood
//     spans, as a box of mean ± 1.25 σ in YCoCg, so something that was there
//     and is not any more is not remembered. Clipped in a weighted space —
//     each colour divided by one plus its exposed luminance — so a single
//     bright texel does not stretch the box for everything around it.
//   * **The history is dropped** where the nearest surface there last frame
//     was at a different depth: a pixel that was the floor and is now a crate
//     has no past worth blending. The history's alpha is that depth.
//   * **The blend** weighs each side by one over one plus its exposed
//     luminance, so a flickering highlight does not dominate its neighbours.
//
// The history is linear scene light, like the scene: the exposure is only a
// weight here, and the composite applies it as it always did.

in vec2 v_uv;

out vec4 frag_color;

uniform sampler2D scene_texture;
uniform sampler2D history_texture;
uniform sampler2D velocity_texture;
uniform sampler2D surface_texture;

uniform TemporalInfo {
  /// xy: one over the scene's size in pixels. zw: the scene's size.
  vec4 scene_texel;

  /// xy: this frame's jitter as an offset in UV. z: how much of each pixel
  /// is history, nought to one. w: one when there is a history to blend,
  /// nought on the first frame and after a cut.
  vec4 jitter;

  /// x: the exposure, for the weights. y: how far apart two depths may be,
  /// as a fraction of the nearer, and still be one surface. zw: the output's
  /// size in pixels, which the history has.
  vec4 params;
}
temporal_info;

float Luma(vec3 c) { return dot(c, vec3(0.2126, 0.7152, 0.0722)); }

vec3 Weigh(vec3 c) {
  return c / (1.0 + Luma(c) * temporal_info.params.x);
}

vec3 Unweigh(vec3 c) {
  return c / max(1.0 - Luma(c) * temporal_info.params.x, 1e-4);
}

vec3 RgbToYCoCg(vec3 c) {
  return vec3(0.25 * c.r + 0.5 * c.g + 0.25 * c.b,
              0.5 * c.r - 0.5 * c.b,
              -0.25 * c.r + 0.5 * c.g - 0.25 * c.b);
}

vec3 YCoCgToRgb(vec3 c) {
  return vec3(c.x + c.y - c.z, c.x + c.z, c.x - c.y - c.z);
}

/// [q] pulled towards the box's centre until it lies inside it.
vec3 ClipToBox(vec3 lo, vec3 hi, vec3 q) {
  vec3 centre = 0.5 * (hi + lo);
  vec3 extent = 0.5 * (hi - lo) + vec3(1e-5);
  vec3 v = q - centre;
  vec3 units = abs(v / extent);
  float most = max(units.x, max(units.y, units.z));
  return most > 1.0 ? centre + v / most : q;
}

/// Catmull-Rom over the history, in nine bilinear taps.
vec3 HistoryAt(vec2 uv) {
  vec2 size = temporal_info.params.zw;
  vec2 position = uv * size;
  vec2 centre1 = floor(position - 0.5) + 0.5;
  vec2 f = position - centre1;
  vec2 w0 = f * (-0.5 + f * (1.0 - 0.5 * f));
  vec2 w1 = 1.0 + f * f * (-2.5 + 1.5 * f);
  vec2 w2 = f * (0.5 + f * (2.0 - 1.5 * f));
  vec2 w3 = f * f * (-0.5 + 0.5 * f);
  vec2 w12 = w1 + w2;
  vec2 at0 = (centre1 - 1.0) / size;
  vec2 at3 = (centre1 + 2.0) / size;
  vec2 at12 = (centre1 + w2 / w12) / size;

  vec3 sum = vec3(0.0);
  sum += texture(history_texture, vec2(at0.x, at0.y)).rgb * w0.x * w0.y;
  sum += texture(history_texture, vec2(at12.x, at0.y)).rgb * w12.x * w0.y;
  sum += texture(history_texture, vec2(at3.x, at0.y)).rgb * w3.x * w0.y;
  sum += texture(history_texture, vec2(at0.x, at12.y)).rgb * w0.x * w12.y;
  sum += texture(history_texture, vec2(at12.x, at12.y)).rgb * w12.x * w12.y;
  sum += texture(history_texture, vec2(at3.x, at12.y)).rgb * w3.x * w12.y;
  sum += texture(history_texture, vec2(at0.x, at3.y)).rgb * w0.x * w3.y;
  sum += texture(history_texture, vec2(at12.x, at3.y)).rgb * w12.x * w3.y;
  sum += texture(history_texture, vec2(at3.x, at3.y)).rgb * w3.x * w3.y;
  // The negative lobes can take a sharp edge below zero.
  return max(sum, vec3(0.0));
}

void main() {
  vec2 texel = temporal_info.scene_texel.xy;
  vec2 sceneUv = v_uv + temporal_info.jitter.xy;
  vec2 centre = (floor(sceneUv * temporal_info.scene_texel.zw) + 0.5) * texel;

  vec3 sum = vec3(0.0);
  vec3 sumSquares = vec3(0.0);
  vec3 lowest = vec3(1e30);
  vec3 highest = vec3(-1e30);
  float nearest = 1e30;
  vec2 nearestUv = centre;
  for (int dy = -1; dy <= 1; dy++) {
    for (int dx = -1; dx <= 1; dx++) {
      vec2 at = centre + vec2(float(dx), float(dy)) * texel;
      vec3 c = RgbToYCoCg(Weigh(texture(scene_texture, at).rgb));
      sum += c;
      sumSquares += c * c;
      lowest = min(lowest, c);
      highest = max(highest, c);
      float depth = texture(surface_texture, at).a;
      if (depth > 0.0 && depth < nearest) {
        nearest = depth;
        nearestUv = at;
      }
    }
  }

  vec3 current = texture(scene_texture, sceneUv).rgb;
  // The nearest depth around the pixel rather than the depth at it: on a
  // silhouette the jitter moves the centre on and off the object every
  // frame, and a history compared against that would be thrown away every
  // frame. The nearest surface in the neighbourhood stays put.
  float depth = nearest < 1e30 ? nearest : 0.0;
  vec2 then = v_uv - texture(velocity_texture, nearestUv).xy;

  if (temporal_info.jitter.w < 0.5 || then.x < 0.0 || then.x > 1.0 ||
      then.y < 0.0 || then.y > 1.0) {
    frag_color = vec4(current, depth);
    return;
  }

  float thenDepth = texture(history_texture, then).a;
  float trust = 1.0;
  if ((depth > 0.0) != (thenDepth > 0.0)) trust = 0.0;
  if (depth > 0.0 && thenDepth > 0.0 &&
      abs(thenDepth - depth) > temporal_info.params.y * min(depth, thenDepth)) {
    trust = 0.0;
  }

  vec3 mean = sum / 9.0;
  vec3 sigma = sqrt(max(sumSquares / 9.0 - mean * mean, vec3(0.0)));
  vec3 lo = max(lowest, mean - 1.25 * sigma);
  vec3 hi = min(highest, mean + 1.25 * sigma);
  vec3 history = Unweigh(
      YCoCgToRgb(ClipToBox(lo, hi, RgbToYCoCg(Weigh(HistoryAt(then))))));

  float keep = temporal_info.jitter.z * trust;
  float exposure = temporal_info.params.x;
  float wCurrent = (1.0 - keep) / (1.0 + Luma(current) * exposure);
  float wHistory = keep / (1.0 + Luma(history) * exposure);
  vec3 resolved =
      (current * wCurrent + history * wHistory) / max(wCurrent + wHistory, 1e-6);
  frag_color = vec4(resolved, depth);
}
