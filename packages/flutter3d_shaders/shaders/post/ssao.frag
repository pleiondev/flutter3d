#version 460 core

// Screen-space ambient occlusion, read out of the surface buffer.
//
// What it measures is how much of the sky a point can see. That is the same
// question the hemispheric ambient in `lib/surface.glsl` answers by looking at
// the normal alone, and the reason the two belong together: ambient without
// occlusion lifts the inside of a corner exactly as much as the outside of one,
// and no amount of colour makes that read as light.
//
// **Nothing here needs a depth texture, and that is not a preference.**
// flutter_gpu cannot sample a depth attachment at all, so the engine's depth
// lives in the alpha channel of the surface buffer — see `WriteSurfaceGeometry`
// in `lib/color.glsl`. Every screen-space effect in this renderer is built on
// that one decision, and this stage inherits it rather than working around it.
//
// The cost that must be stated rather than discovered: reading the surface
// buffer turns MSAA off for the whole scene pass, because the average of two
// octahedral normals is not the encoding of any normal. Switching this on
// therefore changes the antialiasing of the entire frame, not just the shading
// in its corners.
precision highp float;

in vec2 v_uv;

out vec4 frag_color;

uniform sampler2D surface_texture;

uniform SsaoInfo {
  /// Screen to world, for turning a stored depth back into a point.
  ///
  /// Carries the framebuffer origin, as its partner below does — see
  /// [UvFromNdc].
  mat4 inverse_view_projection;

  /// World to screen, for finding where a sampled point lands.
  mat4 view_projection;

  /// x: radius in world metres. y: how many samples. w: bias in metres, which
  /// keeps a flat surface from occluding itself.
  ///
  /// z is unused: the strength belongs to the composite, which is the pass that
  /// has to make "off" mean a multiplier of exactly one. It is left in place
  /// rather than removed so the block's layout does not depend on that staying
  /// true.
  vec4 params;

  /// x: 1/width, y: 1/height of *this* target, which is half the scene's.
  /// z, w unused.
  vec4 screen;
}
ssao_info;

vec3 DecodeOctahedral(vec2 e) {
  e = e * 2.0 - 1.0;
  vec3 n = vec3(e.xy, 1.0 - abs(e.x) - abs(e.y));
  float t = max(-n.z, 0.0);
  n.x += n.x >= 0.0 ? -t : t;
  n.y += n.y >= 0.0 ? -t : t;
  return normalize(n);
}

/// Where a point at clip-space [ndc] lands in the surface buffer.
///
/// **v runs the other way from y, and the matrix is what makes that true on
/// both backends** — the convention `lib/surface.glsl` reads shadow maps with,
/// and the one this pass should have had. `toFramebufferOrigin` negates y in
/// the matrices below for the backend whose row zero is at the bottom.
///
/// Written the other way round — `ndc * 0.5 + 0.5`, with unadjusted matrices —
/// this pass reconstructed the point at the pixel mirrored about the middle of
/// the frame and took its taps around that, on every backend but the browser.
vec2 UvFromNdc(vec2 ndc) {
  return vec2(ndc.x * 0.5 + 0.5, 0.5 - ndc.y * 0.5);
}

vec3 WorldFromDepth(vec2 uv, float depth) {
  // y undoes [UvFromNdc]: a point projected and then reconstructed has to come
  // back where it started.
  vec4 ndc = vec4(uv.x * 2.0 - 1.0, 1.0 - uv.y * 2.0, depth, 1.0);
  vec4 world = ssao_info.inverse_view_projection * ndc;
  return world.xyz / world.w;
}

/// Twelve directions on a hemisphere, as a fixed table.
///
/// A table rather than a hash of the fragment coordinate, and the reason is the
/// conformance suite rather than taste: the cross-backend budgets in this
/// repository are measured in hundredths of a per cent, and a float hash agrees
/// between a GPU and a software rasteriser nowhere. A table is the same twelve
/// numbers everywhere.
///
/// Lengths vary deliberately, packing more samples near the origin: occlusion
/// falls off with distance, so uniform spacing spends most of its taps where
/// they matter least.
vec3 KernelTap(int i) {
  if (i == 0) return vec3(0.5381, 0.1856, 0.4319);
  if (i == 1) return vec3(0.1379, 0.2486, 0.4430);
  if (i == 2) return vec3(0.3371, 0.5679, 0.0057);
  if (i == 3) return vec3(-0.6999, -0.0451, 0.0019);
  if (i == 4) return vec3(0.0689, -0.1598, -0.8547);
  if (i == 5) return vec3(0.0560, 0.0069, -0.1843);
  if (i == 6) return vec3(-0.0146, 0.1402, 0.0762);
  if (i == 7) return vec3(0.0100, -0.1924, -0.0344);
  if (i == 8) return vec3(-0.3577, -0.5301, -0.4358);
  if (i == 9) return vec3(-0.3169, 0.1063, 0.0158);
  if (i == 10) return vec3(0.0103, -0.5869, 0.0046);
  return vec3(-0.0897, -0.4940, 0.3287);
}

/// One of four rotations, chosen by the parity of the pixel.
///
/// Four constants rather than a random angle, for the same reason the kernel is
/// a table. It leaves a 2×2 pattern in the result, which is exactly what the
/// composite's 2×2 average cancels — the blur is sized to the artefact rather
/// than guessed at, and the two have to change together or neither works.
vec2 Rotation(vec2 uv) {
  vec2 pixel = floor(uv / ssao_info.screen.xy);
  bool oddX = mod(pixel.x, 2.0) >= 1.0;
  bool oddY = mod(pixel.y, 2.0) >= 1.0;
  if (oddX && oddY) return vec2(-0.7071, -0.7071);
  if (oddX) return vec2(0.7071, -0.7071);
  if (oddY) return vec2(-0.7071, 0.7071);
  return vec2(1.0, 0.0);
}

void main() {
  vec4 surface = texture(surface_texture, v_uv);

  // Nothing was drawn here. The buffer is cleared to zero and a zero alpha is
  // the sky, not a surface sitting on the near plane — the same test
  // `reflections.frag` makes, and for the same reason.
  if (surface.a <= 0.0) {
    frag_color = vec4(1.0);
    return;
  }

  vec3 normal = DecodeOctahedral(surface.rg);

  float radius = max(ssao_info.params.x, 1e-4);
  int samples = clamp(int(ssao_info.params.y + 0.5), 1, 12);

  // Lifted off the surface along its own normal, and this is where the bias
  // goes rather than into the depth comparison below. A bias in window depth is
  // a different number of millimetres at every distance from the camera —
  // that is what a projection matrix does — so a value tuned on a near wall
  // leaves acne on a far one. A metre is a metre anywhere.
  vec3 origin = WorldFromDepth(v_uv, surface.a) + normal * ssao_info.params.w;

  vec2 rot = Rotation(v_uv);
  float occluded = 0.0;

  for (int i = 0; i < 12; i++) {
    if (i >= samples) break;

    vec3 tap = KernelTap(i);
    // Rotated about the vertical axis of the kernel's own space, before it is
    // oriented to the surface: rotating afterwards would turn the hemisphere
    // off the normal and let taps fall behind the surface.
    vec3 spun =
        vec3(tap.x * rot.x - tap.y * rot.y, tap.x * rot.y + tap.y * rot.x, tap.z);

    // Flipped into the hemisphere the surface faces, rather than built from a
    // tangent frame. A frame needs a tangent, this pass has none, and any it
    // invented would rotate along a silhouette and shimmer.
    if (dot(spun, normal) < 0.0) spun = -spun;

    vec3 at = origin + spun * radius;

    vec4 clip = ssao_info.view_projection * vec4(at, 1.0);
    if (clip.w <= 0.0) continue;
    vec3 ndc = clip.xyz / clip.w;
    if (abs(ndc.x) > 1.0 || abs(ndc.y) > 1.0) continue;

    vec2 uv = UvFromNdc(ndc.xy);
    vec4 there = texture(surface_texture, uv);
    // The sky occludes nothing: a sample that lands on it is a sample looking
    // out of the scene, which is the opposite of being enclosed.
    if (there.a <= 0.0) continue;

    // Nearer to the camera than the point we sampled towards means something
    // stands between them. Compared in window depth, which is what the buffer
    // holds and what `ndc.z` already is — reconstructing both to world space
    // and measuring there would be the same test with two extra matrix
    // multiplies and a division.
    if (there.a >= ndc.z) continue;

    // The range check, and the reason a version without one draws haloes: a
    // wall four metres behind a railing is nearer to the camera than every
    // sample taken around the railing, and would occlude all of them. Distance
    // measured in the world, because "four metres behind" is a world fact and
    // the depth buffer's answer to it depends on where the camera is.
    vec3 seen = WorldFromDepth(uv, there.a);
    occluded +=
        smoothstep(0.0, 1.0, radius / max(distance(seen, origin), 1e-4));
  }

  // Raw, with no strength applied. The strength lives in the composite, and it
  // lives in exactly one place on purpose: applied here as well it would be
  // squared, and — more to the point — "off" has to mean a multiplier of
  // exactly one, which is a property of the composite's `mix` rather than of
  // any arithmetic done here.
  frag_color = vec4(clamp(1.0 - occluded / float(samples), 0.0, 1.0));
}
