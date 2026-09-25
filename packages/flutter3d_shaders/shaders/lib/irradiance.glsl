// The irradiance field, read per pixel — `L3`.
//
// **Per pixel where it was per object.** The field used to be sampled once
// per draw at the node's centre, twice (up and down), and handed to the shader
// as the hemisphere ambient. A floor that runs from a red wall to a blue one
// then took one colour, whichever its middle saw. Read here, at each point,
// the red bleeds onto the floor near the red wall and fades across it.
//
// The field arrives as one float texture: every probe's irradiance tile (rgb,
// with the probe's "active" flag in alpha) in a grid of `columns` × `rows`
// tiles at the top, and every probe's depth-moment tile (mean and mean
// square) in the same grid below. Each tile carries a one-texel gutter, so a
// bilinear read inside it never needs to know where the tile ends. The read
// is done here, four nearest taps at a time, rather than by a filtered
// sampler: a filtered float texture is a capability three backends answer
// differently, and four taps are the same on all of them.
//
// Weights per probe, as `IrradianceField.sample` on the host: trilinear by
// the point's place in its cell, the square of a half-cosine towards the
// probe, and Chebyshev's bound from the depth moments, the last two floored
// and crushed so no active probe's weight reaches nought. The point is moved
// off its surface along the normal and towards the eye first, so a surface
// does not read the probe's own view of it as a wall.
//
// Included by the lit models only, through `material_maps.glsl`.

#ifndef IRRADIANCE_GLSL_
#define IRRADIANCE_GLSL_

uniform sampler2D irradiance_texture;

uniform IrradianceInfo {
  /// xyz: where probe (0, 0, 0) stands. w: one when the field is read,
  /// nought when the hemisphere ambient stands.
  vec4 origin;

  /// xyz: the spacing between probes per axis. w: how far the point is
  /// moved along the normal, in metres.
  vec4 spacing;

  /// xyz: probes per axis. w: how far the point is moved towards the eye.
  vec4 counts;

  /// x: an irradiance tile's interior, y: a moment tile's, in texels.
  /// z: tiles per row of the atlas. w: the row the moment tiles start at.
  vec4 tiles;

  /// xy: one over the atlas's size. zw unused.
  vec4 atlas;
}
irradiance_info;

bool IrradianceEnabled() { return irradiance_info.origin.w > 0.5; }

/// `encodeOctahedral` in `irradiance_field.dart`.
vec2 ProbeOctahedral(vec3 direction) {
  float sum = abs(direction.x) + abs(direction.y) + abs(direction.z);
  if (sum <= 0.0) return vec2(0.5);
  vec3 n = direction / sum;
  vec2 xy = n.xy;
  if (n.z < 0.0) {
    xy = vec2((1.0 - abs(n.y)) * (n.x >= 0.0 ? 1.0 : -1.0),
              (1.0 - abs(n.x)) * (n.y >= 0.0 ? 1.0 : -1.0));
  }
  return xy * 0.5 + 0.5;
}

vec4 AtlasTexel(vec2 texel) {
  return textureLod(irradiance_texture, (texel + 0.5) * irradiance_info.atlas.xy,
                    0.0);
}

/// A bilinear read of the tile whose top-left stored texel is [corner],
/// [interior] wide, at the octahedral [uv].
vec4 TileBilinear(vec2 corner, float interior, vec2 uv) {
  vec2 at = 1.0 + uv * interior - 0.5;
  vec2 low = floor(at);
  vec2 f = at - low;
  vec4 a = AtlasTexel(corner + low);
  vec4 b = AtlasTexel(corner + low + vec2(1.0, 0.0));
  vec4 c = AtlasTexel(corner + low + vec2(0.0, 1.0));
  vec4 d = AtlasTexel(corner + low + vec2(1.0, 1.0));
  return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

/// The irradiance arriving at [world] on a surface facing [normal], seen
/// from the direction [view] (a unit vector towards the eye).
vec3 SampleIrradiance(vec3 world, vec3 normal, vec3 view) {
  vec3 origin = irradiance_info.origin.xyz;
  vec3 spacing = irradiance_info.spacing.xyz;
  vec3 counts = irradiance_info.counts.xyz;
  float irradianceTile = irradiance_info.tiles.x;
  float depthTile = irradiance_info.tiles.y;
  float columns = irradiance_info.tiles.z;
  float momentsTop = irradiance_info.tiles.w;
  vec3 unit = normalize(normal);

  vec3 biased = world + unit * irradiance_info.spacing.w +
                view * irradiance_info.counts.w;
  vec3 grid = (biased - origin) / spacing;
  vec3 base = clamp(floor(grid), vec3(0.0), counts - 2.0);
  vec3 f = clamp(grid - base, vec3(0.0), vec3(1.0));

  vec3 total = vec3(0.0);
  float weights = 0.0;
  for (int corner = 0; corner < 8; corner++) {
    vec3 offset = vec3(float(corner & 1), float((corner >> 1) & 1),
                       float((corner >> 2) & 1));
    vec3 cell = base + offset;
    float probe = (cell.z * counts.y + cell.y) * counts.x + cell.x;
    vec2 tile = vec2(mod(probe, columns), floor(probe / columns));

    vec2 irradianceCorner = tile * (irradianceTile + 2.0);
    vec2 momentCorner = vec2(tile.x * (depthTile + 2.0),
                             momentsTop + tile.y * (depthTile + 2.0));

    // The probe's own flag, on the tile's first interior texel.
    if (AtlasTexel(irradianceCorner + 1.0).a < 0.5) continue;

    vec3 trilinear = mix(vec3(1.0) - f, f, offset);
    float weight = max(trilinear.x * trilinear.y * trilinear.z, 0.001);

    vec3 probePosition = origin + spacing * cell;
    vec3 toProbe = probePosition - biased;
    float distance = length(toProbe);
    if (distance > 1e-6) {
      vec3 direction = toProbe / distance;
      // Facing and visibility are floored, then crushed, rather than let
      // fall to nought (Majercik et al. 2019): a probe behind the surface or
      // past a wall counts for almost nothing but never for nothing, so a
      // point every probe of its cell is cut off from still reads a blend of
      // them rather than black.
      float facing = dot(unit, normalize(probePosition - world)) * 0.5 + 0.5;
      float probeWeight = facing * facing + 0.2;

      vec2 moments = TileBilinear(momentCorner, depthTile,
                                  ProbeOctahedral(-direction)).xy;
      float chebyshev = 1.0;
      if (distance > moments.x) {
        float variance = max(moments.y - moments.x * moments.x, 1e-6);
        float difference = distance - moments.x;
        chebyshev = variance / (variance + difference * difference);
        chebyshev = chebyshev * chebyshev * chebyshev;
      }
      probeWeight = max(probeWeight * max(chebyshev, 0.05), 1e-6);
      if (probeWeight < 0.2) probeWeight *= probeWeight * probeWeight * 25.0;
      weight *= probeWeight;
    }

    total += TileBilinear(irradianceCorner, irradianceTile,
                          ProbeOctahedral(unit)).rgb *
             weight;
    weights += weight;
  }
  return weights > 0.0 ? total / weights : vec3(0.0);
}

#endif  // IRRADIANCE_GLSL_
