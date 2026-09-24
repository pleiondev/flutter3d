#version 460 core

// Contact shadows: a short march toward the light, in screen space —
// `gfx-76n`.
//
// **What a shadow map cannot do at any resolution.** A box resting on a plane
// meets it along a line, and the shadow that belongs at that line is a texel
// wide or less. Raise the map's resolution and the line moves closer to right
// without arriving; raise the bias enough to stop the acne a tight contact
// produces and the shadow detaches from the object entirely — which is the
// familiar look of a prop floating a centimetre above the floor. The gap is
// structural, and the answer everywhere is to stop asking the map about the
// first few centimetres and march the depth buffer instead.
//
// **Not contact *hardening*, which this repository already has.** `shadow.glsl`
// searches for blockers and sizes its penumbra from what it finds, so a shadow
// is sharp where its caster is close. That is a different thing with a
// confusingly similar name, and it is the grep hit that made a survey record
// this row as already done.
//
// **The march is the same arithmetic `ssao.frag` does**, with one direction
// instead of a hemisphere: reconstruct the surface point from the buffer's
// depth, step toward the light in world metres, project each step back into the
// buffer, and compare in metres. Everything about why — the reconstruction as a
// ray crossing a plane, the comparison in metres rather than window depth,
// `textureLod` at level zero — is written out there and holds here unchanged.
//
// The strength is not applied here. It lives in the composite, for the reason
// the occlusion's does: "off" has to mean a multiplier of exactly one, and that
// is a property of a `mix` in one place rather than of arithmetic in two.

// A fullscreen stage declares its own varying and its own output, the way
// every other pass in this directory does: `lib/color.glsl` is the mesh
// fragment's preamble and brings a surface this pass does not have.
#include <lib/frag_coord_info.glsl>
#include <lib/blue_noise.glsl>

in vec2 v_uv;

out vec4 frag_color;

uniform sampler2D surface_texture;

uniform ContactShadowInfo {
  /// Screen to world, for turning a stored depth back into a point.
  mat4 inverse_view_projection;

  /// World to screen, for finding where a marched point lands.
  mat4 view_projection;

  /// x: how far to march, in world metres. y: how many steps.
  /// z: how thick an occluder is assumed to be, in metres — a surface nearer
  /// than the ray by more than this is something else in front rather than the
  /// thing casting. w: bias in metres, which lifts the ray off its own surface.
  vec4 params;

  /// xyz: where the eye is. w unused.
  vec4 camera;

  /// xyz: the direction the camera looks, a unit vector. The normal of the
  /// planes the stored depth measures against.
  vec4 forward;

  /// xyz: the direction *to* the light, a unit vector in world space — the
  /// reverse of the direction a directional light points. w unused.
  ///
  /// One light and not eight. A march is a march per light, and eight of them
  /// per pixel is a different pass with a different budget; the sun is the one
  /// whose contact is missing from a shadow map that has to cover a level.
  vec4 to_light;
}
contact_info;

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
/// v runs the other way from y, and the matrices carry the framebuffer origin
/// — `ssao.frag` says at length what going the other way costs.
vec2 UvFromNdc(vec2 ndc) {
  return vec2(ndc.x * 0.5 + 0.5, 0.5 - ndc.y * 0.5);
}

/// Where the depth stored for [uv] is, in the world.
vec3 WorldAtDepth(vec2 uv, float depth) {
  vec2 xy = vec2(uv.x * 2.0 - 1.0, 1.0 - uv.y * 2.0);
  vec4 nearH = contact_info.inverse_view_projection * vec4(xy, 0.0, 1.0);
  vec4 farH = contact_info.inverse_view_projection * vec4(xy, 1.0, 1.0);
  vec3 origin = nearH.xyz / nearH.w;
  vec3 along = normalize(farH.xyz / farH.w - origin);
  vec3 axis = contact_info.forward.xyz;
  return origin +
         along * ((depth - dot(origin - contact_info.camera.xyz, axis)) /
                  dot(along, axis));
}

/// How deep [at] is, in the metres the buffer holds.
float DepthOf(vec3 at) {
  return dot(at - contact_info.camera.xyz, contact_info.forward.xyz);
}

void main() {
  vec4 surface = texture(surface_texture, v_uv);

  // Nothing was drawn here. The buffer is cleared to zero and a zero alpha is
  // the sky, not a surface sitting on the near plane.
  if (surface.a <= 0.0) {
    frag_color = vec4(1.0);
    return;
  }

  vec3 normal = DecodeOctahedral(surface.rg);
  vec3 toLight = normalize(contact_info.to_light.xyz);

  // A surface already facing away from the light is unlit by the light term
  // itself, and marching from it would find its own far side. Returning one
  // leaves it to the lighting, which is the half that knows about the normal.
  if (dot(normal, toLight) <= 0.0) {
    frag_color = vec4(1.0);
    return;
  }

  float reach = max(contact_info.params.x, 1e-4);
  int steps = clamp(int(contact_info.params.y + 0.5), 1, 16);
  float thickness = max(contact_info.params.z, 1e-4);

  // Lifted along the normal, in metres, for `ssao.frag`'s reason: a bias in
  // window depth is a different number of millimetres at every distance.
  vec3 origin = WorldAtDepth(v_uv, surface.a) + normal * contact_info.params.w;
  float stride = reach / float(steps);

  // **Jittered by a Bayer cell**, as Unreal's march is by its dither and
  // Bend's by its offsets: eight fixed steps otherwise quantise the fade
  // below into eight flat levels, a staircase across every penumbra. Each
  // sample lands somewhere in its own step rather than at its end. A pattern
  // rather than a hash so the software backend matches bit for bit.
  float jitter = PixelNoise(TargetFragCoord());

  // **A tolerance at least twice what one step moves in depth**, as Unreal's
  // `CompareTolerance`: a ray running steeply away from the camera crosses
  // more depth per step than a fixed thickness, and a thin blocker passed
  // between two samples was never found.
  float stepDepth = abs(DepthOf(origin + toLight * stride) - DepthOf(origin));
  float tolerance = max(thickness, 2.0 * stepDepth);

  for (int i = 0; i < 16; i++) {
    if (i >= steps) break;

    float along = float(i) + 1.0 - jitter;
    vec3 at = origin + toLight * (stride * along);
    vec4 clip = contact_info.view_projection * vec4(at, 1.0);
    // Behind the eye: the march has left the frame, and a division by a
    // negative w would fold it back into view somewhere it is not.
    if (clip.w <= 0.0) break;
    vec2 uv = UvFromNdc(clip.xy / clip.w);
    // Off the edge of the buffer. Nothing is known out there, and guessing
    // would put a dark rim around every frame.
    if (uv.x < 0.0 || uv.x > 1.0 || uv.y < 0.0 || uv.y > 1.0) break;

    vec4 there = textureLod(surface_texture, uv, 0.0);
    if (there.a <= 0.0) continue;

    float marched = DepthOf(at);
    float gap = marched - there.a;
    // In front of the ray, and not so far in front that it is a different
    // object seen past the one casting: without the thickness test a wall four
    // metres nearer than the floor shadows everything the ray crosses, which
    // is the same halo `ssao.frag`'s range check exists to stop.
    if (gap > 0.0 && gap < tolerance) {
      // **Darker the nearer the blocker, which is what makes this a contact
      // shadow rather than a stencil.** A hit on the first step is a surface
      // touching this one and gets nothing; a hit at the far end of the march
      // is most of a metre away and barely counts. Without the fade the pass
      // writes zero or one and the march's own reach becomes a visible edge on
      // the floor — a hard band that ends where the loop does, which is a
      // number in a settings object rather than anything in the scene.
      frag_color = vec4(max(along - 1.0, 0.0) / float(steps));
      return;
    }
  }

  frag_color = vec4(1.0);
}
