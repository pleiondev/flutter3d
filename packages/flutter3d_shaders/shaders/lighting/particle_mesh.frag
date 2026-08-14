#version 460 core

// Mesh particles: additive, fogged, and shaded by which way each face points.
//
// ## Why there is a facing term at all
//
// The billboard path needs none: its quad is a procedural disc, so the falloff
// from the middle to the edge is what gives a sprite its form. A mesh has no
// such coordinate, and additive blending flattens everything it touches — every
// face adds the same colour, so a tumbling shard comes back as a solid
// silhouette of its own outline. It reads as a hole in the world rather than as
// an object.
//
// One term fixes it: how squarely a face points at the eye. A face turned away
// contributes less, so the shape's own geometry separates itself, and a shard
// spinning through a torch's light flickers because its faces do.
//
// **This is not lighting.** It reads no light in the scene, casts nothing, and
// receives nothing; the same shape is equally bright in a dark corridor. That
// is deliberate: an additive particle is *emissive by definition* — it adds to
// what is behind it — and shading one by the room's lights would mean binding
// the whole lit path's uniform set to something that has no business being lit.

in vec4 v_color;
in vec3 v_world_position;
in vec3 v_normal;

out vec4 frag_color;

/// The same block the other particle stage declares, for the same reason: this
/// shader shares none of the lit shaders' headers.
uniform FogInfo {
  /// rgb: linear fog colour. w: density per metre, zero for no fog.
  vec4 fog;

  /// xyz: camera position in world space.
  vec4 eye;
}
fog_info;

void main() {
  vec3 to_eye = fog_info.eye.xyz - v_world_position;
  float distance_to_eye = length(to_eye);

  // `abs`, not `max(dot, 0)`. Nothing here is culled — a particle mesh is seen
  // from every side as it tumbles — so a back face is as visible as a front
  // one, and clamping would make half of every shard go black rather than dim.
  vec3 n = normalize(v_normal);
  float facing = distance_to_eye > 0.0
      ? abs(dot(n, to_eye / distance_to_eye))
      : 1.0;

  // Never all the way to zero. A silhouette edge is exactly perpendicular to
  // the eye, and a face that vanished there would carve a dark seam across the
  // shape at precisely the place the eye is best at noticing one.
  float intensity = mix(0.35, 1.0, facing);

  // Attenuation rather than a mix, for the reason spelled out in
  // lighting/particle.frag: blending toward the fog colour makes a distant
  // additive particle *add* fog to the wall behind it.
  float fogged = 1.0;
  if (fog_info.fog.w > 0.0) {
    fogged = clamp(exp(-fog_info.fog.w * distance_to_eye), 0.0, 1.0);
  }

  frag_color = vec4(v_color.rgb * v_color.a * intensity * fogged, 1.0);
}
