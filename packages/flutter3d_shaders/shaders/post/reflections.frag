#version 460 core

// Screen-space reflections.
//
// Reflects what is already on screen, and nothing else. That is the whole
// bargain: a torch behind the camera does not appear in the floor, and a
// surface at a grazing angle reflects a stretched smear of whatever the ray
// happened to hit. It is bought cheaply — one texture read per march step, no
// second pass over the geometry, no cube maps and so no mip levels, which this
// channel does not have.
//
// The surface buffer is what makes it possible at all: a forward renderer
// throws its normals away inside the fragment shader, and there is nothing to
// reflect against without them. rg is the world-space normal, octahedrally
// encoded; b is perceptual roughness; a is window depth — depth is here rather
// than in a depth texture because flutter_gpu cannot sample one.
//
// Roughness is why the normal is squeezed into two channels. Without it the
// shader reflects off rough stone as readily as off a wet floor, which is what
// the first version did: the walls of the crypt lit up and the floor did not.
precision highp float;

in vec2 v_uv;

out vec4 frag_color;

uniform sampler2D scene_texture;
uniform sampler2D surface_texture;

uniform ReflectionInfo {
  /// World to clip, and back. Both carry the framebuffer origin — see
  /// [UvFromNdc] — so neither is the camera's own matrix on every backend.
  mat4 view_projection;
  mat4 inverse_view_projection;
  /// xyz: camera position. w: unused.
  vec4 camera;
  /// x: steps. y: stride in world metres. z: thickness in world metres.
  /// w: intensity.
  vec4 params;
  /// x: 1/width, y: 1/height, z: unused, w: 1 to show only what the march
  /// found, which is the only way to see whether it found anything.
  vec4 screen;
}
reflection_info;

vec3 DecodeOctahedral(vec2 e) {
  e = e * 2.0 - 1.0;
  vec3 n = vec3(e.xy, 1.0 - abs(e.x) - abs(e.y));
  float t = max(-n.z, 0.0);
  n.x += n.x >= 0.0 ? -t : t;
  n.y += n.y >= 0.0 ? -t : t;
  return normalize(n);
}

/// Where a point at clip-space [ndc] lands in the textures this pass reads.
///
/// **v runs the other way from y, and the matrix is what makes that true on
/// both backends.** Row zero of a rendered texture is its top on Impeller and
/// its bottom in WebGL, so the conversion cannot be written once for both in
/// GLSL — `toFramebufferOrigin` negates y in the matrix handed down here for
/// the backend that needs it, exactly as it does for the shadow lookup in
/// `lib/surface.glsl`, which has used this convention all along.
///
/// This pass used the opposite one — `ndc * 0.5 + 0.5`, with an unadjusted
/// matrix — and was therefore right in a browser and mirrored top to bottom
/// everywhere else: the march read the surface buffer at the pixel reflected
/// about the middle of the frame, found nothing there that had anything to do
/// with the ray, and drew a reflection of whatever happened to be in the way.
vec2 UvFromNdc(vec2 ndc) {
  return vec2(ndc.x * 0.5 + 0.5, 0.5 - ndc.y * 0.5);
}

/// World position of the pixel at [uv] with window depth [depth].
vec3 WorldAt(vec2 uv, float depth) {
  // Depth runs 0..1 here rather than -1..1: Impeller is Metal-like, and using
  // the OpenGL convention puts every reconstructed point behind the camera.
  //
  // y undoes [UvFromNdc], so that reconstructing the point a march projected
  // hands back the point it started from.
  vec4 ndc = vec4(uv.x * 2.0 - 1.0, 1.0 - uv.y * 2.0, depth, 1.0);
  vec4 world = reflection_info.inverse_view_projection * ndc;
  return world.xyz / world.w;
}

void main() {
  vec4 surface = texture(surface_texture, v_uv);
  vec3 scene = texture(scene_texture, v_uv).rgb;

  // Nothing was drawn here: the buffer is cleared to zero and a zero alpha is
  // the sky, not a surface at the near plane.
  bool debugOnly = reflection_info.screen.w > 0.5;
  vec3 background = debugOnly ? vec3(0.0) : scene;

  if (surface.a <= 0.0) {
    frag_color = vec4(background, 1.0);
    return;
  }

  vec3 normal = DecodeOctahedral(surface.rg);
  float roughness = surface.b;

  // Rough surfaces scatter: a sharp screen-space reflection off one is a lie,
  // and the honest thing is to stop rather than to blur something that was
  // never sampled widely enough to blur.
  float polish = 1.0 - smoothstep(0.18, 0.45, roughness);
  if (polish <= 0.0) {
    frag_color = vec4(background, 1.0);
    return;
  }
  vec3 position = WorldAt(v_uv, surface.a);
  vec3 toEye = normalize(reflection_info.camera.xyz - position);

  // Facing away, or so nearly edge-on that the march would crawl along the
  // surface it started from.
  float facing = dot(normal, toEye);
  if (facing <= 0.05) {
    frag_color = vec4(background, 1.0);
    return;
  }

  vec3 ray = reflect(-toEye, normal);

  int steps = int(reflection_info.params.x);
  float stride = reflection_info.params.y;
  float thickness = reflection_info.params.z;
  float intensity = reflection_info.params.w;

  // Started one stride out. Beginning at the surface makes the first sample
  // hit the pixel we came from, and every surface reflects itself.
  vec3 march = position + normal * 0.02 + ray * stride;
  vec3 hitColor = vec3(0.0);
  float hit = 0.0;
  float travelled = stride;

  for (int i = 0; i < 64; i++) {
    if (i >= steps) break;

    vec4 clip = reflection_info.view_projection * vec4(march, 1.0);
    if (clip.w <= 0.0) break;
    vec3 ndc = clip.xyz / clip.w;
    vec2 uv = UvFromNdc(ndc.xy);

    // Off screen is where this technique ends. Fading rather than cutting,
    // because a hard edge at the border of the frame is more distracting than
    // a missing reflection.
    if (uv.x < 0.0 || uv.x > 1.0 || uv.y < 0.0 || uv.y > 1.0) break;

    float sceneDepth = texture(surface_texture, uv).a;
    // Behind whatever was drawn at this pixel. Ordering is the one thing
    // window depth is good for: it is monotonic in distance, so the sign of
    // this comparison is exact at any range.
    if (sceneDepth > 0.0 && ndc.z > sceneDepth) {
      // *How far* behind, in metres, and that is the whole fix. This used to
      // read the window-depth difference as a thickness, and a window-depth
      // difference is a different number of metres at every range: near the
      // camera 0.006 was a few centimetres and one stride stepped clean over
      // every surface in the frame, while at ten metres it was several metres
      // and every ray passing in front of a distant wall "hit" it. That is why
      // the effect was off in every scene and looked wrong the moment it was
      // switched on. `ssao.frag` splits the same two questions the same way,
      // and says why on its own range check.
      //
      // The marched point and the recorded surface lie on one ray from the eye
      // — the surface is reconstructed at the uv the march projected to — so
      // the difference of their distances from the camera is the gap between
      // them along that ray, with no view matrix needed.
      vec3 seen = WorldAt(uv, sceneDepth);
      float behind = distance(reflection_info.camera.xyz, march) -
                     distance(reflection_info.camera.xyz, seen);
      if (behind < thickness) {
        hitColor = texture(scene_texture, uv).rgb;
        // Fade at the edges of the frame and with distance travelled, so a
        // reflection thins out instead of stopping.
        vec2 edge = abs(uv * 2.0 - 1.0);
        float border = 1.0 - max(edge.x, edge.y);
        hit = smoothstep(0.0, 0.15, border);
        break;
      }
    }

    march += ray * stride;
    travelled += stride;
  }

  // Grazing angles reflect more, straight-on less: the Fresnel term, minus the
  // parts that need a material.
  float fresnel = pow(1.0 - facing, 4.0);
  vec3 reflection = hitColor * hit * intensity * polish * (0.15 + 0.85 * fresnel);
  frag_color = vec4(debugOnly ? reflection : scene + reflection, 1.0);
}
