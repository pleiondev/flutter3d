// The octahedral view grid an impostor is baked on and read from — C4.
//
// Shared by `impostor.vert` and `lighting/impostor.frag`, and mirrored in
// `flutter3d_core`'s `impostor_node.dart` (the bake) and `flutter3d_cpu`'s
// `cpu_shaders_impostor.dart`: the card, the camera a view was baked from and
// the cell it was baked into have to agree to the last sign, or a view is
// read mirrored.

#ifndef IMPOSTOR_GLSL_
#define IMPOSTOR_GLSL_

/// Views along each side of the atlas. Fixed in 0.8: the plan's 8 x 8, and a
/// constant so no block has to carry it.
#define kImpostorGrid 8.0

/// A direction on the sphere as a point of the unit square, with +Y at the
/// centre and -Y at the four corners — the octahedral map with Y as its pole,
/// so the views a tree is mostly seen from (level, and from above) take the
/// middle of the atlas rather than its folded edges.
vec2 ImpostorEncode(vec3 d) {
  vec3 a = abs(d);
  vec2 p = d.xz / max(a.x + a.y + a.z, 1e-8);
  vec2 s = vec2(p.x >= 0.0 ? 1.0 : -1.0, p.y >= 0.0 ? 1.0 : -1.0);
  vec2 folded = (vec2(1.0) - abs(p.yx)) * s;
  return (d.y >= 0.0 ? p : folded) * 0.5 + vec2(0.5);
}

/// The inverse of [ImpostorEncode].
vec3 ImpostorDecode(vec2 uv) {
  vec2 p = uv * 2.0 - vec2(1.0);
  float y = 1.0 - abs(p.x) - abs(p.y);
  vec2 s = vec2(p.x >= 0.0 ? 1.0 : -1.0, p.y >= 0.0 ? 1.0 : -1.0);
  vec2 folded = (vec2(1.0) - abs(p.yx)) * s;
  vec2 xz = y >= 0.0 ? p : folded;
  return normalize(vec3(xz.x, y, xz.y));
}

/// The right-hand axis of a card, or a baked view, facing along [d]: level
/// with the ground, except looking straight up or down, where "level" has no
/// direction and -Z stands in for up.
vec3 ImpostorRight(vec3 d) {
  vec3 up = abs(d.y) > 0.999 ? vec3(0.0, 0.0, -1.0) : vec3(0.0, 1.0, 0.0);
  return normalize(cross(up, d));
}

#endif  // IMPOSTOR_GLSL_
