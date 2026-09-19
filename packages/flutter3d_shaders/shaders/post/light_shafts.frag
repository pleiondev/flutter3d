#version 460 core

// Volumetric light shafts, marched through the directional shadow map —
// `gfx-33n`.
//
// **What it draws, and why it is not a screen-brightness trick.** The
// familiar cheap version takes the bright pixels of the frame and smears them
// radially from the sun's position on screen. That needs the sun to be *in*
// the frame, it brightens anything else that happens to be bright, and it has
// no idea what is casting. This marches the view ray instead and asks the
// shadow map, at each step, whether that point in the air is lit. What comes
// out is a shaft where the light actually reaches and none where something is
// in the way — so a beam through a doorway is the doorway's shape, and
// turning the caster's shadow off leaves nothing at all.
//
// **Additive, and it reads the scene only for where to stop.** The in-scatter
// is added to the lit colour; the surface buffer's depth says how far along
// the ray there is still air to march. Past that the ray is inside geometry
// and anything accumulated would be light inside a wall.
//
// The dithered start is what makes sixteen steps look like a beam rather than
// sixteen bands. Each pixel starts a fraction of a step further along, from a
// 4x4 Bayer cell — ordered rather than random for the reason the dither in
// `composite.frag` is: it is a function of screen position and of nothing
// else, so a golden recorded with shafts on stays recorded.

in vec2 v_uv;

out vec4 frag_color;

uniform sampler2D scene_texture;
uniform sampler2D surface_texture;
uniform sampler2D shadow_texture;

uniform ShaftInfo {
  // Screen to world, for turning a stored depth back into a point.
  mat4 inverse_view_projection;

  // The three cascade matrices, world to light clip. Unused ones are the
  // identity and are never reached, because `cascades.z` says how many there
  // are.
  mat4 shadow_matrix;
  mat4 shadow_matrix_far;
  mat4 shadow_matrix_farthest;

  // xyz: where the eye is. w: how far to march, in world metres.
  vec4 camera;

  // xyz: the direction the camera looks. w: how many steps.
  vec4 forward;

  // xyz: the colour the air scatters, already multiplied by the strength.
  // w: unused.
  vec4 scatter;

  // x, y: the two cascade split distances. z: how many cascades. w: the
  // depth bias, in the same units the map holds.
  vec4 cascades;
}
shaft_info;

// One cell of a 4x4 Bayer matrix, in [0, 1). The same table
// `composite.frag` keeps, for the same reason.
float BayerCell(vec2 at) {
  int x = int(mod(at.x, 4.0));
  int y = int(mod(at.y, 4.0));
  int index = y * 4 + x;
  float value = 0.0;
  if (index == 0) value = 0.0;
  else if (index == 1) value = 8.0;
  else if (index == 2) value = 2.0;
  else if (index == 3) value = 10.0;
  else if (index == 4) value = 12.0;
  else if (index == 5) value = 4.0;
  else if (index == 6) value = 14.0;
  else if (index == 7) value = 6.0;
  else if (index == 8) value = 3.0;
  else if (index == 9) value = 11.0;
  else if (index == 10) value = 1.0;
  else if (index == 11) value = 9.0;
  else if (index == 12) value = 15.0;
  else if (index == 13) value = 7.0;
  else if (index == 14) value = 13.0;
  else value = 5.0;
  return value / 16.0;
}

// Whether [world] is lit by the caster: 1 in the light, 0 in shadow.
//
// The cascade walk `lib/shadow.glsl` does, without the surface it needs. A
// point in the air has no normal, so there is no normal offset here and no
// soft kernel either — one tap, because sixteen of them per pixel is already
// the cost of this pass.
float LitAt(vec3 world, float viewDistance) {
  int cascadeCount = int(shaft_info.cascades.z + 0.5);
  int cascade = 0;
  if (cascadeCount > 1 && viewDistance > shaft_info.cascades.x) cascade = 1;
  if (cascadeCount > 2 && viewDistance > shaft_info.cascades.y) cascade = 2;

  for (int attempt = 0; attempt < 3; attempt++) {
    int which = cascade + attempt;
    if (which >= cascadeCount) break;

    mat4 matrix = which == 0
        ? shaft_info.shadow_matrix
        : (which == 1 ? shaft_info.shadow_matrix_far
                      : shaft_info.shadow_matrix_farthest);
    vec4 lightSpace = matrix * vec4(world, 1.0);
    if (lightSpace.w <= 0.0) continue;
    vec3 candidate = lightSpace.xyz / lightSpace.w;

    vec2 inTile = vec2(candidate.x * 0.5 + 0.5, 0.5 - candidate.y * 0.5);
    if (inTile.x < 0.0 || inTile.x > 1.0 || inTile.y < 0.0 || inTile.y > 1.0) {
      continue;
    }
    if (candidate.z > 1.0) continue;

    vec2 uv = vec2((inTile.x + float(which)) / float(cascadeCount), inTile.y);
    // `textureLod`, for `shadow.glsl`'s own reason: the cascade search above
    // continues and breaks on values computed per fragment, so a WGSL backend
    // refuses the implicit derivative here as possibly non-uniform. One level,
    // so naming it directly changes no pixel.
    float stored = textureLod(shadow_texture, uv, 0.0).r;
    // Outside the map is lit rather than dark: a point beyond the shadow
    // volume has nothing recorded about it, and calling that shadow would
    // put a wall of darkness across the far half of every shaft.
    return candidate.z - shaft_info.cascades.w > stored ? 0.0 : 1.0;
  }
  return 1.0;
}

void main() {
  vec4 scene = texture(scene_texture, v_uv);
  int steps = int(shaft_info.forward.w + 0.5);
  if (steps < 1) {
    frag_color = scene;
    return;
  }

  // Where the ray starts and which way it goes.
  vec2 xy = vec2(v_uv.x * 2.0 - 1.0, 1.0 - v_uv.y * 2.0);
  vec4 nearH = shaft_info.inverse_view_projection * vec4(xy, 0.0, 1.0);
  vec4 farH = shaft_info.inverse_view_projection * vec4(xy, 1.0, 1.0);
  vec3 origin = nearH.xyz / nearH.w;
  vec3 along = normalize(farH.xyz / farH.w - origin);

  // How far there is air. The surface buffer holds depth along the view axis
  // in metres, so the distance along *this* ray is that over the cosine
  // between the two — a ray at the corner of the frame travels further than
  // the axis does to reach the same plane.
  float surfaceDepth = texture(surface_texture, v_uv).a;
  float cosine = max(dot(along, shaft_info.forward.xyz), 1e-4);
  float toSurface = surfaceDepth > 0.0 ? surfaceDepth / cosine : 1e9;
  float distance = min(shaft_info.camera.w, toSurface);
  if (distance <= 0.0) {
    frag_color = scene;
    return;
  }

  float stride = distance / float(steps);
  // The dithered start: a fraction of a step, so the banding sixteen samples
  // would otherwise draw is broken into a pattern the eye integrates.
  float offset = BayerCell(gl_FragCoord.xy) * stride;

  float lit = 0.0;
  for (int i = 0; i < 64; i++) {
    if (i >= steps) break;
    float travelled = offset + float(i) * stride;
    vec3 at = origin + along * travelled;
    lit += LitAt(at, travelled * cosine);
  }

  // The average share of the ray that was in light, times the scatter colour.
  // An average rather than a sum, so changing the step count changes the
  // quality and not the brightness.
  vec3 shaft = shaft_info.scatter.rgb * (lit / float(steps));
  frag_color = vec4(scene.rgb + shaft, scene.a);
}
