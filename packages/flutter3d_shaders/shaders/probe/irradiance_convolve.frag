#version 460 core

// One probe of the irradiance field, updated from a capture — `L4`.
//
// A `FieldPass` kernel over the whole atlas `lib/irradiance.glsl` reads: every
// texel that is not one of this probe's two tiles is copied through, and
// every texel that is gets the capture convolved into it and blended with
// what it held, by the field's hysteresis. Each step updates one probe; the
// renderer schedules a few a frame, round robin, so the field follows a
// changing room over a second or two rather than all at once.
//
// **The same arithmetic as `gatherProbe` on the host**, over the six cube
// faces the probe's capture drew instead of over rays: a cosine-weighted
// mean of the radiance for irradiance, and a mean and mean square of the
// distance under a cosine to the sixth for the moments. The capture's
// second attachment is the surface buffer, whose alpha is the depth along
// the face's own axis; the distance along a direction is that over the
// direction's component on the axis.
//
// Gutters are filled here too, from the interior texel `fillGutters` would
// copy, so a probe's tiles stay continuous without a second pass.
//
// Mode 1 is a plain copy from `seed_texture`, which is how the atlas the
// host baked becomes the one the GPU keeps updating.

in vec2 v_uv;

out vec4 frag_color;

uniform sampler2D field_texture;
uniform sampler2D seed_texture;
uniform samplerCube radiance_texture;
uniform samplerCube surface_texture;

uniform ConvolveInfo {
  /// x: the probe being updated. y: nought to update, one to seed. z: the
  /// hysteresis, the share of the old value kept. w: tiles per row.
  vec4 probe;

  /// x: an irradiance tile's interior, y: a moment tile's, in texels.
  /// z: the row the moment tiles start at. w: the distance a direction that
  /// saw only sky is given.
  vec4 tiles;

  /// xy: the atlas's size in texels. zw unused.
  vec4 atlas;
}
convolve_info;

const int kSamples = 64;

vec3 SphereDirection(int i) {
  float z = 1.0 - (2.0 * float(i) + 1.0) / float(kSamples);
  float r = sqrt(max(1.0 - z * z, 0.0));
  float phi = float(i) * 2.39996323;
  return vec3(r * cos(phi), r * sin(phi), z);
}

/// `decodeOctahedral` in `irradiance_field.dart`.
vec3 DecodeProbeOctahedral(vec2 uv) {
  vec2 xy = uv * 2.0 - 1.0;
  float z = 1.0 - abs(xy.x) - abs(xy.y);
  float t = max(-z, 0.0);
  vec3 n = vec3(xy.x + (xy.x >= 0.0 ? -t : t), xy.y + (xy.y >= 0.0 ? -t : t),
                z);
  return normalize(n);
}

/// The interior texel the stored texel [local] of a tile [interior] wide
/// stands for — itself inside, the one `fillGutters` copies in the gutter.
vec2 InteriorOf(vec2 local, float interior) {
  float last = interior - 1.0;
  vec2 i = local - 1.0;
  bool left = local.x < 0.5;
  bool right = local.x > interior + 0.5;
  bool top = local.y < 0.5;
  bool bottom = local.y > interior + 0.5;
  if ((left || right) && (top || bottom)) {
    return vec2(left ? last : 0.0, top ? last : 0.0);
  }
  if (top) return vec2(last - i.x, 0.0);
  if (bottom) return vec2(last - i.x, last);
  if (left) return vec2(0.0, last - i.y);
  if (right) return vec2(last, last - i.y);
  return i;
}

float DistanceAlong(vec3 direction) {
  float depth = textureLod(surface_texture, direction, 0.0).a;
  if (depth <= 0.0) return convolve_info.tiles.w;
  float axis = max(abs(direction.x), max(abs(direction.y), abs(direction.z)));
  return depth / max(axis, 1e-4);
}

void main() {
  vec2 size = convolve_info.atlas.xy;
  vec2 pixel = floor(v_uv * size);
  vec4 old = textureLod(field_texture, (pixel + 0.5) / size, 0.0);

  if (convolve_info.probe.y > 0.5) {
    frag_color = textureLod(seed_texture, (pixel + 0.5) / size, 0.0);
    return;
  }

  float columns = convolve_info.probe.w;
  float target = convolve_info.probe.x;
  float irradianceTile = convolve_info.tiles.x;
  float depthTile = convolve_info.tiles.y;
  float momentsTop = convolve_info.tiles.z;
  bool moments = pixel.y >= momentsTop;
  float stride = (moments ? depthTile : irradianceTile) + 2.0;
  vec2 local = moments ? vec2(pixel.x, pixel.y - momentsTop) : pixel;
  vec2 tile = floor(local / stride);
  if (tile.y * columns + tile.x != target || tile.x >= columns) {
    frag_color = old;
    return;
  }

  float interior = moments ? depthTile : irradianceTile;
  vec2 texel = InteriorOf(local - tile * stride, interior);
  vec3 normal = DecodeProbeOctahedral((texel + 0.5) / interior);

  vec3 light = vec3(0.0);
  float mean = 0.0;
  float square = 0.0;
  float weight = 0.0;
  for (int i = 0; i < kSamples; i++) {
    vec3 direction = SphereDirection(i);
    float cosine = dot(normal, direction);
    if (cosine <= 0.0) continue;
    if (moments) {
      float c2 = cosine * cosine;
      float w = c2 * c2 * c2;
      float distance = DistanceAlong(direction);
      mean += distance * w;
      square += distance * distance * w;
      weight += w;
    } else {
      light += textureLod(radiance_texture, direction, 0.0).rgb * cosine;
      weight += cosine;
    }
  }
  float keep = convolve_info.probe.z;
  if (moments) {
    vec2 fresh = weight > 0.0 ? vec2(mean, square) / weight : old.xy;
    frag_color = vec4(mix(fresh, old.xy, keep), 0.0, 1.0);
  } else {
    vec3 fresh = weight > 0.0 ? light / weight : old.rgb;
    frag_color = vec4(mix(fresh, old.rgb, keep), old.a);
  }
}
