#version 460 core

// How well exposed each part of the frame would be at three exposures —
// `R7`, the first step of local exposure.
//
// Exposure fusion: a picture taken three times, the shadows pushed up, as
// shot, and the highlights pulled down, and at each place whichever of them
// shows it best. "Best" is how near mid-grey the place comes out, which is
// the well-exposedness weight of exposure fusion. Here it is measured at an
// eighth of the frame's size, from the scene before the tone map; the blur
// that follows turns the three weights into one exposure per place, and the
// composite applies it before the curve. A dark room keeps its bright window
// and a window keeps its dark room, where one global exposure has to choose.

in vec2 v_uv;

out vec4 frag_color;

uniform sampler2D scene_texture;

uniform LocalExposureInfo {
  /// x: how many stops the shadow exposure lifts by. y: how many the
  /// highlight exposure pulls down by. zw: one texel of the scene.
  vec4 stops;

  /// x: the frame's own exposure, the one the composite multiplies by after
  /// this (auto exposure's answer when it is on). yzw unused.
  vec4 camera;
}
local_exposure_info;

float Luma(vec3 c) { return dot(c, vec3(0.2126, 0.7152, 0.0722)); }

/// How near mid-grey a scene luminance [y] comes out, from nought to one.
float WellExposed(float y) {
  float display = pow(y / (1.0 + y), 1.0 / 2.2);
  float off = display - 0.5;
  return exp(-off * off / 0.08);
}

void main() {
  // Four taps across the eighth's block, so a small bright thing counts.
  vec2 t = local_exposure_info.stops.zw * 2.0;
  float y = 0.25 * (Luma(texture(scene_texture, v_uv + vec2(-t.x, -t.y)).rgb) +
                    Luma(texture(scene_texture, v_uv + vec2(t.x, -t.y)).rgb) +
                    Luma(texture(scene_texture, v_uv + vec2(-t.x, t.y)).rgb) +
                    Luma(texture(scene_texture, v_uv + vec2(t.x, t.y)).rgb));
  // **As shot means as the camera exposed it.** The scene buffer is not
  // pre-exposed: the composite multiplies by the frame's exposure after the
  // local stops. Judged at exposure one, a dark room the meter has already
  // lifted three stops still looked underexposed and was lifted again, and a
  // scene authored in physical units looked blown everywhere. Exposure
  // fusion weighs the exposures a camera would actually have taken.
  y = max(y, 0.0) * max(local_exposure_info.camera.x, 0.0);
  float shadow = exp2(local_exposure_info.stops.x);
  float highlight = exp2(-local_exposure_info.stops.y);
  frag_color = vec4(WellExposed(y * shadow) + 1e-4, WellExposed(y) + 1e-4,
                    WellExposed(y * highlight) + 1e-4, 1.0);
}
