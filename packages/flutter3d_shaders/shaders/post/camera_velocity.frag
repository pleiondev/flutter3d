#version 460 core

// How far each pixel moved on screen since the last frame, because the
// camera moved — `R1`.
//
// **Reconstructed rather than drawn.** Everything that stood still in the
// world moved on screen only because the camera did, and for those pixels
// the answer is arithmetic: take the point the surface buffer stored, carry
// it through last frame's view-projection, and the difference between where
// it lands and where it is now is its motion. The object pass draws over
// this only where a node itself moved.
//
// **Both matrices are the unjittered ones.** The resolve wants the motion of
// the picture, and the jitter is a deliberate wobble of the sampling grid
// that the history averages out; counting it as motion would make a still
// scene reproject by a fraction of a pixel every frame and never settle.
//
// The answer is in UV units, now minus then: the resolve reads history at
// `v_uv - velocity`. Red and green carry it; blue is zero and alpha one, so
// the target reads back as a picture.

in vec2 v_uv;

out vec4 frag_color;

uniform sampler2D surface_texture;

uniform CameraVelocityInfo {
  /// This frame's screen to world, for turning a stored depth into a point.
  /// Carries the framebuffer origin, as `ContactShadowInfo`'s does.
  mat4 inverse_view_projection;

  /// Last frame's world to screen, with the same origin.
  mat4 previous_view_projection;

  /// xyz: where the eye is now.
  vec4 camera;

  /// xyz: the direction the camera looks now, a unit vector.
  vec4 forward;
}
velocity_info;

vec2 UvFromNdc(vec2 ndc) {
  return vec2(ndc.x * 0.5 + 0.5, 0.5 - ndc.y * 0.5);
}

void main() {
  vec4 surface = texture(surface_texture, v_uv);

  vec2 xy = vec2(v_uv.x * 2.0 - 1.0, 1.0 - v_uv.y * 2.0);
  vec4 nearH = velocity_info.inverse_view_projection * vec4(xy, 0.0, 1.0);
  vec4 farH = velocity_info.inverse_view_projection * vec4(xy, 1.0, 1.0);
  vec3 origin = nearH.xyz / nearH.w;
  vec3 along = normalize(farH.xyz / farH.w - origin);

  // The sky is at infinity, so only the camera's turning moves it: a
  // direction carried through last frame's matrix with w zero, which drops
  // the translation exactly.
  vec4 then;
  if (surface.a <= 0.0) {
    then = velocity_info.previous_view_projection * vec4(along, 0.0);
  } else {
    vec3 axis = velocity_info.forward.xyz;
    vec3 world =
        origin +
        along * ((surface.a - dot(origin - velocity_info.camera.xyz, axis)) /
                 dot(along, axis));
    then = velocity_info.previous_view_projection * vec4(world, 1.0);
  }

  // Behind last frame's eye: nothing on screen then to reproject from, and
  // no motion is the answer that leaves the resolve to reject the history
  // by depth instead.
  if (then.w <= 0.0) {
    frag_color = vec4(0.0, 0.0, 0.0, 1.0);
    return;
  }
  frag_color = vec4(v_uv - UvFromNdc(then.xy / then.w), 0.0, 1.0);
}
