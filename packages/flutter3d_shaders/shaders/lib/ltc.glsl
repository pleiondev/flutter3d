// The GGX lobe over a rectangle light, by linearly transformed cosines — `L7`.
//
// Heitz, Dupuy, Hill and Neubelt, "Real-Time Polygonal-Light Shading with
// Linearly Transformed Cosines", ACM TOG 35(4), 2016. The fitted tables are
// `EngineTables.ltc`; see `tables/ltc.dart` for their layout and licence.
//
// A model that wants it defines `F3D_LTC` before including `surface.glsl`,
// which is what gives its stage the one sampler below. Every other model
// keeps the representative point, and no sampler.

#ifndef LTC_GLSL_
#define LTC_GLSL_

/// Both tables, 64 × 128: the inverse matrices above, the norms, Fresnel
/// terms and sphere form factors below.
uniform sampler2D ltc_texture;

/// Where `(x, y)`, each nought to one, lands in the table starting at
/// [table] (nought the upper, one the lower): on texel centres, so the ends of
/// the range read the first and last entries rather than half of the
/// neighbour.
vec2 LtcUv(float x, float y, float table) {
  vec2 inTable = vec2(x, y) * (63.0 / 64.0) + 0.5 / 64.0;
  return vec2(inTable.x, (inTable.y + table) * 0.5);
}

/// One edge's share of the vector form factor, from [a] to [b], unit
/// directions: the angle between them along the normal of their plane,
/// over 2π. Exact, with the `acos` clamped for the reason
/// `RectangleFormFactor` gives.
vec3 LtcEdge(vec3 a, vec3 b) {
  vec3 axis = cross(a, b);
  float len = length(axis);
  float angle = acos(clamp(dot(a, b), -1.0, 1.0));
  return len > 1e-6 ? axis * (angle / (len * 6.2831853)) : vec3(0.0);
}

/// The GGX lobe of roughness [roughness] seen along [v] from normal [n],
/// integrated over the rectangle with corners [corners] (relative to the
/// shading point, wound as `SampleLight` winds them), with the fitted
/// Fresnel pair for that lobe: x the integral, y the norm, z the Fresnel
/// term. The specular is `x · (f0 · y + (1 − f0) · z)`.
///
/// Clipped to the horizon by the sphere table rather than by cutting the
/// polygon: the vector form factor's length and elevation name a sphere
/// with the same, and the table holds how much of that sphere's clamped
/// cosine lies above the horizon.
///
/// Says nothing about which face of the panel the point is on: the vector
/// form factor points the same way in the world from either side, so this is
/// as bright behind the panel as in front of it. `SampleLight` tests the side
/// and leaves a point behind unlit before this is asked.
vec3 LtcRectangle(vec3 n, vec3 v, float roughness, vec3 corners[4]) {
  vec2 uv = vec2(clamp(roughness, 0.0, 1.0),
                 sqrt(clamp(1.0 - dot(n, v), 0.0, 1.0)));
  vec4 inverse = textureLod(ltc_texture, LtcUv(uv.x, uv.y, 0.0), 0.0);
  vec4 fit = textureLod(ltc_texture, LtcUv(uv.x, uv.y, 1.0), 0.0);

  // The frame the fit was made in: the normal up, the view in the xz plane.
  // A view along the normal has no plane of its own, and any will do.
  vec3 along = v - n * dot(v, n);
  float alongLength = length(along);
  vec3 t1 = alongLength > 1e-5
                ? along / alongLength
                : normalize(cross(n, abs(n.z) < 0.999 ? vec3(0.0, 0.0, 1.0)
                                                      : vec3(1.0, 0.0, 0.0)));
  vec3 t2 = cross(n, t1);
  mat3 minv = mat3(vec3(inverse.x, 0.0, inverse.y), vec3(0.0, 1.0, 0.0),
                   vec3(inverse.z, 0.0, inverse.w));

  vec3 l[4];
  for (int i = 0; i < 4; i++) {
    vec3 p = corners[i];
    l[i] = normalize(minv * vec3(dot(p, t1), dot(p, t2), dot(p, n)));
  }
  // Negated, for `RectangleFormFactor`'s reason: the panel emits along
  // `cross(halfWidth, halfHeight)`, and seen from there these corners run
  // clockwise.
  vec3 f = -(LtcEdge(l[0], l[1]) + LtcEdge(l[1], l[2]) +
             LtcEdge(l[2], l[3]) + LtcEdge(l[3], l[0]));
  float len = length(f);
  float z = len > 1e-9 ? f.z / len : 0.0;
  float sphere =
      textureLod(ltc_texture, LtcUv(z * 0.5 + 0.5, clamp(len, 0.0, 1.0), 1.0),
                 0.0)
          .w;
  return vec3(max(len * sphere, 0.0), fit.x, fit.y);
}

#endif  // LTC_GLSL_
