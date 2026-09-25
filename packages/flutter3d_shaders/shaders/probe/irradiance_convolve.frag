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
// **Every texel of the capture, each by the solid angle it covers**, rather
// than a fixed set of directions through it. A fixed set gave every update
// of a still room the same estimate, so the hysteresis settled on that
// estimate's error rather than averaging it away: a lamp or a sunlit patch a
// few texels wide was missed by one probe and counted twice by the next. At
// sixteen texels a side the whole cube is 1536 taps, cheap for a kernel that
// runs over two small tiles.
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

  /// xy: the atlas's size in texels. z: the capture's side in texels.
  /// w unused.
  vec4 atlas;
}
convolve_info;

/// Towards the centre of a texel of cube face [face] (+X, −X, +Y, −Y, +Z,
/// −Z), [a] and [b] across it in −1..1: unnormalised, the face's axis at one.
/// Which of the other two axes each coordinate names does not matter — the
/// texel centres are symmetric under either — only that every texel is
/// reached once.
vec3 CubeTexel(int face, float a, float b) {
  float side = (face & 1) == 0 ? 1.0 : -1.0;
  int axis = face >> 1;
  if (axis == 0) return vec3(side, a, b);
  if (axis == 1) return vec3(a, side, b);
  return vec3(a, b, side);
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

  int captureSide = max(int(convolve_info.atlas.z + 0.5), 1);
  float span = 2.0 / float(captureSide);
  vec3 light = vec3(0.0);
  float mean = 0.0;
  float square = 0.0;
  float weight = 0.0;
  for (int face = 0; face < 6; face++) {
    for (int row = 0; row < captureSide; row++) {
      for (int column = 0; column < captureSide; column++) {
        float a = (float(column) + 0.5) * span - 1.0;
        float b = (float(row) + 0.5) * span - 1.0;
        // A texel's solid angle goes as one over its distance from the
        // centre cubed: the square for the distance, one more for the slant.
        float inverse = inversesqrt(1.0 + a * a + b * b);
        vec3 direction = CubeTexel(face, a, b) * inverse;
        float solidAngle = inverse * inverse * inverse;
        float cosine = dot(normal, direction);
        if (cosine <= 0.0) continue;
        if (moments) {
          float c2 = cosine * cosine;
          float w = c2 * c2 * c2 * solidAngle;
          float distance = DistanceAlong(direction);
          mean += distance * w;
          square += distance * distance * w;
          weight += w;
        } else {
          float w = cosine * solidAngle;
          light += textureLod(radiance_texture, direction, 0.0).rgb * w;
          weight += w;
        }
      }
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
