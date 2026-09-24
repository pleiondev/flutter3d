// The scene's lights, for a stage a contributor draws rather than a surface —
// `N6`.
//
// A surface reads its lights out of `FragInfo`, a block that also carries a
// material, three shadow cascades and an environment: close to six kilobytes a
// stage cannot afford to declare for the sake of four arrays. This is those
// four arrays alone, in the order `FragInfo` holds them, plus the light list
// and its clusters from `lib/light_list.glsl`, which is the same one the lit
// models read. `ContributorLights.bind` on the Dart side writes both, from the
// same selection a mesh of the same bounds would be given.
//
// **No shadows, and no rectangle integral.** A particle is a translucent
// sprite: sampling a shadow map at a point inside a cloud of smoke answers a
// question about an opaque surface that is not there. A rectangular light is
// read as a point at its centre with the inverse square, which is the right
// answer at the distances a puff of smoke is from a window and the wrong one
// only close enough to touch it.

#ifndef CONTRIBUTOR_LIGHTS_GLSL_
#define CONTRIBUTOR_LIGHTS_GLSL_

#include <lib/light_list.glsl>

/// The slots a draw is handed, and the tail it may read past them. The same
/// eight and twenty-four as `kMaxLights` and `kExtraLights` in `surface.glsl`,
/// named apart so a stage may include both headers.
#define kContributorSlots 8
#define kContributorTail 24
#define kContributorLights (kContributorSlots + kContributorTail)

uniform ContributorLightInfo {
  /// xyz: world position. w: type, 0 directional 1 point 2 spot 3 rectangle.
  vec4 light_position[kContributorSlots];

  /// rgb: linear colour. w: intensity.
  vec4 light_color[kContributorSlots];

  /// xyz: the direction the light points. w: range, 0 unbounded.
  vec4 light_direction[kContributorSlots];

  /// x: cos(inner cone angle). y: cos(outer cone angle).
  vec4 light_cone[kContributorSlots];

  /// x: how many of the slots hold a light. yzw unused.
  vec4 slots;
}
contributor_light_info;

/// How many lights reach [world]: the draw's slots and its tail, or the
/// cell's tail when the view is clustered.
int ContributorLightCount(vec3 world) {
  float tail = light_list_info.list.x;
  if (Clustered()) {
    FindCluster(world);
    tail = g_cluster_count;
  }
  return clamp(int(contributor_light_info.slots.x + 0.5), 0,
               kContributorSlots) +
         clamp(int(tail + 0.5), 0, kContributorTail);
}

/// Light [index] as [world] receives it: [toLight] the unit direction towards
/// it, and [radiance] what arrives, zero for a light that does not reach.
///
/// Selects rather than early returns, for SPIR-V Cross's sake: a function that
/// returns a constant from two branches becomes a phi of constants it refuses.
void ContributorLight(int index, vec3 world, out vec3 toLight,
                      out vec3 radiance) {
  vec4 position;
  vec4 color;
  vec4 direction;
  vec4 cone;
  if (index < kContributorSlots) {
    position = contributor_light_info.light_position[index];
    color = contributor_light_info.light_color[index];
    direction = contributor_light_info.light_direction[index];
    cone = contributor_light_info.light_cone[index];
  } else {
    // The list's row, read the way `SampleLight` reads it: from the cell when
    // the view is clustered, skipping a light the slots already hold.
    int slot = index - kContributorSlots;
    bool clustered = Clustered();
    float listRow = clustered ? ClusterRow(slot) : LightListRow(slot);
    float v = (listRow + 0.5) * light_list_info.list.z;
    float u = light_list_info.list.y;
    position = textureLod(light_list_texture, vec2(0.5 * u, v), 0.0);
    color = textureLod(light_list_texture, vec2(1.5 * u, v), 0.0);
    direction = textureLod(light_list_texture, vec2(2.5 * u, v), 0.0);
    cone = textureLod(light_list_texture, vec2(3.5 * u, v), 0.0);
    color.w *= clustered ? (InSlots(listRow) ? 0.0 : 1.0)
                         : LightListScale(slot);
  }

  float type = position.w;
  bool directional = type < 0.5;
  vec3 offset = position.xyz - world;
  float distance = length(offset);
  vec3 aim = normalize(direction.xyz);

  // A light exactly at the point has no direction; it contributes nothing
  // rather than a NaN that spreads through the blend.
  bool degenerate = !directional && distance < 1e-6;
  toLight = directional ? -aim : offset / max(distance, 1e-6);

  // The glTF window, as `PunctualAttenuation` has it.
  float ratio = direction.w > 0.0 ? distance / direction.w : 0.0;
  float window = clamp(1.0 - ratio * ratio * ratio * ratio, 0.0, 1.0);
  float falloff = window * window / max(distance * distance, 1e-4);

  // A spot's ramp between its two cone cosines. Only a spot's direction is an
  // aim; a rectangle's is the edge of its panel.
  bool spot = type > 1.5 && type < 2.5;
  float ramp = spot ? clamp((dot(aim, -toLight) - cone.y) /
                                max(cone.x - cone.y, 1e-4),
                            0.0, 1.0)
                    : 1.0;

  float attenuation = directional ? 1.0 : (degenerate ? 0.0 : falloff * ramp);
  radiance = color.rgb * color.w * attenuation;
}

#endif  // CONTRIBUTOR_LIGHTS_GLSL_
