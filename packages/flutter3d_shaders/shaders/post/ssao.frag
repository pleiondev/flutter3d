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
// lives in the alpha channel of the surface buffer — as metres along the view
// axis, which is not what a depth buffer holds and is deliberate; see
// `WriteSurfaceGeometry` in `lib/color.glsl`. Every screen-space effect in this
// renderer is built on that one decision, and this stage inherits it rather
// than working around it.
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
  /// z: one when `albedo_texture` holds the albedo buffer (`L5`); otherwise
  /// the strength's old slot, unused: the strength belongs to the composite, which is the pass that
  /// has to make "off" mean a multiplier of exactly one. It is left in place
  /// rather than removed so the block's layout does not depend on that staying
  /// true.
  vec4 params;

  /// x: 1/width, y: 1/height of *this* target, which is half the scene's.
  /// z: the method — nought the kernel below, one ground-truth horizon
  /// search, two the horizon search with indirect light (`L5`). w: the
  /// thickness the indirect method gives each sample, in metres.
  vec4 screen;

  /// xyz: where the eye is. w unused.
  ///
  /// Needed because the surface buffer holds a *depth along the view axis in
  /// metres* rather than a window depth — see `WriteSurfaceGeometry`. Turning
  /// one back into a point takes a ray and a plane rather than a matrix
  /// multiply, and this is where the ray starts.
  vec4 camera;

  /// xyz: the direction the camera looks, a unit vector in world space.
  /// w unused. The normal of the planes the stored depth measures against.
  vec4 forward;
}
ssao_info;

#include <lib/blue_noise.glsl>

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

/// Where the depth stored for [uv] is, in the world.
///
/// **A ray crossing a plane**, rather than a matrix multiply. The buffer stores
/// metres along the view axis rather than a window depth, so the inverse matrix
/// is used to find the pixel's ray — both ends of it — and the stored depth
/// picks the point on that ray lying [depth] metres in front of the eye. What
/// that buys is precision: a window depth in a half float cannot tell twenty
/// metres from twenty and a half, which is what used to draw bands across every
/// wall.
///
/// **Both ends, rather than one and the camera**, and that is what makes it
/// true of an orthographic camera as well. Its rays do not meet at the eye;
/// they are parallel, and a reconstruction that starts every ray at the camera
/// position puts an isometric scene's geometry somewhere it is not. Two
/// unprojections cost one extra matrix multiply and are right either way.
///
/// y undoes [UvFromNdc]: a point projected and then reconstructed has to come
/// back where it started.
///
/// [PixelRay] is the ray on its own: where it starts and which way it goes.
/// Reversed it is also the way to the eye, for either camera — see [EyeWard].
void PixelRay(vec2 uv, out vec3 origin, out vec3 along) {
  vec2 xy = vec2(uv.x * 2.0 - 1.0, 1.0 - uv.y * 2.0);
  vec4 nearH = ssao_info.inverse_view_projection * vec4(xy, 0.0, 1.0);
  vec4 farH = ssao_info.inverse_view_projection * vec4(xy, 1.0, 1.0);
  origin = nearH.xyz / nearH.w;
  along = normalize(farH.xyz / farH.w - origin);
}

vec3 WorldAtDepth(vec2 uv, float depth) {
  vec3 origin;
  vec3 along;
  PixelRay(uv, origin, along);
  vec3 axis = ssao_info.forward.xyz;
  return origin +
         along * ((depth - dot(origin - ssao_info.camera.xyz, axis)) /
                  dot(along, axis));
}

/// The way to the eye from what [uv] shows: the pixel's ray, reversed — the
/// zenith the horizon slices below are measured from.
///
/// **The ray rather than the camera position.** Under a perspective camera
/// the two agree, since every ray starts at the eye. An orthographic camera's
/// rays are parallel, so the samples along a screen line lie in the plane of
/// that line and the view axis; a zenith pointed at the camera position tilts
/// out of that plane towards the frame's edges, and the occlusion measured
/// against it drifted with the distance from the centre.
vec3 EyeWard(vec2 uv) {
  vec3 origin;
  vec3 along;
  PixelRay(uv, origin, along);
  return -along;
}

/// How deep [at] is, in the metres the buffer holds.
float DepthOf(vec3 at) {
  return dot(at - ssao_info.camera.xyz, ssao_info.forward.xyz);
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
///
/// **An angle from the blue noise while a temporal resolve runs** — `R3`:
/// a different one each frame, which the occlusion's own history averages,
/// so the pattern the composite's blur was sized for is not there to cancel.
vec2 Rotation(vec2 uv) {
  vec2 pixel = floor(uv / ssao_info.screen.xy);
  if (noise_info.noise.x > 0.5) {
    float angle = 6.2831853 * BlueNoise(pixel);
    return vec2(cos(angle), sin(angle));
  }
  bool oddX = mod(pixel.x, 2.0) >= 1.0;
  bool oddY = mod(pixel.y, 2.0) >= 1.0;
  if (oddX && oddY) return vec2(-0.7071, -0.7071);
  if (oddX) return vec2(0.7071, -0.7071);
  if (oddY) return vec2(-0.7071, 0.7071);
  return vec2(1.0, 0.0);
}

/// How many pixels of this target [radius] metres span at [point] — the
/// reach of the horizon searches below.
///
/// **In pixels, and stepped in pixels**, because a pixel is the one unit
/// the projection keeps square. A uv unit is the target's width one way and
/// its height the other, so a radius measured across the screen and stepped
/// as uv reached only height/width of it up the screen — a little over half
/// on a landscape frame, and nearly twice too far on a phone held upright —
/// and slices spread evenly in uv were not spread evenly in angle.
///
/// Measured across the view, along a horizontal line through [point]; the
/// world up is swapped for x when the eye looks nearly straight along it.
float PixelRadius(vec3 point, vec3 view, float radius) {
  vec3 across = normalize(
      cross(view, abs(view.y) < 0.99 ? vec3(0.0, 1.0, 0.0) : vec3(1.0, 0.0, 0.0)));
  vec4 here = ssao_info.view_projection * vec4(point, 1.0);
  vec4 there = ssao_info.view_projection * vec4(point + across * radius, 1.0);
  return length((UvFromNdc(there.xy / there.w) - UvFromNdc(here.xy / here.w)) /
                ssao_info.screen.xy);
}

/// Ground-truth ambient occlusion (Jimenez et al. 2016) — `L5`.
///
/// Two slices through the point, turned by the pixel's noise; along each,
/// the highest horizon on either side within the radius, as the cosine of
/// its angle from the eye; and the cosine-weighted visibility between the
/// two horizons integrated in closed form against the normal projected into
/// the slice. What the kernel above estimates by twelve taps into a
/// hemisphere this answers per slice exactly, which is why its corners are
/// the right darkness rather than a matter of tuning.
///
/// The steps are the sample count spread over the two sides of two slices,
/// and falloff towards the radius is a smooth fade of each horizon back to
/// the eye's own, so a wall just past the radius does not snap in.
float GtaoVisibility(vec2 uv, vec3 point, vec3 normal) {
  vec3 view = EyeWard(uv);
  float radius = max(ssao_info.params.x, 1e-4);
  int steps = clamp(int(ssao_info.params.y + 0.5) / 4, 1, 4);
  float pixelRadius = PixelRadius(point, view, radius);

  vec2 pixel = floor(uv / ssao_info.screen.xy);
  float noise = PixelNoise(pixel);
  float depth = textureLod(surface_texture, uv, 0.0).a;

  float visibility = 0.0;
  float slices = 0.0;
  for (int slice = 0; slice < 2; slice++) {
    float phi = (float(slice) + noise) * 1.5707963;
    // One pixel along the slice, in uv: the angle is an angle on the screen.
    vec2 direction = vec2(cos(phi), sin(phi)) * ssao_info.screen.xy;

    // The slice's direction in the world: the same screen step taken at this
    // point's depth, with the eye's component removed.
    vec3 along = WorldAtDepth(uv + direction, depth) - point;
    vec3 tangent = along - view * dot(along, view);
    float tangentLength = length(tangent);
    if (tangentLength < 1e-6) continue;
    tangent /= tangentLength;
    vec3 axis = normalize(cross(tangent, view));
    vec3 projected = normal - axis * dot(normal, axis);
    float projectedLength = length(projected);
    if (projectedLength < 1e-4) continue;
    // The normal's angle from the eye, kept within a quarter turn of it: a
    // stored normal turned away from the eye — an interpolated one at a
    // smooth mesh's silhouette — would otherwise put a horizon on the wrong
    // side of the zenith, and the arc below would take visibility away.
    float n = sign(dot(projected, tangent)) *
              acos(clamp(dot(projected / projectedLength, view), 0.0, 1.0));

    float horizons[2];
    for (int side = 0; side < 2; side++) {
      float s = side == 0 ? -1.0 : 1.0;
      float best = -1.0;
      for (int i = 0; i < 4; i++) {
        if (i >= steps) break;
        float t = (float(i) + 0.5 + 0.5 * noise) / float(steps);
        vec2 at = uv + s * direction * pixelRadius * t;
        if (at.x < 0.0 || at.x > 1.0 || at.y < 0.0 || at.y > 1.0) continue;
        float d = textureLod(surface_texture, at, 0.0).a;
        if (d <= 0.0) continue;
        vec3 toSample = WorldAtDepth(at, d) - point;
        float distance = length(toSample);
        if (distance < 1e-5) continue;
        float cosine = dot(toSample / distance, view);
        float fade = clamp(1.0 - (distance * distance) / (radius * radius), 0.0,
                           1.0);
        best = max(best, mix(-1.0, cosine, fade));
      }
      horizons[side] = s * acos(clamp(best, -1.0, 1.0));
    }
    // Both horizons within the quarter turns either side of the normal, bound
    // from above and below alike.
    float h1 = n + clamp(horizons[0] - n, -1.5707963, 1.5707963);
    float h2 = n + clamp(horizons[1] - n, -1.5707963, 1.5707963);
    visibility += projectedLength * 0.25 *
                  ((-cos(2.0 * h1 - n) + cos(n) + 2.0 * h1 * sin(n)) +
                   (-cos(2.0 * h2 - n) + cos(n) + 2.0 * h2 * sin(n)));
    slices += 1.0;
  }
  return slices > 0.0 ? clamp(visibility / slices, 0.0, 1.0) : 1.0;
}

/// The lit scene, for the light the indirect method bounces — `L5`. Bound
/// to the scene's colour on every draw; read only by that method.
uniform sampler2D scene_texture;

/// The albedo buffer — `L5`: the receiving surface's own colour. A stand-in
/// when the device has none, which `params.z` says: then the indirect method
/// takes a neutral grey and the horizon method no bounces.
uniform sampler2D albedo_texture;

vec3 SrgbToLinearAlbedo(vec3 srgb) {
  return mix(srgb / 12.92, pow((srgb + vec3(0.055)) / 1.055, vec3(2.4)),
             step(vec3(0.04045), srgb));
}

/// The sectors a run from [low] to [high] covers, each in nought to one
/// across the slice's half circle: sixteen of them, four to a vector, one
/// where the run takes in a sector's centre and nought where it does not.
///
/// Floats rather than the bits of a `uint`: the OpenGL ES target impellerc
/// compiles for has no unsigned integers, and aborts on the shifts.
void SectorRun(float low, float high, out vec4 m0, out vec4 m1, out vec4 m2,
               out vec4 m3) {
  const vec4 base = vec4(0.5, 1.5, 2.5, 3.5) / 16.0;
  m0 = step(vec4(low), base) * step(base, vec4(high));
  m1 = step(vec4(low), base + 0.25) * step(base + 0.25, vec4(high));
  m2 = step(vec4(low), base + 0.5) * step(base + 0.5, vec4(high));
  m3 = step(vec4(low), base + 0.75) * step(base + 0.75, vec4(high));
}

/// Visibility with the light the surroundings pass back — `L5`: the fit of
/// Jimenez et al. 2016 to many bounces between surfaces of this [albedo],
/// taken per channel and brought to one number by Rec. 709 luma, since the
/// composite multiplies by one. A dark room stays as dark as the horizon
/// says; a white one gives back much of what the crease took.
float MultiBounce(float visible, vec3 albedo) {
  vec3 a = 2.0404 * albedo - 0.3324;
  vec3 b = -4.7951 * albedo + 0.6417;
  vec3 c = 2.7552 * albedo + 0.6903;
  vec3 v = vec3(visible);
  vec3 bounced = max(v, ((v * a + b) * v + c) * v);
  return dot(bounced, vec3(0.2126, 0.7152, 0.0722));
}

float SectorCount(vec4 m0, vec4 m1, vec4 m2, vec4 m3) {
  return dot(m0 + m1 + m2 + m3, vec4(1.0));
}

/// Screen-space indirect light with a visibility bitmask (Therrien et al.
/// 2023) — `L5`. rgb: the light that bounces onto this point off what it
/// sees, times its own albedo; a: the share of the hemisphere left open.
///
/// The slices and steps of [GtaoVisibility], but each sample is a slab of
/// the given thickness rather than a height field: its front and back
/// angles cover a run of 16 sectors across the slice, and only sectors no
/// nearer sample covered yet let its light through. So a thin pole shades
/// what is behind it and lets the light past it on either side, where a
/// horizon would have hidden everything behind the pole.
vec4 SsilLight(vec2 uv, vec3 point, vec3 normal) {
  vec3 view = EyeWard(uv);
  float radius = max(ssao_info.params.x, 1e-4);
  float thickness = max(ssao_info.screen.w, 1e-3);
  int steps = clamp(int(ssao_info.params.y + 0.5) / 4, 1, 4);
  float pixelRadius = PixelRadius(point, view, radius);

  vec2 pixel = floor(uv / ssao_info.screen.xy);
  float noise = PixelNoise(pixel);
  float depth = textureLod(surface_texture, uv, 0.0).a;

  vec3 light = vec3(0.0);
  float open = 0.0;
  float slices = 0.0;
  for (int slice = 0; slice < 2; slice++) {
    float phi = (float(slice) + noise) * 1.5707963;
    vec2 direction = vec2(cos(phi), sin(phi)) * ssao_info.screen.xy;
    vec3 along = WorldAtDepth(uv + direction, depth) - point;
    vec3 tangent = along - view * dot(along, view);
    float tangentLength = length(tangent);
    if (tangentLength < 1e-6) continue;
    tangent /= tangentLength;
    vec3 axis = normalize(cross(tangent, view));
    vec3 projected = normal - axis * dot(normal, axis);
    float projectedLength = length(projected);
    if (projectedLength < 1e-4) continue;
    float n = sign(dot(projected, tangent)) *
              acos(clamp(dot(projected / projectedLength, view), 0.0, 1.0));

    vec4 c0 = vec4(0.0);
    vec4 c1 = vec4(0.0);
    vec4 c2 = vec4(0.0);
    vec4 c3 = vec4(0.0);
    for (int side = 0; side < 2; side++) {
      float s = side == 0 ? -1.0 : 1.0;
      for (int i = 0; i < 4; i++) {
        if (i >= steps) break;
        float t = (float(i) + 0.5 + 0.5 * noise) / float(steps);
        vec2 at = uv + s * direction * pixelRadius * t;
        if (at.x < 0.0 || at.x > 1.0 || at.y < 0.0 || at.y > 1.0) continue;
        vec4 sampled = textureLod(surface_texture, at, 0.0);
        if (sampled.a <= 0.0) continue;
        vec3 front = WorldAtDepth(at, sampled.a) - point;
        if (length(front) > radius) continue;
        vec3 toward = normalize(front);
        vec3 back = front - view * thickness;
        // Angles from the eye, signed by the side, over the half circle
        // centred on the normal: nought at one end, one at the other.
        float a = s * acos(clamp(dot(toward, view), -1.0, 1.0));
        float b = s * acos(clamp(dot(normalize(back), view), -1.0, 1.0));
        float lowAngle = (min(a, b) - n + 1.5707963) / 3.1415927;
        float highAngle = (max(a, b) - n + 1.5707963) / 3.1415927;
        vec4 m0;
        vec4 m1;
        vec4 m2;
        vec4 m3;
        SectorRun(lowAngle, highAngle, m0, m1, m2, m3);
        float fresh = SectorCount(m0 * (1.0 - c0), m1 * (1.0 - c1),
                                  m2 * (1.0 - c2), m3 * (1.0 - c3));
        vec3 radiance = textureLod(scene_texture, at, 0.0).rgb;
        // Both ends' cosines: the receiver's to the sample, and the sample's
        // back to the receiver. Without the second, the lit top of a table
        // bled onto the floor it faces away from.
        float cosine = max(dot(normal, toward), 0.0) *
                       max(dot(DecodeOctahedral(sampled.rg), -toward), 0.0);
        light += radiance * cosine * fresh / 16.0;
        c0 = max(c0, m0);
        c1 = max(c1, m1);
        c2 = max(c2, m2);
        c3 = max(c3, m3);
      }
    }
    open += 1.0 - SectorCount(c0, c1, c2, c3) / 16.0;
    slices += 1.0;
  }
  float count = max(slices, 1.0);
  vec3 albedo = ssao_info.params.z > 0.5
                     ? SrgbToLinearAlbedo(textureLod(albedo_texture, uv, 0.0).rgb)
                     : vec3(0.5);
  // With no slice to measure, open and unlit — as a select: impellerc's
  // SPIR-V to Metal step aborts on a phi of constants.
  return slices > 0.0 ? vec4(light / count * albedo, open / count)
                      : vec4(0.0, 0.0, 0.0, 1.0);
}

void main() {
  vec4 surface = textureLod(surface_texture, v_uv, 0.0);

  // Nothing was drawn here. The buffer is cleared to zero and a zero alpha is
  // the sky, not a surface sitting on the near plane — the same test
  // `reflections.frag` makes, and for the same reason.
  if (surface.a <= 0.0) {
    // Open sky: nothing occludes it, and with the indirect method nothing
    // bounces onto it either.
    frag_color = ssao_info.screen.z > 1.5 ? vec4(0.0, 0.0, 0.0, 1.0)
                                           : vec4(1.0);
    return;
  }

  vec3 normal = DecodeOctahedral(surface.rg);

  if (ssao_info.screen.z > 1.5) {
    frag_color = SsilLight(v_uv, WorldAtDepth(v_uv, surface.a), normal);
    return;
  }
  if (ssao_info.screen.z > 0.5) {
    float visible =
        GtaoVisibility(v_uv, WorldAtDepth(v_uv, surface.a), normal);
    // With the albedo buffer, the bounces too; without it, the horizon alone.
    float shaded = ssao_info.params.z > 0.5
                       ? MultiBounce(visible, SrgbToLinearAlbedo(
                                                  textureLod(albedo_texture, v_uv, 0.0).rgb))
                       : visible;
    frag_color = vec4(shaded);
    return;
  }

  float radius = max(ssao_info.params.x, 1e-4);
  int samples = clamp(int(ssao_info.params.y + 0.5), 1, 12);

  // Lifted off the surface along its own normal, and this is where the bias
  // goes rather than into the depth comparison below. A bias in window depth is
  // a different number of millimetres at every distance from the camera —
  // that is what a projection matrix does — so a value tuned on a near wall
  // leaves acne on a far one. A metre is a metre anywhere.
  vec3 origin =
      WorldAtDepth(v_uv, surface.a) + normal * ssao_info.params.w;

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
    // **`textureLod` at level zero, for the same reason the march in
    // `reflections.frag` uses it.** Two `continue`s stand above this line, so
    // the invocations of a quad are not all here, and a WGSL backend refuses to
    // derive a mip level where they are not. The surface buffer is a
    // full-screen render target with one level, and this pass binds it
    // unfiltered besides, so level zero is the only level there has ever been
    // to read.
    vec4 there = textureLod(surface_texture, uv, 0.0);
    // The sky occludes nothing: a sample that lands on it is a sample looking
    // out of the scene, which is the opposite of being enclosed.
    if (there.a <= 0.0) continue;

    // Nearer to the eye than the point we sampled towards means something
    // stands between them. **Compared in metres**, which is what the buffer
    // holds: the same test in window depth is a comparison whose resolution
    // collapses with range, and at twenty metres a half float cannot separate
    // two surfaces half a metre apart. `reflections.frag` reached this
    // conclusion first and says so at more length.
    if (there.a >= DepthOf(at)) continue;

    // The range check, and the reason a version without one draws haloes: a
    // wall four metres behind a railing is nearer to the camera than every
    // sample taken around the railing, and would occlude all of them. Distance
    // measured in the world, because "four metres behind" is a world fact and
    // the depth buffer's answer to it depends on where the camera is.
    vec3 seen = WorldAtDepth(uv, there.a);
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
