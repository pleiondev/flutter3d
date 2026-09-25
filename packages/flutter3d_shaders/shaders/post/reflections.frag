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
// encoded; b is perceptual roughness; a is the depth along the view axis in
// world metres — depth is here rather than in a depth texture because
// flutter_gpu cannot sample one, and it is in metres rather than a window depth
// because a half float cannot hold the second one usefully past a few metres.
//
// Roughness is why the normal is squeezed into two channels. Without it the
// shader reflects off rough stone as readily as off a wet floor, which is what
// the first version did: the walls of the crypt lit up and the floor did not.
precision highp float;

#include <lib/frag_coord_info.glsl>
#include <lib/blue_noise.glsl>

in vec2 v_uv;

out vec4 frag_color;

uniform sampler2D scene_texture;
uniform sampler2D surface_texture;
/// The scene's environment, which the lit pass has already reflected. Bound
/// always, to a one-texel cube when there is none, for the reason
/// `lib/pbr.glsl` gives: a declared sampler nobody binds is a crash on Metal.
uniform samplerCube environment_texture;

uniform ReflectionInfo {
  /// World to clip, and back. Both carry the framebuffer origin — see
  /// [UvFromNdc] — so neither is the camera's own matrix on every backend.
  mat4 view_projection;
  mat4 inverse_view_projection;
  /// xyz: camera position. w: unused.
  vec4 camera;
  /// xyz: the direction the camera looks, a unit vector in world space.
  /// w: unused. With [camera] it names the planes the buffer's depths measure
  /// against; see [WorldAt].
  vec4 forward;
  /// x: steps. y: stride in world metres. z: thickness in world metres.
  /// w: intensity.
  vec4 params;
  /// x: 1/width, y: 1/height, z: unused, w: 1 to show only what the march
  /// found, which is the only way to see whether it found anything.
  vec4 screen;
  /// The environment the lit pass reflected, so that a hit can take its place
  /// — see the end of [main]. x: its levels, nought when the lit pass read
  /// none. y: the strength it was read at, `Scene.ambientIntensity`. zw:
  /// unused.
  vec4 environment;
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

/// World position of the pixel at [uv], [depth] metres along the view axis.
///
/// **A ray crossing a plane**, because that is what the buffer holds now — see
/// `WriteSurfaceGeometry`. The inverse matrix gives both ends of the pixel's
/// ray; the stored depth names the plane the surface sits on, and every ray
/// crosses that plane once. A window depth in a half float could not name it at
/// range: past twenty metres its steps are wider than the differences this
/// march turns on.
///
/// Both ends rather than the camera and one end, so that an orthographic camera
/// — whose rays are parallel and meet nowhere — reconstructs correctly too.
/// `post/ssao.frag` says the same at more length.
///
/// y undoes [UvFromNdc], so that reconstructing the point a march projected
/// hands back the point it started from.
void PixelRay(vec2 uv, out vec3 origin, out vec3 along) {
  vec2 xy = vec2(uv.x * 2.0 - 1.0, 1.0 - uv.y * 2.0);
  vec4 nearH = reflection_info.inverse_view_projection * vec4(xy, 0.0, 1.0);
  vec4 farH = reflection_info.inverse_view_projection * vec4(xy, 1.0, 1.0);
  origin = nearH.xyz / nearH.w;
  along = normalize(farH.xyz / farH.w - origin);
}

vec3 WorldAt(vec2 uv, float depth) {
  vec3 origin, along;
  PixelRay(uv, origin, along);
  vec3 axis = reflection_info.forward.xyz;
  return origin +
         along * ((depth - dot(origin - reflection_info.camera.xyz, axis)) /
                  dot(along, axis));
}

/// How deep [at] is, in the metres the buffer holds.
float DepthOf(vec3 at) {
  return dot(at - reflection_info.camera.xyz, reflection_info.forward.xyz);
}

/// Where [at] lands in the textures this pass reads, or a negative x when it
/// is behind the camera.
vec2 UvOf(vec3 at) {
  vec4 clip = reflection_info.view_projection * vec4(at, 1.0);
  if (clip.w <= 0.0) return vec2(-1.0);
  return UvFromNdc(clip.xy / clip.w);
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
  // never sampled widely enough to blur. **Gone by 0.25, not by 0.45.** At a
  // perceptual roughness of 0.3 the GGX lobe is several degrees wide — tens of
  // centimetres of blur three metres out — and this pass has no blur: the old
  // window left such a floor a sharp mirror at 58% weight, which is where the
  // ghostly copies of objects standing on it came from.
  float polish = 1.0 - smoothstep(0.05, 0.25, roughness);
  if (polish <= 0.0) {
    frag_color = vec4(background, 1.0);
    return;
  }
  vec3 position = WorldAt(v_uv, surface.a);

  // Back along the ray this pixel looks down, rather than towards the camera
  // position. The two are the same thing under a perspective camera and are
  // not under an orthographic one, whose rays are parallel: there the vector to
  // the camera *position* leans further off the view axis the nearer a pixel is
  // to the edge of the frame, and every reflection in an isometric scene would
  // be angled by where it happened to sit on screen.
  vec3 rayOrigin, viewRay;
  PixelRay(v_uv, rayOrigin, viewRay);
  vec3 toEye = -viewRay;

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

  // **Started a jittered fraction of a stride out** — McGuire and Mara's
  // answer to the banding a fixed world stride leaves: neighbouring pixels
  // otherwise cross an object on the same step with the same overshoot, and
  // the reflection comes back as a stack of shifted copies of it. Half a
  // stride at least, off a centimetre of normal bias, so the first sample does
  // not land on the pixel it came from.
  float jitter = 0.5 + PixelNoise(TargetFragCoord());
  float travelled = stride * jitter;
  vec3 march = position + normal * 0.01 + ray * travelled;
  float reach = stride * (float(steps) + 0.5);
  vec3 hitColor = vec3(0.0);
  float hit = 0.0;

  for (int i = 0; i < 64; i++) {
    if (i >= steps) break;

    vec2 uv = UvOf(march);
    if (uv.x < -0.5) break;

    // Off screen is where this technique ends. Fading rather than cutting,
    // because a hard edge at the border of the frame is more distracting than
    // a missing reflection.
    if (uv.x < 0.0 || uv.x > 1.0 || uv.y < 0.0 || uv.y > 1.0) break;

    // **`textureLod` at level zero for every read inside this march.** The loop
    // breaks the moment a ray leaves the frustum or the frame, so no two
    // invocations of a quad are guaranteed to be on the same step, and a WGSL
    // backend will not derive a mip level under a branch like that. Both
    // textures are full-screen render targets with a single level and are read
    // at one texel per pixel, so level zero is what the derivative was
    // selecting; asking for it by name is the same picture.
    float sceneDepth = textureLod(surface_texture, uv, 0.0).a;
    // The march's own depth, in the same metres the buffer holds — so the two
    // are comparable without a projection between them.
    float marchDepth = DepthOf(march);
    // Behind whatever was drawn at this pixel, in metres both sides of the
    // comparison are already in.
    if (sceneDepth > 0.0 && marchDepth > sceneDepth) {
      // *How far* behind, in metres, and that is the whole fix. This used to
      // read the window-depth difference as a thickness, and a window-depth
      // difference is a different number of metres at every range: near the
      // camera 0.006 was a few centimetres and one stride stepped clean over
      // every surface in the frame, while at twenty metres it was several metres
      // and every ray passing in front of a distant wall "hit" it. That is why
      // the effect was off in every scene and looked wrong the moment it was
      // switched on. `ssao.frag` splits the same two questions the same way.
      //
      // The gap between the two points rather than between their depths: they
      // sit on one ray from the eye, and along a ray running away from the
      // camera a depth difference is shorter than the distance it stands for.
      // Thickness is a size in the world, so it is compared against one.
      vec3 seen = WorldAt(uv, sceneDepth);
      float behind = distance(march, seen);
      // A surface turned away from the ray is the back of something: the ray
      // would have met its front first, so it is not what this pixel sees.
      vec3 seenNormal = DecodeOctahedral(textureLod(surface_texture, uv, 0.0).rg);
      if (behind < thickness && dot(seenNormal, ray) < 0.0) {
        // **Refined before it is read.** The step that crossed the surface
        // overshot it by up to a stride; halving the last stride five times
        // lands within a thirty-second of it, so the colour is read where the
        // ray met the surface rather than where the step happened to stop.
        vec3 lo = march - ray * stride;
        vec3 hi = march;
        for (int j = 0; j < 5; j++) {
          vec3 mid = 0.5 * (lo + hi);
          vec2 at = UvOf(mid);
          float d = at.x < -0.5 ? 0.0 : textureLod(surface_texture, at, 0.0).a;
          if (d > 0.0 && DepthOf(mid) > d) {
            hi = mid;
          } else {
            lo = mid;
          }
        }
        vec2 hitUv = UvOf(hi);
        if (hitUv.x < -0.5) hitUv = uv;
        hitColor = textureLod(scene_texture, hitUv, 0.0).rgb;
        // Fade at the edges of the frame, and with the length of the ray: a
        // hit at the far end of the march weighs nothing, so the reflection
        // thins out instead of stopping where the march does (three.js's
        // `(1 - d / max)^2`).
        vec2 edge = abs(hitUv * 2.0 - 1.0);
        float border = 1.0 - max(edge.x, edge.y);
        float along = clamp(1.0 - travelled / reach, 0.0, 1.0);
        hit = smoothstep(0.0, 0.15, border) * along * along;
        break;
      }
    }

    march += ray * stride;
    travelled += stride;
  }

  // Schlick's Fresnel for a dielectric, F0 = 0.04: four percent head-on, all
  // of it at grazing. The buffer carries no metalness to tint it with. This
  // used to floor at fifteen percent with a fourth power, which put nearly
  // four times the reflection on a floor seen from above.
  float fresnel = 0.04 + 0.96 * pow(1.0 - facing, 5.0);
  vec3 reflection = hitColor * hit * intensity * polish * fresnel;
  float confidence = hit * polish;
  // **A hit replaces the environment's reflection rather than adding to it.**
  // The lit colour already holds the environment's specular wherever the
  // scene has one: the metal-rough stage reflects the cube along this same
  // ray, prefiltered to this roughness. Adding the hit on top made every
  // reflected object a second reflection laid over the sky's, brighter than
  // the light there is and see-through where it should hide the sky behind
  // it. So the cube is read here the way the lit pass read it and taken
  // away in the share the hit is trusted, which leaves the environment
  // wherever the march found nothing. Weighted by this pass's Fresnel for
  // both, so the swap stays a swap; the lit pass's own weight differs a
  // little, and the difference is what stays of the sky.
  //
  // What is taken away is an estimate of what was added, read from the
  // scene's own cube: this pass cannot tell which pixels a probe lit instead,
  // so the renderer sends no levels while the scene has probes, and a surface
  // shaded by a model with no environment term (Lambert, Phong, toon) loses a
  // share it never had. Hence the clamp at nought, applied only when
  // something is taken, so a scene with no environment is the sum it was.
  float levels = reflection_info.environment.x;
  vec3 environment =
      levels > 0.0
          ? textureLod(environment_texture, ray, roughness * levels).rgb *
                reflection_info.environment.y
          : vec3(0.0);
  vec3 replaced = environment * confidence * fresnel;
  vec3 composed = levels > 0.0 ? max(scene + reflection - replaced, vec3(0.0))
                               : scene + reflection;
  frag_color = vec4(debugOnly ? reflection : composed, 1.0);
}
