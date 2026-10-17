#version 460 core

// Projected box decals — `P3`: a picture laid onto whatever geometry stands
// inside a box, as if it were part of that geometry's material.
//
// **The point under a pixel comes from the surface buffer, because it can
// come from nowhere else.** flutter_gpu cannot sample a depth attachment, so a
// decal cannot be the usual box drawn against the depth it would read. The
// scene pass already wrote a world normal and a depth along the view axis into
// its second attachment, and `WorldAt` turns the two back into a point, as
// the reflections and the occlusion do.
//
// **A material, not a sticker over the lit picture.** The light a surface was
// lit by is recovered from what the scene pass left: the lit colour over the
// albedo buffer's colour is the light that reached the point, shadows,
// probes and the sky's share included. The decal's colour replaces the
// albedo under that same light, so a decal in shadow is in shadow and a decal
// under a red lamp is red. It is what keeps this a fullscreen pass of two
// draws rather than a second lighting model with every light and map bound.
//
// **Two draws with one stage, because a pixel needs two terms.** The new
// colour is the old one times a factor (the albedo swap) plus a term (an
// unlit stack and an emitted light), and one blend cannot multiply and add.
// The first draw writes the factor under a multiplying blend, the second the
// term under an adding one; `params.w` says which.
//
// What the albedo cannot say is stated rather than guessed: a surface that
// wrote no albedo (unlit, or black) has no light to borrow, and there the
// decal is laid over the picture at its own colour. The surface's emission,
// its fog and its specular highlight are scaled with the light, which is
// close for a matte wall and wrong for a mirror.
precision highp float;

in vec2 v_uv;

out vec4 frag_color;

uniform sampler2D surface_texture;
uniform sampler2D albedo_texture;

/// Four pictures a draw may read, each a slot a decal names. A slot nobody
/// names is bound to a one-texel white, for the reason `lib/pbr.glsl` gives:
/// a declared sampler nobody binds is a crash on Metal.
uniform sampler2D decal_texture_0;
uniform sampler2D decal_texture_1;
uniform sampler2D decal_texture_2;
uniform sampler2D decal_texture_3;

/// Decals per draw. Must match `_DecalBatch.maxDecals` in
/// `renderer_decal_pass.dart`; a frame with more draws again over what the
/// first draw left.
#define kMaxDecals 16

/// How little albedo still names a light. Below it the decal stops borrowing
/// the surface's light and is laid on at its own colour, through a ramp
/// rather than a step so a dark texture does not show a seam where it
/// crosses.
#define kAlbedoFloor 0.08

uniform DecalInfo {
  /// Screen to world, carrying the framebuffer origin — see `UvFromNdc` in
  /// `post/reflections.frag`.
  mat4 inverse_view_projection;
  /// xyz: the camera's position. w: unused.
  vec4 camera;
  /// xyz: the direction the camera looks; with [camera] it names the planes
  /// the surface buffer's depths are measured against. w: unused.
  vec4 forward;
  /// x: how many decals. y, z: one texel of the target. w: which term this
  /// draw writes, nought the factor and one the term.
  vec4 params;
  /// The view this draw paints, in the target's texture coordinates: xy
  /// where it starts, zw how much of the target it spans. The surface buffer
  /// holds every view side by side and the matrix above is this one's.
  vec4 view;
  /// Per slot: xy its size in texels, zw unused.
  vec4 slots[4];
  /// The rows of each decal's world-to-box matrix: the box is the unit cube
  /// about its origin, and its picture faces up its y axis.
  vec4 axis_x[kMaxDecals];
  vec4 axis_y[kMaxDecals];
  vec4 axis_z[kMaxDecals];
  /// The part of its slot's picture a decal shows: xy where it starts in
  /// texture coordinates, zw how far it reaches.
  vec4 region[kMaxDecals];
  /// rgb: the tint, linear. a: the opacity.
  vec4 color[kMaxDecals];
  /// x: the slot, negative for none. y: the cosine of the angle from the
  /// box's up at which the decal is gone, z: the cosine width over which it
  /// fades in from there. w: the share of the box's half height, from its
  /// top and bottom faces, over which it fades out.
  vec4 fade[kMaxDecals];
  /// rgb: light the painted colour emits, as a multiple of it. w: unused.
  vec4 emissive[kMaxDecals];
}
decal_info;

vec3 DecodeOctahedral(vec2 e) {
  e = e * 2.0 - 1.0;
  vec3 n = vec3(e.xy, 1.0 - abs(e.x) - abs(e.y));
  float t = max(-n.z, 0.0);
  n.x += n.x >= 0.0 ? -t : t;
  n.y += n.y >= 0.0 ? -t : t;
  return normalize(n);
}

vec3 SrgbToLinear(vec3 srgb) {
  return mix(srgb / 12.92, pow((srgb + vec3(0.055)) / 1.055, vec3(2.4)),
             step(vec3(0.04045), srgb));
}

/// The world point at [uv], [depth] metres along the view axis: the ray
/// through the pixel, crossing the plane the depth names. See `WorldAt` in
/// `post/reflections.frag`, which this is, but for [uv] being the target's
/// rather than the view's.
vec3 WorldAt(vec2 uv, float depth) {
  vec2 inView = (uv - decal_info.view.xy) / decal_info.view.zw;
  vec2 xy = vec2(inView.x * 2.0 - 1.0, 1.0 - inView.y * 2.0);
  vec4 nearH = decal_info.inverse_view_projection * vec4(xy, 0.0, 1.0);
  vec4 farH = decal_info.inverse_view_projection * vec4(xy, 1.0, 1.0);
  vec3 origin = nearH.xyz / nearH.w;
  vec3 along = normalize(farH.xyz / farH.w - origin);
  vec3 axis = decal_info.forward.xyz;
  return origin +
         along * ((depth - dot(origin - decal_info.camera.xyz, axis)) /
                  dot(along, axis));
}

/// How far the world moves across one texel along [step], taken toward the
/// neighbour nearer in depth.
///
/// **Read from the buffer rather than from `dFdx`**, so the software backend,
/// which has no quads to difference, picks the same level. The nearer
/// neighbour, because the far one across a silhouette belongs to another
/// surface, and its distance would choose the blurriest level for a pixel
/// that is in the middle of a decal.
vec3 WorldStep(vec2 step, float depth, vec3 at) {
  vec4 ahead = textureLod(surface_texture, v_uv + step, 0.0);
  vec4 behind = textureLod(surface_texture, v_uv - step, 0.0);
  float aheadGap = ahead.a > 0.0 ? abs(ahead.a - depth) : 1e30;
  float behindGap = behind.a > 0.0 ? abs(behind.a - depth) : 1e30;
  vec3 forward = WorldAt(v_uv + step, ahead.a) - at;
  vec3 backward = at - WorldAt(v_uv - step, behind.a);
  vec3 chosen = aheadGap <= behindGap ? forward : backward;
  // Nothing drawn on either side: no footprint, which is the base level.
  return min(aheadGap, behindGap) < 1e29 ? chosen : vec3(0.0);
}

vec4 SampleSlot(float slot, vec2 uv, float lod) {
  // A chain of selects rather than an index: GLSL ES 3.00 cannot index an
  // array of samplers with anything but a constant.
  vec4 picture = vec4(1.0);
  if (slot > 2.5) {
    picture = textureLod(decal_texture_3, uv, lod);
  } else if (slot > 1.5) {
    picture = textureLod(decal_texture_2, uv, lod);
  } else if (slot > 0.5) {
    picture = textureLod(decal_texture_1, uv, lod);
  } else if (slot > -0.5) {
    picture = textureLod(decal_texture_0, uv, lod);
  }
  return picture;
}

void main() {
  bool factor = decal_info.params.w < 0.5;
  vec4 surface = textureLod(surface_texture, v_uv, 0.0);

  // What leaves the pixel as it was, for each draw: a factor of one, a term of
  // nought. Alpha is not touched by either blend.
  vec3 keepFactor = vec3(1.0);
  vec3 keepTerm = vec3(0.0);
  if (surface.a <= 0.0) {
    frag_color = vec4(factor ? keepFactor : keepTerm, 1.0);
    return;
  }

  float depth = surface.a;
  vec3 at = WorldAt(v_uv, depth);
  vec3 normal = DecodeOctahedral(surface.rg);
  vec3 dx = WorldStep(vec2(decal_info.params.y, 0.0), depth, at);
  vec3 dy = WorldStep(vec2(0.0, decal_info.params.z), depth, at);
  vec3 albedo =
      SrgbToLinear(textureLod(albedo_texture, v_uv, 0.0).rgb);

  // Three stacks, decal over decal in order: the albedo the decals leave, the
  // share of the picture an unlit stack leaves, and that stack's colour —
  // premultiplied, as an over composite keeps it — and the emitted light.
  vec3 painted = albedo;
  float kept = 1.0;
  vec3 laid = vec3(0.0);
  vec3 emitted = vec3(0.0);
  int count = int(decal_info.params.x + 0.5);
  for (int i = 0; i < kMaxDecals; i++) {
    if (i >= count) break;
    vec4 rowX = decal_info.axis_x[i];
    vec4 rowY = decal_info.axis_y[i];
    vec4 rowZ = decal_info.axis_z[i];
    vec3 local = vec3(dot(rowX.xyz, at) + rowX.w, dot(rowY.xyz, at) + rowY.w,
                      dot(rowZ.xyz, at) + rowZ.w);
    if (any(greaterThan(abs(local), vec3(0.5)))) continue;

    vec4 fade = decal_info.fade[i];
    // The box's up in the world is the gradient of its y, which is the row
    // itself; normalised, it stays the up under a box scaled unevenly.
    float facing = dot(normal, normalize(rowY.xyz));
    float byAngle = clamp((facing - fade.y) / max(fade.z, 1e-4), 0.0, 1.0);
    float byDepth = fade.w > 0.0
        ? clamp((0.5 - abs(local.y)) / (fade.w * 0.5), 0.0, 1.0)
        : 1.0;

    // Seen from above, along the box's down, x runs right and z runs down
    // the picture: the picture is not mirrored on the face it is stamped on.
    vec4 region = decal_info.region[i];
    vec2 uv = region.xy + (local.xz + 0.5) * region.zw;

    // The level from the footprint, as the software backend's sampler
    // chooses one: the larger axis, in texels, over one pixel.
    float slot = fade.x;
    vec2 size = decal_info.slots[int(clamp(slot, 0.0, 3.0))].xy;
    vec2 alongX = vec2(dot(rowX.xyz, dx), dot(rowZ.xyz, dx)) * region.zw;
    vec2 alongY = vec2(dot(rowX.xyz, dy), dot(rowZ.xyz, dy)) * region.zw;
    float footprint = max(max(abs(alongX.x), abs(alongY.x)) * size.x,
                          max(abs(alongX.y), abs(alongY.y)) * size.y);
    float lod = footprint > 1.0 ? log2(footprint) : 0.0;

    vec4 picture = SampleSlot(slot, uv, lod);
    vec4 tint = decal_info.color[i];
    vec3 colour = SrgbToLinear(picture.rgb) * tint.rgb;
    float alpha = clamp(picture.a * tint.a * byAngle * byDepth, 0.0, 1.0);

    painted = mix(painted, colour, alpha);
    kept *= 1.0 - alpha;
    laid = mix(laid, colour, alpha);
    emitted = mix(emitted, colour * decal_info.emissive[i].rgb, alpha);
  }

  // How far the albedo names the light: one at the floor and over it.
  float named = clamp(max(albedo.r, max(albedo.g, albedo.b)) / kAlbedoFloor,
                      0.0, 1.0);
  // The change of albedo under the light it was lit by, as a factor: the new
  // albedo over the old where the old is over the floor, and exactly one
  // where no decal reached, whatever the albedo. Written as one plus the
  // change rather than as the ratio, because under the floor the ratio is not
  // one for an untouched pixel and the ramp below would darken every dark
  // surface in the frame.
  vec3 swap = vec3(1.0) + (painted - albedo) / max(albedo, vec3(kAlbedoFloor));
  vec3 multiply = swap * named + vec3(kept * (1.0 - named));
  vec3 add = laid * (1.0 - named) + emitted;
  frag_color = vec4(factor ? multiply : add, 1.0);
}
