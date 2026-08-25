// Shared material and lighting interface for the lighting models.
//
// flutter_gpu compiles shaders ahead of time into a bundle: there is no runtime
// compilation, so a node-graph material system assembled at run time is
// impossible. Each lighting model is therefore
// its own pre-built fragment shader, and this header is what keeps them
// interchangeable — one identical uniform block, so the Dart binding code never
// needs to know which model is active.
//
// Keep every declaration below byte-identical across models. A member a model
// does not read may be optimized out of the reflected block, which is why the
// Dart side skips absent members instead of failing.
//
// Only include this from a shader that actually reads FragInfo. Declaring the
// block without using it leaves it visible to reflection while the compiled
// shader binds no buffer for it, and binding that phantom block segfaults
// inside Metal. Shaders needing only colour helpers include lib/color.glsl.

#ifndef SURFACE_GLSL_
#define SURFACE_GLSL_

#include <lib/color.glsl>

/// Lights per draw. Must match LightBuffer.maxLights on the Dart side.
///
/// A fixed array with a runtime count, not a shader permutation per light
/// count: turning a light on has to be free, because there is no runtime
/// compilation to fall back on. Verified against the SDK — Impeller keeps
/// `vec4 x[8]` in the compiled Metal struct and reflects the array's base
/// offset, with the std140 stride of 16 bytes.
#define kMaxLights 8

uniform FragInfo {
  /// xyz: world position (point and spot). w: type, 0 directional 1 point 2 spot.
  vec4 light_position[kMaxLights];

  /// rgb: linear colour. w: intensity.
  vec4 light_color[kMaxLights];

  /// xyz: the direction the light points, its local -Z. w: range, 0 unbounded.
  vec4 light_direction[kMaxLights];

  /// x: cos(inner cone angle). y: cos(outer cone angle).
  vec4 light_cone[kMaxLights];

  /// rgb: albedo tint applied on top of the texture. w: opacity.
  vec4 base_color;

  /// rgb: emissive factor, already linear. w unused.
  vec4 emissive;

  /// xyz: camera position in world space, needed for every specular term.
  vec4 camera_position;

  /// x: metallic, y: roughness, z: ambient strength, w: specular strength.
  vec4 material;

  /// x: alpha cutoff (negative when the material is not masked), y: normal
  /// scale, z: occlusion strength, w: emissive strength.
  vec4 material2;

  /// x: exposure, y: active light count, z: index of the shadow-casting light.
  /// w is reserved so adding a frame-wide parameter does not change the offsets
  /// of anything already here.
  vec4 frame_params;

  /// x: one texel of the shadow map, y: depth bias, z: normal offset,
  /// w: strength, zero when shadows are off.
  vec4 shadow_params;

  /// World space to the shadow camera's clip space. The first cascade.
  mat4 shadow_matrix;

  /// The second and third cascades. Copies of the first when there is one, so
  /// this block's layout never depends on how many there are.
  mat4 shadow_matrix_far;
  mat4 shadow_matrix_farthest;

  /// x, y: where cascades 0 and 1 end, in metres from the camera. z: how many
  /// cascades there are, 1 to 3. w: one texel of a tile, vertically —
  /// shadow_params.x is one texel of the whole atlas, and with more than one
  /// cascade those differ.
  vec4 shadow_cascades;

  /// rgb: what a surface facing straight up receives from the environment.
  /// w unused.
  ///
  /// Appended after everything else on purpose: std140 lays a block out in
  /// declaration order, so adding here leaves every offset above unchanged and
  /// the three backends do not have to agree about anything they did not
  /// already agree about.
  vec4 ambient_sky;

  /// rgb: what a surface facing straight down receives — bounce off the ground
  /// rather than the ground itself. w unused.
  ///
  /// Two colours rather than one is the whole of what makes ambient look like
  /// light instead of like a lifted black level. Outdoors the sky is blue and
  /// bright and the ground is warm and dim, and a flat grey for both leaves
  /// every underside as pale as every upward face — which reads as the model
  /// being flat, and gets blamed on the normals.
  vec4 ambient_ground;
}
frag_info;

uniform sampler2D base_color_texture;

/// Everything about the surface that does not depend on which light is being
/// evaluated, resolved once per fragment.
struct Surface {
  vec3 albedo;      // linear, already tinted
  float alpha;      // opacity after texture, tint and vertex colour
  vec3 n;           // unit normal, perturbed by the normal map when there is one
  vec3 v;           // unit direction to the camera
  float n_dot_v;
  float metallic;
  float roughness;  // perceptual
  float occlusion;  // 1 means unoccluded
  vec3 emissive;    // linear, added after shading
  vec3 ambient;     // hemispheric, already scaled by the scene's strength
  float exposure;
};

/// One light's contribution geometry, recomputed per light per fragment.
struct LightSample {
  vec3 l;           // unit direction to the light
  vec3 h;           // unit half vector
  vec3 radiance;    // colour * intensity * attenuation
  float n_dot_l;
  float n_dot_h;
  float v_dot_h;
};

Surface ReadSurface() {
  Surface s;

  vec4 texel = texture(base_color_texture, v_texcoord);
  // Vertex colour is authored linear per the glTF spec, unlike the base colour
  // texture and the tint, which are sRGB.
  s.albedo = SrgbToLinear(texel.rgb) *
             SrgbToLinear(frag_info.base_color.rgb) *
             v_color.rgb;
  s.alpha = texel.a * frag_info.base_color.a * v_color.a;

  // Alpha masking, glTF's third alpha mode. A negative cutoff means the
  // material is opaque or blended, and discard would then be wrong rather than
  // merely unnecessary. Doing it before anything else is deliberate: a
  // discarded fragment should not pay for the lighting loop.
  float cutoff = frag_info.material2.x;
  if (cutoff >= 0.0 && s.alpha < cutoff) discard;

  s.n = normalize(v_normal);
  s.v = normalize(frag_info.camera_position.xyz - v_world_position);
  // Clamped away from zero: a grazing view direction otherwise divides by zero
  // in the specular visibility term.
  s.n_dot_v = max(dot(s.n, s.v), 1e-4);

  s.metallic = clamp(frag_info.material.x, 0.0, 1.0);
  s.roughness = clamp(frag_info.material.y, 0.02, 1.0);
  // Hemispheric: the sky above, the ground below, blended by which way this
  // surface faces. `material.z` stays the overall strength, so the two are
  // separable — a scene dims its ambient without changing its colour, which is
  // what the one control used to do on its own.
  //
  // The blend runs on the geometric normal deliberately, before
  // `ApplyMaterialMaps` perturbs it. A normal map describes millimetres of
  // surface relief, and ambient of this kind describes which half of the world
  // a face can see; letting bump detail swing it makes a brick wall's mortar
  // lines pick up sky and reads as noise.
  s.ambient = mix(frag_info.ambient_ground.rgb, frag_info.ambient_sky.rgb,
                  s.n.y * 0.5 + 0.5) *
              frag_info.material.z;
  s.exposure = max(frag_info.frame_params.x, 0.0);

  // Neutral until ApplyMaterialMaps says otherwise, so a model that samples no
  // maps still has a complete surface.
  s.occlusion = 1.0;
  s.emissive = vec3(0.0);

  return s;
}

int LightCount() {
  return clamp(int(frag_info.frame_params.y + 0.5), 0, kMaxLights);
}

/// Distance attenuation for a punctual light, following the glTF spec.
///
/// Inverse square with an optional range window. The window is what stops a
/// lamp with a declared range from contributing a faint haze across the whole
/// scene, which matters far more once there are eight of them.
float PunctualAttenuation(float distance, float range) {
  float attenuation = 1.0 / max(distance * distance, 1e-4);
  if (range > 0.0) {
    float ratio = distance / range;
    float window = clamp(1.0 - ratio * ratio * ratio * ratio, 0.0, 1.0);
    attenuation *= window * window;
  }
  return attenuation;
}

/// Resolves light [index] against the surface.
///
/// Returns `n_dot_l == 0` for anything that contributes nothing — behind the
/// surface, out of range, outside the spot cone — so a model can skip it with
/// one test instead of repeating the classification.
LightSample SampleLight(int index, Surface s) {
  LightSample light;

  vec4 position = frag_info.light_position[index];
  vec4 color = frag_info.light_color[index];
  vec4 direction = frag_info.light_direction[index];
  vec4 cone = frag_info.light_cone[index];

  float type = position.w;
  vec3 aim = normalize(direction.xyz);
  float attenuation = 1.0;

  if (type < 0.5) {
    // Directional: no position, no falloff. The direction to the light is the
    // reverse of the direction it points.
    light.l = -aim;
  } else {
    vec3 toLight = position.xyz - v_world_position;
    float distance = length(toLight);
    // A light exactly on the surface has no direction; treat it as contributing
    // nothing rather than producing a NaN that spreads through the frame.
    if (distance < 1e-6) {
      light.l = s.n;
      light.h = s.n;
      light.radiance = vec3(0.0);
      light.n_dot_l = 0.0;
      light.n_dot_h = 0.0;
      light.v_dot_h = 0.0;
      return light;
    }
    light.l = toLight / distance;
    attenuation = PunctualAttenuation(distance, direction.w);

    if (type > 1.5) {
      // Spot: a smooth ramp between the two cone cosines. The Dart side already
      // guarantees the denominator is non-zero.
      float cosAngle = dot(aim, -light.l);
      attenuation *= clamp(
          (cosAngle - cone.y) / (cone.x - cone.y), 0.0, 1.0);
    }
  }

  light.h = normalize(light.l + s.v);
  light.n_dot_l = max(dot(s.n, light.l), 0.0);
  light.n_dot_h = max(dot(s.n, light.h), 0.0);
  light.v_dot_h = max(dot(s.v, light.h), 0.0);
  light.radiance = color.rgb * color.w * attenuation;

  return light;
}

/// How much of light [index] reaches this fragment, defined by each fragment
/// shader.
///
/// A prototype rather than a call into shadow.glsl, because the models that
/// sample no shadow map must not declare its sampler — the compiler would drop
/// the slot and leave the engine binding one that is not there. A lit model
/// returns `ShadowFactor(...)`; an unlit one returns 1.
float LightVisibility(Surface s, LightSample light, int index);

/// A model's per-light term, defined by each fragment shader.
///
/// A prototype here and the definition in the model is what lets the loop below
/// be written once. The alternative — repeating the loop in every model — is
/// six copies of the same three lines, and the place a light would go missing.
vec3 ShadeLight(Surface s, LightSample light);

/// Sums every active light's contribution.
///
/// The loop bound is the compile-time maximum with a runtime break, because GLSL
/// wants a constant trip count and the hardware wants the early exit.
// **The point-shadow half of this header, behind a guard.**
//
// A model that never shadows must not *declare* any of this, and the reason is
// the one `unlit.frag` already gives about the shadow sampler — with one
// backend's failure added to the other's. On Impeller the compiler drops what
// nothing reads, and the engine binding a slot that is no longer there is a
// native crash. On WebGL2 nothing is dropped: an active uniform block with no
// buffer under it makes every draw `INVALID_OPERATION`, discarded with nothing
// logged.
//
// That is what `lighting-unlit` was on this backend. Unlit's own metadata says
// `usesPointShadow` is false, so the engine correctly bound no `PointShadow`
// block — and the translated shader declared one anyway, so the sphere was
// never drawn and the frame came back the clear colour.
#ifndef F3D_NO_POINT_SHADOW

/// The cube atlas: three tiles across, two down, each a ninety-degree view
/// from a point light, each storing radial distance normalised by range.
uniform sampler2D point_shadow_texture;

/// The same atlas for the things that never move, rendered once at load.
///
/// Two maps rather than one because a dungeon's walls can be baked and a
/// spinning pickup cannot, and there is no way to draw into part of a texture
/// without redrawing the rest of it. Sampling both and keeping the nearer
/// occluder costs one extra read and saves six views of the level every frame.
uniform sampler2D point_shadow_static_texture;

/// How many lights may have a row of the atlas. Six tiles across each.
const int kShadowSlots = 4;

uniform PointShadow {
  /// The same view-projections the atlas was rendered with, six per slot.
  ///
  /// Passed rather than reconstructed. Deriving cube face coordinates here
  /// would be a second implementation of a decision the renderer already made,
  /// and the two would disagree about handedness or up vectors on some face
  /// and nowhere else — which shows as one face of every shadow being wrong.
  mat4 faces[6 * kShadowSlots];

  /// Per slot. xyz: the light's world position. w: its range.
  vec4 lights[kShadowSlots];

  /// Per light, in the order the lighting knows them.
  ///
  /// x: the atlas row it owns, or negative when it has none — a fifth torch in
  /// a room lands there. z: the tangent of half the frustum's opening angle,
  /// which is what converts a world width into a fraction of a tile. y and w
  /// are unwritten.
  ///
  /// **z is exactly one for a point light**, because a cube face is a ninety
  /// degree frustum and `tan(45°) == 1`. That is not a convention chosen to be
  /// tidy: it is what lets a narrower frustum share this whole path, since
  /// multiplying by one in IEEE 754 changes no bit of the result. Whatever else
  /// a spot light will need, it does not need a second copy of the filter.
  vec4 slots[kMaxLights];

  /// x: half a texel, in tile-local uv. y: distance bias in metres.
  /// z: strength. w: normal offset in metres.
  vec4 params;

  /// x: smallest kernel radius in tile-local uv, and the fixed radius used
  /// when contact hardening is off. y: the light's own radius in metres; zero
  /// turns contact hardening off. z: largest kernel radius in tile-local uv.
  /// w: non-zero paints the penumbra estimate into the surface buffer instead
  /// of shading with it.
  vec4 params2;

  /// x: non-zero when this backend stores the atlas bottom-up.
  ///
  /// **Appended after everything else on purpose**, the same way FragInfo's
  /// ambient pair was: std140 lays a block out in declaration order, so adding
  /// here leaves every offset above unchanged and the three backends do not
  /// have to agree about anything they already agreed about. y, z and w are
  /// unwritten.
  vec4 params3;
}
point_shadow;

/// Eight points on a Poisson disk, the same set flutter_scene filters its
/// cascades with.
///
/// A disk rather than a grid because a grid of taps on a straight shadow edge
/// lands every sample on the same side at once, and the edge steps between
/// kernel widths instead of sliding. Eight rather than sixteen because every
/// tap here reads **two** atlases — the static walls and the movers — so the
/// cost is doubled before it is counted.
vec2 PointShadowDiskTap(int i) {
  if (i == 0) return vec2(-0.94201624, -0.39906216);
  if (i == 1) return vec2(0.94558609, -0.76890725);
  if (i == 2) return vec2(-0.09418410, -0.92938870);
  if (i == 3) return vec2(0.34495938, 0.29387760);
  if (i == 4) return vec2(-0.91588581, 0.45771432);
  if (i == 5) return vec2(-0.81544232, -0.87912464);
  if (i == 6) return vec2(-0.38277543, 0.27676845);
  return vec2(0.97484398, 0.75648379);
}

/// One comparison against the atlas, at [uv] offset within the tile.
///
/// The clamp is applied **after** the offset, not before, and that is the whole
/// reason a kernel can be widened here without touching anything else: each tap
/// is held inside its own tile individually. Clamping the centre and then
/// offsetting would let the outer taps walk straight out of the tile and read a
/// distance measured from a different face, or a different light.
float PointShadowDistance(vec2 uv, vec2 offset, vec2 tile, float range) {
  float inset = point_shadow.params.x;
  vec2 local = clamp(uv + offset, inset, 1.0 - inset);
  vec2 atlas = (local + tile) * vec2(1.0 / 6.0, 1.0 / float(kShadowSlots));
  // **The whole atlas, turned over, where row zero of a render target is at the
  // bottom.** Both halves of the address are wrong there and this is the one
  // place that fixes both: the tile the light owns — a light in slot zero is
  // drawn into the row the shader would call three, because the viewport
  // rectangle is flipped to land it — and the picture inside that tile, which
  // was drawn through a projection built for the other origin.
  //
  // Every check of this atlas missed it for the same reason: the debug view
  // composites the texture through a full-screen pass, which turns it over
  // again and puts the row back. The atlas compared equal on both backends
  // across six scenes while the lit pass, which samples it directly and has no
  // such pass to cancel, read a row that had never been drawn into and found
  // nothing in the way of anything.
  if (point_shadow.params3.x > 0.5) atlas.y = 1.0 - atlas.y;
  // Whichever is nearer occludes: a wall in front of a monster shadows, and so
  // does a monster in front of a wall.
  return min(texture(point_shadow_texture, atlas).r,
             texture(point_shadow_static_texture, atlas).r) * range;
}

float PointShadowTap(vec2 uv, vec2 offset, vec2 tile, float range,
                     float receiver) {
  float stored = PointShadowDistance(uv, offset, tile, range);
  // Nothing was drawn in that direction by either, so nothing is in the way.
  if (stored >= range * 0.999) return 1.0;
  return receiver > stored ? 0.0 : 1.0;
}

/// The disk point for tap [i], rotated by [ca]/[sa] and scaled to [radius].
vec2 PointShadowOffset(int i, float ca, float sa, float radius) {
  vec2 p = PointShadowDiskTap(i);
  return vec2(p.x * ca - p.y * sa, p.x * sa + p.y * ca) * radius;
}

/// How wide the penumbra should be here, in tile-local uv.
///
/// Contact hardening, and the reason a fixed kernel looks wrong: a shadow is
/// sharp where its caster touches the floor and soft a metre away, and one
/// radius for both makes the contact mushy or the distant edge hard.
///
/// The similar-triangles estimate is the standard one — a light of radius `L`
/// with a blocker at `b` and a receiver at `r` throws a penumbra `L * (r - b) /
/// b` wide at the receiver. Converting that to tile uv is exact rather than
/// tuned, because a face is a ninety degree frustum: at distance `r` from the
/// light the face spans `2 * r` in world units across the full `0..1` of uv,
/// so a world width `w` is `w / (2 * r)` of a tile.
///
/// The blocker search runs at the **widest** penumbra allowed, since a blocker
/// outside that circle cannot widen the result anyway, and searching narrower
/// would miss the very blockers that make an edge soft.
///
/// [tanHalf] is where the ninety degrees stop being assumed. The span above is
/// `2 * r` only for a right-angled frustum; in general it is `2 * r * tan(θ/2)`,
/// and for a cube face that factor is one. A narrower frustum covers less world
/// per tile, so the same world width is a *larger* fraction of it — which is
/// why this divides rather than multiplies, and why getting it upside down
/// would make a tight cone's shadows harden instead of soften.
float PointShadowPenumbra(vec2 uv, vec2 tile, float range, float receiver,
                          float ca, float sa, float tanHalf,
                          out float blockerOut) {
  blockerOut = -1.0;
  float lightRadius = point_shadow.params2.y;
  float minRadius = point_shadow.params2.x;
  float maxRadius = point_shadow.params2.z;
  if (lightRadius <= 0.0) {
    // **The debug channel is filled even though the search is skipped**, and
    // leaving it unfilled cost a session. `blockerOut` starts at −1 to mean
    // "nothing was measured"; the debug encoding clamps it into a colour, where
    // −1 becomes zero — the same green as a blocker touching the surface, which
    // reads as the most alarming answer available. A whole theory was built on
    // that zero, and the search it described had never run.
    //
    // The centre tap is what the filter below would use anyway, so this reports
    // a distance the atlas really returned rather than a sentinel.
    blockerOut = PointShadowDistance(uv, vec2(0.0), tile, range);
    return minRadius;
  }


  float sum = 0.0;
  float count = 0.0;
  for (int i = 0; i < 8; i++) {
    float stored =
        PointShadowDistance(uv, PointShadowOffset(i, ca, sa, maxRadius), tile,
                            range);
    if (stored >= range * 0.999) continue;
    if (stored >= receiver) continue;
    sum += stored;
    count += 1.0;
  }
  // Nothing in front of this fragment anywhere in the search: fully lit, and
  // the caller can skip the filter entirely.
  if (count < 0.5) return -1.0;

  float blocker = max(sum / count, 1e-4);
  blockerOut = blocker;
  float world = lightRadius * max(receiver - blocker, 0.0) / blocker;
  return clamp(world / (2.0 * receiver * tanHalf), minRadius, maxRadius);
}

/// How lit [world] is by the point light that owns the cube atlas.
///
/// One, fully lit, when this is not that light or the atlas has nothing to say.
float PointShadowFactor(vec3 world, vec3 normal, int lightIndex) {
  int slot = int(point_shadow.slots[lightIndex].x + 0.5);
  if (point_shadow.slots[lightIndex].x < 0.0) return 1.0;
  float strength = point_shadow.params.z;
  if (strength <= 0.0) return 1.0;

  // Offset along the normal before measuring, and scaled by how steeply the
  // surface leans away from the light.
  //
  // A soft kernel on a tilted surface straddles a depth gradient: the taps at
  // one end of the disk are further from the light than the fragment itself,
  // so a flat offset that clears the surface head-on leaves acne at a grazing
  // angle. The slope term lifts the whole kernel clear instead, and is capped
  // because it runs away as the surface turns edge-on to the light — an
  // uncapped lift detaches the shadow from its caster.
  vec3 toLight = point_shadow.lights[slot].xyz - world;
  float toLightLength = max(length(toLight), 1e-6);
  float nDotL = max(dot(normal, toLight / toLightLength), 0.15);
  float slope = min(sqrt(max(1.0 - nDotL * nDotL, 0.0)) / (nDotL * nDotL), 8.0);
  // Both terms are metres. The slope term used to be the kernel radius, which
  // is a fraction of a tile — a unit error copied across from flutter_scene,
  // where the softness it borrows genuinely is the right quantity for their
  // map. Here it meant widening the kernel also lifted the sample off the
  // surface, by up to ten centimetres at the wider settings, so the softening
  // and the lift cancelled: tripling the kernel moved 184 pixels of the frame,
  // where the kernel alone moves thousands. It is what made contact hardening
  // look inert, and it was hiding in a comparison rather than in the estimate.
  vec3 origin = world + normal * point_shadow.params.w * (1.0 + slope);
  vec3 toFragment = origin - point_shadow.lights[slot].xyz;
  float distance = length(toFragment);
  float range = max(point_shadow.lights[slot].w, 1e-4);
  if (distance >= range) return 1.0;

  // The dominant axis picks the face, in the order the renderer wrote them:
  // +X, -X, +Y, -Y, +Z, -Z, left to right then top to bottom.
  //
  // A spot has one column and no choice to make. Asking the dominant axis
  // anyway would be worse than pointless: a fragment below and to the side of
  // a downlight has −Y dominant, which is column 3, and column 3 of a spot's
  // row is deliberately blank — so the whole cone would read as unshadowed
  // except for the wedge where the aim happens to be the dominant axis.
  int face = 0;
  if (point_shadow.slots[lightIndex].y < 0.5) {
    vec3 a = abs(toFragment);
    if (a.x >= a.y && a.x >= a.z) {
      face = toFragment.x > 0.0 ? 0 : 1;
    } else if (a.y >= a.z) {
      face = toFragment.y > 0.0 ? 2 : 3;
    } else {
      face = toFragment.z > 0.0 ? 4 : 5;
    }
  }

  vec4 clip = point_shadow.faces[slot * 6 + face] * vec4(origin, 1.0);
  if (clip.w <= 0.0) return 1.0;
  vec2 ndc = clip.xy / clip.w;
  if (abs(ndc.x) > 1.0 || abs(ndc.y) > 1.0) return 1.0;

  // v is flipped, the same way the directional map does it: the texture's
  // origin is at the top, where row zero of the render target is. Getting this
  // wrong does not tilt the shadow — it makes the top row of faces read the
  // bottom row, so a whole region compares against an unrelated distance and
  // comes out as a black slab.
  vec2 uv = vec2(ndc.x * 0.5 + 0.5, 0.5 - ndc.y * 0.5);
  // The face across, the light down: six tiles wide, four tall.
  vec2 tile = vec2(float(face), float(slot));

  float receiver = distance - point_shadow.params.y;

  // One rotation, shared by the blocker search and the filter. Per fragment,
  // so eight samples read as a soft edge rather than as eight copies of the
  // silhouette: without it every fragment along an edge tests the same eight
  // directions and the pattern shows.
  float noise = fract(52.9829189 * fract(dot(gl_FragCoord.xy,
                                            vec2(0.06711056, 0.00583715))));
  float angle = noise * 6.28318530718;
  float ca = cos(angle);
  float sa = sin(angle);

  // Guarded rather than read straight, because a zero here divides by zero and
  // a NaN radius poisons the filter into a black fragment. Zero is what an
  // unwritten channel holds, and "unwritten" is a state this block has been in
  // before: every slot is cleared to −1 each frame.
  float tanHalf = max(point_shadow.slots[lightIndex].z, 1e-4);

  float blocker = -1.0;
  float radius =
      PointShadowPenumbra(uv, tile, range, receiver, ca, sa, tanHalf, blocker);

  // The debug channel, and the reason it exists: two explanations for why the
  // estimate collapses were argued from the finished picture and both were
  // wrong, because the number that decides it never leaves this function.
  //
  // Red is how wide the penumbra came out, against the widest allowed. Green
  // is how far away the blocker was, against the light's range. Blue marks
  // the fragments where the search found nothing at all — which is a different
  // answer from "found something very close", and telling those two apart is
  // most of the question.
  if (point_shadow.params2.w > 0.5) {
    g_debug_surface_on = true;
    g_debug_surface = radius < 0.0
        ? vec3(0.0, 0.0, 1.0)
        : vec3(clamp(radius / max(point_shadow.params2.z, 1e-6), 0.0, 1.0),
               clamp(blocker / range, 0.0, 1.0), 0.0);
  }

  // The search found nothing between here and the light.
  if (radius < 0.0) return 1.0;

  float lit = PointShadowTap(uv, vec2(0.0), tile, range, receiver);
  if (radius > 0.0) {
    for (int i = 0; i < 8; i++) {
      lit += PointShadowTap(uv, PointShadowOffset(i, ca, sa, radius), tile,
                            range, receiver);
    }
    lit *= 1.0 / 9.0;
  }

  // Strength lerps towards fully lit, so the control is "how dark", not "how
  // much of the kernel" — the same convention the directional map uses.
  return mix(1.0, lit, clamp(strength, 0.0, 1.0));
}

#else

/// The stand-in for a model that declares none of the above.
///
/// Fully lit, which is what a model with no shadow term means, and a constant
/// the compiler folds rather than a branch anything pays for.
float PointShadowFactor(vec3 world, vec3 normal, int lightIndex) {
  return 1.0;
}

#endif  // F3D_NO_POINT_SHADOW

vec3 AccumulateLights(Surface s) {
  vec3 total = vec3(0.0);
  int count = LightCount();

  for (int i = 0; i < kMaxLights; i++) {
    if (i >= count) break;
    LightSample light = SampleLight(i, s);
    if (light.n_dot_l <= 0.0) continue;
    float visibility = LightVisibility(s, light, i) *
        PointShadowFactor(v_world_position, s.n, i);
    if (visibility <= 0.0) continue;
    total += ShadeLight(s, light) * light.radiance * light.n_dot_l * visibility;
  }

  return total;
}

#endif  // SURFACE_GLSL_
